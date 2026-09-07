import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tahfiz/core/constants/app_constants.dart';
import 'package:tahfiz/core/di/injection.dart';
import 'package:tahfiz/core/error/exceptions.dart';
import 'package:tahfiz/core/localization/app_localization.dart';
import 'package:tahfiz/data/datasources/asset_reader.dart';
import 'package:tahfiz/data/models/reciter.dart';
import 'package:tahfiz/data/models/surah.dart';
import 'package:tahfiz/main.dart';
import 'package:tahfiz/services/audio/ayah_duration_service.dart';

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

  static Future<AppHarness> start() async {
    TestWidgetsFlutterBinding.ensureInitialized();

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
      _storageDir = Directory.systemTemp.createTempSync('tahfiz_ui');
      Hive.init(_storageDir!.path);
    }

    await sl.reset();
    await configureDependencies();

    // Swap in measured durations rather than probing audio, which has no
    // plugin implementation under `flutter test`.
    sl.unregister<AyahDurationService>();
    sl.registerLazySingleton<AyahDurationService>(FakeAyahDurationService.new);

    sl.unregister<AssetReader>();
    sl.registerLazySingleton<AssetReader>(FileAssetReader.new);

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
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(app(locale: locale));
    await settle(tester);
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
    child: const TahfizApp(),
  );
}
