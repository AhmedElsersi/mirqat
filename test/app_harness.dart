import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/features/home/widgets/juz_widgets.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';
import 'package:mirqat/features/surah_list/screen/surah_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hive_ce/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/bootstrap.dart';
import 'package:mirqat/core/constants/app_constants.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/downloads_database.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/repositories/reading_history_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/data/models/reading_position.dart';
import 'package:mirqat/data/datasources/reading_history_local_data_source.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/core/router/app_router.dart';
import 'package:mirqat/features/splash/screen/splash_screen.dart';
import 'package:mirqat/main.dart';
import 'package:mirqat/services/app_info_service.dart';
import 'package:mirqat/services/app_version_service.dart';
import 'package:mirqat/services/audio/ayah_duration_service.dart';
import 'package:mirqat/services/audio/manifest_service.dart';
import 'package:mirqat/services/audio/memorization_player_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_session_player.dart';

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

/// What the tests' CDN offers: the bundled reciter, with Al-Fatiha and nothing
/// else.
///
/// Small on purpose. One surah with audio and 113 without is what the reader,
/// the surah list and the session all need to be exercised, and pinning it
/// here means publishing a surah never moves a test.
const String testManifest = '''
{"schemaVersion":1,"baseUrl":"https://cdn.invalid/","mirrors":[],
 "reciters":[{"id":"ahmed_khalil_shaheen","nameAr":"أحمد خليل شاهين",
   "nameEn":"Ahmed Khalil Shaheen","riwayah":"hafs","bitrate":64,"version":"1",
   "audioPath":"audio/{id}/{bitrate}/{s3}{a3}.mp3",
   "packPath":"packs/{id}/{bitrate}/{s3}.zip","totalBytes":571930,
   "surahs":[{"n":1,"ayahs":7,"bytes":571930,"sha256":"ab","hasBasmala":false}]}]}
''';

/// Serves one string, whatever is asked for.
class _FixedManifestReader implements AssetReader {
  const _FixedManifestReader(this.contents);

  final String contents;

  @override
  Future<String> loadString(String path) async => contents;
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

    // just_audio has no implementation under `flutter test` either. The fake
    // records what a session asks of the player, and lets a test say which
    // ayah has been reached.
    sl.unregister<MemorizationPlayerService>();
    sl.registerLazySingleton<MemorizationPlayerService>(FakeSessionPlayer.new);

    // `app.json` the same way: the bundled copy off disk, a network that is
    // never there, and no cache. And a version, since package_info_plus has no
    // implementation here either.
    sl.unregister<AppInfoService>();
    sl.registerLazySingleton<AppInfoService>(
      () => offlineAppInfo(const FileAssetReader()),
      dispose: (AppInfoService s) => s.dispose(),
    );
    sl.unregister<AppVersionService>();
    sl.registerLazySingleton<AppVersionService>(
      () => FixedAppVersion(installedVersion),
    );

    // The real service would fetch the manifest and cache it through
    // path_provider, neither of which has an implementation under
    // `flutter test`. This one reads the bundled manifest off disk and has no
    // network and no cache — exactly the app's offline first-run state.
    sl.unregister<ManifestService>();
    sl.registerLazySingleton<ManifestService>(
      () => ManifestService(
        // A fixed manifest, not the shipped one. `assets/data/manifest.json` is
        // a copy of what is published, so reading it here would make every UI
        // test depend on which surahs happen to be live — a publish would then
        // change what the tests exercise, and one did.
        const _FixedManifestReader(testManifest),
        client: MockClient((http.Request _) async => http.Response('', 404)),
        storageDirectory: () =>
            throw UnsupportedError('No manifest cache under flutter test.'),
      ),
      dispose: (ManifestService s) => s.dispose(),
    );

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

