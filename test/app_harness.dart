import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/bootstrap.dart';
import 'package:mirqat/core/constants/app_constants.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/core/router/app_router.dart';
import 'package:mirqat/features/splash/screen/splash_screen.dart';
import 'package:mirqat/main.dart';
import 'package:mirqat/services/audio/ayah_duration_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Real clip lengths for Ahmed Khalil Shaheen's Al-Fatiha, so the session
/// summary is exercised with the same numbers the app would measure.
/// The real service probes through just_audio, which has no implementation
/// under `flutter test`.
class FakeAyahDurationService implements AyahDurationService {
  static const Map<int, Duration> fatiha = <int, Duration>{
    1: Duration(milliseconds: 3527),
    2: Duration(milliseconds: 3918),
    3: Duration(milliseconds: 2795),
    4: Duration(milliseconds: 2821),
    5: Duration(milliseconds: 4676),
    6: Duration(milliseconds: 3657),
    7: Duration(milliseconds: 14106),
  };

  @override
  Future<Map<int, Duration>> durationsFor({
    required Reciter reciter,
    required Surah surah,
  }) async => fatiha;

  @override
  AudioPlayer? probe;

  @override
  Future<void> dispose() async {}
}

/// Reads the catalog straight off disk.
///
/// Under `testWidgets` the fake-async zone does not reliably complete a
/// `rootBundle` read, which leaves every screen on its spinner from the second
/// test in a file onward. The real bundle path is covered by
/// `test/data/quran_catalog_test.dart`; here the concern is the UI.
class FileAssetReader implements AssetReader {
  const FileAssetReader();

  @override
  Future<String> loadString(String path) async {
    final File file = File(path);
    if (!file.existsSync()) {
      throw AssetNotFoundException(path, 'No file at "$path".');
    }
    return file.readAsStringSync();
  }
}

/// Loads translations off disk instead of through `rootBundle`.
///
/// Same reason as [FileAssetReader]: a `rootBundle` read does not reliably
/// complete inside the fake-async zone `testWidgets` runs in, which leaves the
/// app blank or stuck loading from the second test in a file onward.
class FileTranslationLoader extends AssetLoader {
  const FileTranslationLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final File file = File('$path/${locale.languageCode}.json');
    if (!file.existsSync()) return null;
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }
}

/// Boots the app the way `main` does, against a throwaway Hive directory.
///
/// Hive is initialised once per test file rather than per test: closing and
/// re-initialising it between tests leaves boxes that never reopen, and every
/// screen then sits on its loading spinner forever. State is reset by clearing
/// the boxes instead.
class AppHarness {
  const AppHarness._();

  static Directory? _storageDir;
  static bool _localizationReady = false;
  static bool _sqfliteFfiReady = false;

  static Future<AppHarness> start() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // `sqflite` is a platform-channel plugin with no implementation under
    // `flutter test`; QuranDatabase is overridden below to open through this
    // in-process engine instead, same reasoning as every other override here.
    if (!_sqfliteFfiReady) {
      sqfliteFfiInit();
      _sqfliteFfiReady = true;
    }

    // easy_localization persists the chosen locale through shared_preferences,
    // which has no plugin implementation under `flutter test`. The binding
    // clears mock handlers between tests, so this is re-registered each time.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (MethodCall call) async =>
              call.method == 'getAll' ? <String, Object>{} : null,
        );

    if (!_localizationReady) {
      await EasyLocalization.ensureInitialized();
      _localizationReady = true;
    }

    if (_storageDir == null) {
      _storageDir = Directory.systemTemp.createTempSync('mirqat_ui');
      Hive.init(_storageDir!.path);
    }

    await sl.reset();
    await configureDependencies();

    // The harness has just done by hand what AppBootstrap does, so the app
    // must not do it again — opening the boxes twice would fight this setup.
    AppBootstrap.overrideWith(Future<void>.value());

    // Swap in measured durations rather than probing audio, which has no
    // plugin implementation under `flutter test`.
    sl.unregister<AyahDurationService>();
    sl.registerLazySingleton<AyahDurationService>(FakeAyahDurationService.new);

    sl.unregister<AssetReader>();
    sl.registerLazySingleton<AssetReader>(FileAssetReader.new);

    // quran.db is opened through sqflite, which has no plugin implementation
    // under `flutter test`. Two more constraints, same family as the
    // AssetReader swap above: the no-isolate ffi factory, because a reply from
    // a background isolate never arrives inside the fake-async zone
    // `testWidgets` runs in; and opening here, in `setUp`'s real zone, because
    // the first open copies the asset out with real file I/O.
    final QuranDatabase quranDatabase = QuranDatabase(
      factory: databaseFactoryFfiNoIsolate,
      resolveStorageDirectory: () async => _storageDir!,
    );
    await quranDatabase.open();
    sl.unregister<QuranDatabase>();
    sl.registerLazySingleton<QuranDatabase>(() => quranDatabase);

    // A sqflite query still does not reliably complete when a screen first
    // loads inside pure fake-async pumps (the splash hand-off has no runAsync
    // around it). The catalog source caches both lists, so reading them here,
    // in the real zone, leaves every later read an already-completed future.
    final QuranLocalDataSource catalog = sl<QuranLocalDataSource>();
    for (final Surah surah in await catalog.getSurahs()) {
      await catalog.getAyahs(surah.number);
    }

    await Hive.box<Map<dynamic, dynamic>>(AppConstants.progressBoxName).clear();
    await Hive.box<Map<dynamic, dynamic>>(AppConstants.settingsBoxName).clear();

    return const AppHarness._();
  }

  Future<void> stop() async => sl.reset();

  /// Call from `tearDownAll`.
  static Future<void> disposeAll() async {
    await sl.reset();
    await Hive.close();
    final Directory? dir = _storageDir;
    _storageDir = null;
    if (dir != null && dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Pumps a fresh app.
  ///
  /// The blank frame first is what makes this a restart: pumping the same
  /// widget type again would reuse the element tree, and the app would come
  /// back sitting on whatever route the last test navigated to.
  Future<void> pumpApp(
    WidgetTester tester, {
    Locale locale = AppLocalization.arabic,
    bool skipSplash = true,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(locale: locale));
    // One frame, not `settle`: the splash's sun breathes on a repeating
    // controller, so while it is on screen there is always another frame
    // scheduled and `pumpAndSettle` can never return. Get past it first.
    await tester.pump();
    if (!skipSplash) {
      // Stop on the splash. Settling is impossible while it is mounted — the
      // sun breathes on a repeating controller, so a frame is always
      // scheduled — and a caller that asked to see the splash must drive it
      // with explicit `pump(duration)` calls.
      return;
    }
    await dismissSplash(tester);
    await settle(tester);
  }

  /// Taps through the launch animation and waits for the home screen.
  ///
  /// The splash is the app's first route now, so every test that wants a
  /// screen behind it has to get past it. Tapping is how a person skips it,
  /// which means the skip path is exercised by the whole suite rather than by
  /// one test — and it costs a frame instead of the animation's 2.4 s.
  ///
  /// Pass `skipSplash: false` to [pumpApp] to test the splash itself.
  static Future<void> dismissSplash(WidgetTester tester) async {
    final Finder splash = find.byType(SplashScreen);
    if (!tester.any(splash)) return;

    // Explicit pumps throughout, never `pumpAndSettle`: the breathing sun
    // keeps scheduling frames until the splash is disposed, so settling is
    // only possible once it is gone.
    await tester.runAsync(() async {
      await tester.tap(splash);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();                          // the `go` is processed
    await tester.pump(AppRouter.splashFadeOut);   // the 300 ms dissolve
    await tester.pump();
  }

  /// Taps and waits.
  ///
  /// The tap runs inside `runAsync` because anything that writes to Hive is
  /// real disk I/O, and a real Future never completes inside the fake-async
  /// zone `testWidgets` runs in — the call would simply hang.
  static Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
  }

  /// Waits out a screen's load.
  ///
  /// `pumpAndSettle` never returns while a CircularProgressIndicator is on
  /// screen — it animates forever — so the spinner is pumped away in slices
  /// first. The explicit timeout keeps a genuine hang from stalling the run
  /// for the default ten minutes.
  static Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (!tester.any(find.byType(CircularProgressIndicator))) break;
    }
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 10),
    );
  }

  Widget app({Locale locale = AppLocalization.arabic}) => EasyLocalization(
    supportedLocales: AppLocalization.supportedLocales,
    path: AppLocalization.translationsPath,
    startLocale: locale,
    fallbackLocale: AppLocalization.fallbackLocale,
    assetLoader: const FileTranslationLoader(),
    child: const IqraWartaqApp(),
  );
}