    // `downloads.db` is the app's own writable database and goes through the
    // same plugin, so it gets the same swap: the no-isolate ffi factory, and a
    // throwaway directory per test run.
    sl.unregister<DownloadsDatabase>();
    sl.registerLazySingleton<DownloadsDatabase>(
      () => DownloadsDatabase(
        databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        resolveStorageDirectory: () async => _storageDir!,
      ),
    );
    // A sqflite query still does not reliably complete when a screen first
    // loads inside pure fake-async pumps (the splash hand-off has no runAsync
    // around it). The catalog source caches every surah and its ayahs, so
    // reading them all here, in the real zone, leaves every later read an
    // already-completed future — whichever surah a test opens.
    await _warmCatalog(sl<QuranLocalDataSource>());
    // The same reason, for the home screen's ajzaa tab: the juz list is cached
    // by its data source, so reading it once here makes it a completed future
    // for every HomeIndexCubit a test creates.
    await sl<QuranPagesLocalDataSource>().juzList();

    // Reading history is written on every page turn, and a page turn in a
    // widget test happens under the fake clock, where a real disk write never
    // completes — and an unfinished Hive write keeps the box's lock, so the
    // *next* test's setup would wait on it for ever. Memory has no lock.
    sl.unregister<ReadingHistoryRepository>();
    sl.unregister<ReadingHistoryLocalDataSource>();
    sl.registerLazySingleton<ReadingHistoryLocalDataSource>(
      InMemoryReadingHistory.new,
    );
    sl.registerLazySingleton<ReadingHistoryRepository>(
      () => ReadingHistoryRepositoryImpl(sl<ReadingHistoryLocalDataSource>()),
    );

    await Hive.box<Map<dynamic, dynamic>>(AppConstants.progressBoxName).clear();
    await Hive.box<Map<dynamic, dynamic>>(AppConstants.settingsBoxName).clear();
    // Every test but the introduction's own starts as someone who has already
    // seen it; [freshInstall] puts that back.
    await sl<SettingsRepository>().save(
      const AppSettings(onboardingSeen: true),
    );

    return const AppHarness._();
  }

  Future<void> stop() async => sl.reset();

  /// Settings as a first launch finds them: nothing stored, the introduction
  /// not yet seen.
  static Future<void> freshInstall() =>
      Hive.box<Map<dynamic, dynamic>>(AppConstants.settingsBoxName).clear();

  static Future<void> _warmCatalog(QuranLocalDataSource catalog) async {
    await catalog.getReciters();
    for (final Surah surah in await catalog.getSurahs()) {
      await catalog.getAyahs(surah.number);
    }
  }

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
    bool settleAfter = true,
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
    // Skipped by a test whose launch lands on a screen that never goes idle
    // under the fake clock — the mushaf, whose page load is real I/O.
    if (settleAfter) await settle(tester);
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
    await tester.pump(); // the `go` is processed
    await tester.pump(AppRouter.splashFadeOut); // the 300 ms dissolve
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

  /// Opens the reading view by tapping [target] — a surah, a juz, the
  /// continue card — and waits until its first page and its session are
  /// ready.
  ///
  /// The taps and the waiting run in `runAsync`: a page is built from real
  /// database reads, which never complete under the test's fake clock, and a
  /// read left hanging there holds the connection against every test after.
  static Future<MushafCubit> openReading(
    WidgetTester tester,
    Finder target,
  ) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await tester.pump();
      await tester.pump();
    });
    final BuildContext view = tester.element(find.byType(MushafView));
    final MushafCubit mushaf = BlocProvider.of<MushafCubit>(view);
    final SessionCubit session = BlocProvider.of<SessionCubit>(view);
    await tester.runAsync(() async {
      for (int i = 0; i < 500; i++) {
        final bool pageReady = mushaf.state.pages.containsKey(
          mushaf.state.currentPage,
        );
        // The page suggests the session's range, so a config means both the
        // session and the page have arrived.
        if (pageReady && session.state.config != null) break;
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await frames(tester);
    return mushaf;
  }

  /// Runs frames for [total] ms, one at a time. A single long pump is a
  /// single frame, which starts an animation without ever advancing it.
  static Future<void> frames(WidgetTester tester, [int total = 700]) async {
    for (int t = 0; t < total; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Brings up the bar at the foot of the reading view, the way a reader
  /// does: a tap on the page.
  static Future<void> showReadingBar(WidgetTester tester) async {
    await tester.tap(find.byType(MushafPageView).first);
    await frames(tester, 400);
  }

  /// Opens the session settings from the reading bar. In `runAsync`: the
  /// sheet asks the device which surahs it holds, which is a database read.
  static Future<void> openSessionSheet(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await frames(tester, 500);
  }

  /// A tap on something in the reading view or its sheet, followed by frames
  /// rather than a settle: a page being recited, or a spinner in the sheet,
  /// never goes idle.
  static Future<void> tapAndRun(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.ensureVisible(finder);
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await frames(tester, 300);
  }

  /// Chooses how the home screen is drawn, the way the Settings screen does:
  /// through the live [SettingsCubit]. The home bar used to carry a toggle for
  /// this; it is a setting now, and tests that only need "the grid" should not
  /// have to walk through Settings to get it.
  static Future<void> setHomeView(
    WidgetTester tester,
    HomeViewMode mode,
  ) async {
    final SettingsCubit cubit = BlocProvider.of<SettingsCubit>(
      tester.element(find.byType(SurahListScreen)),
    );
    await tester.runAsync(() async {
      await cubit.setHomeViewMode(mode);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
  }

  /// Swipes from the surahs tab to the ajzaa tab.
  ///
  /// A swipe, not a tap on the tab's label: under the test clock a tapped tab
  /// ends its animation with the new page in place but not answering hit
  /// tests, so the next tap on a row goes nowhere. On a device both work — a
  /// juz opens from either — and the swipe is the gesture the screen was asked
  /// to support anyway. The page reads right to left in Arabic, so the second
  /// tab is to the *right*; the other direction is tried for a left-to-right
  /// locale.
  static Future<void> swipeToAjzaa(WidgetTester tester) async {
    // Most of the pager's own width: a fixed distance is a full swipe on a
    // phone and less than half of one on a tablet, where it snaps back.
    final double reach = tester.getSize(find.byType(TabBarView)).width * 0.8;
    for (final double dx in <double>[reach, -reach]) {
      await tester.drag(find.byType(TabBarView), Offset(dx, 0));
      await settle(tester);
      // A row or a card, whichever the view setting draws.
      if (tester.any(find.byType(JuzRow)) || tester.any(find.byType(JuzTile))) {
        return;
      }
    }
  }

  /// The home list's own vertical scrollable. Not `find.byType(Scrollable)
  /// .first`: the two tabs sit in a horizontal pager, which is a Scrollable
  /// too and comes first in the tree.
  static Finder homeScrollable(Type list) => find
      .descendant(of: find.byType(list), matching: find.byType(Scrollable))
      .first;

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

/// An [AppInfoService] over [assets] with no network and no disk cache.
AppInfoService offlineAppInfo(AssetReader assets) => AppInfoService(
  assets,
  client: MockClient((http.Request _) async => http.Response('', 404)),
  storageDirectory: () =>
      throw UnsupportedError('No app.json cache under flutter test.'),
);

/// The version the tests' app claims to be.
const String installedVersion = '1.2.0';

class FixedAppVersion implements AppVersionService {
  FixedAppVersion(this.version);

  final String? version;

  @override
  Future<InstalledVersion?> read() async => version == null
      ? null
      : InstalledVersion(version: version!, buildNumber: '7');
}

/// Reading history held in a list, for widget tests. See where it is
/// registered for why the real, Hive-backed one cannot be used under them.
class InMemoryReadingHistory implements ReadingHistoryLocalDataSource {
  List<ReadingPosition> _positions = const <ReadingPosition>[];

  @override
  Future<void> open() async {}

  @override
  Future<List<ReadingPosition>> read() async => _positions;

  @override
  Future<void> write(List<ReadingPosition> positions) async =>
      _positions = List<ReadingPosition>.unmodifiable(positions);
}
