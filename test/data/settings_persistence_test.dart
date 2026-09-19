import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mirqat/data/datasources/settings_local_data_source.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/domain/entities/session_config.dart';

void main() {
  late Directory storageDir;

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('mirqat_settings_test');
    Hive.init(storageDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (storageDir.existsSync()) storageDir.deleteSync(recursive: true);
  });

  Future<SettingsLocalDataSource> openSource() async {
    final SettingsLocalDataSourceImpl source = SettingsLocalDataSourceImpl();
    await source.open();
    return source;
  }

  /// Writes a raw settings map, as an older build would have left it.
  Future<void> seedRaw(Map<String, dynamic> map) async {
    final Box<Map<dynamic, dynamic>> box =
        await Hive.openBox<Map<dynamic, dynamic>>('settings');
    await box.put('app_settings', map);
    await box.close();
  }

  Future<Map<dynamic, dynamic>?> readRaw() async {
    final Box<Map<dynamic, dynamic>> box =
        await Hive.openBox<Map<dynamic, dynamic>>('settings');
    final Map<dynamic, dynamic>? stored = box.get('app_settings');
    await box.close();
    return stored;
  }

  test('a fresh install reads the documented defaults', () async {
    final SettingsLocalDataSource source = await openSource();

    final AppSettings settings = await source.read();

    expect(settings.reciterId, isNull);
    expect(settings.defaultRepeatCount, SessionConfig.defaultRepeatCount);
    // Continuous is the product default for a new reader (owner decision).
    expect(settings.defaultConnectMode, ConnectMode.continuous);
    expect(settings.defaultFinalFullPass, isNull);
    expect(settings.defaultRangeBehaviour, RangeBehaviour.wholeSurah);
    expect(settings.lastRanges, isEmpty);
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.homeViewMode, HomeViewMode.list);
    expect(settings.arabicFontSize, AppSettings.defaultArabicFontSize);
  });

  test('settings survive an app restart', () async {
    const AppSettings chosen = AppSettings(
      reciterId: 'ahmed_khalil_shaheen',
      defaultRepeatCount: 7,
      defaultConnectMode: ConnectMode.continuous,
      defaultFinalFullPass: true,
      defaultIntraBlockPauseMs: 250,
      defaultBetweenRepeatPauseMs: 1200,
      defaultBetweenStepsPauseMs: 2000,
      defaultPlaybackSpeed: 0.9,
      defaultRangeBehaviour: RangeBehaviour.lastUsed,
      lastRanges: <int, AyahRange>{1: AyahRange(startAyah: 2, endAyah: 5)},
      themeMode: AppThemeMode.dark,
      homeViewMode: HomeViewMode.grid,
      arabicFontSize: 32,
    );

    final SettingsLocalDataSource first = await openSource();
    await first.write(chosen);

    await Hive.close();
    Hive.init(storageDir.path);

    final SettingsLocalDataSource second = await openSource();
    expect(await second.read(), chosen);
  });

  test('round-trips through the storage map', () {
    const AppSettings settings = AppSettings(
      reciterId: 'r',
      defaultRepeatCount: 5,
      defaultConnectMode: ConnectMode.none,
      themeMode: AppThemeMode.light,
      homeViewMode: HomeViewMode.grid,
      arabicFontSize: 26,
    );

    expect(AppSettings.fromMap(settings.toMap()), settings);
  });

  test('an older install missing the newer keys reads its defaults', () {
    // What a device upgrading from the first release actually holds: the five
    // fields that existed then, and nothing else.
    final AppSettings settings = AppSettings.fromMap(<String, dynamic>{
      'reciterId': 'ahmed_khalil_shaheen',
      'defaultRepeatCount': 5,
      'defaultConnectMode': 'cumulative',
      'themeMode': 'dark',
      'arabicFontSize': 30.0,
    });

    expect(settings.reciterId, 'ahmed_khalil_shaheen');
    expect(settings.defaultRepeatCount, 5);
    expect(settings.defaultConnectMode, ConnectMode.cumulative);
    expect(settings.themeMode, AppThemeMode.dark);
    expect(settings.arabicFontSize, 30.0);
    // Absent, so the defaults apply rather than throwing.
    expect(settings.homeViewMode, HomeViewMode.list);
    expect(settings.defaultPlaybackSpeed, SessionConfig.defaultPlaybackSpeed);
    expect(settings.lastRanges, isEmpty);
  });

  test('an unknown stored enum falls back rather than throwing', () {
    final AppSettings settings = AppSettings.fromMap(<String, dynamic>{
      'defaultConnectMode': 'telepathy',
      'themeMode': 'neon',
    });

    // Falls back to the fresh-install default, which is what an unreadable
    // value and an absent one both mean.
    expect(settings.defaultConnectMode, ConnectMode.continuous);
    expect(settings.themeMode, AppThemeMode.system);
  });

  test('a malformed remembered range is skipped, not fatal', () {
    final AppSettings settings = AppSettings.fromMap(<String, dynamic>{
      'lastRanges': <String, Object?>{
        '1': <int>[2, 5], // good
        '2': <int>[9], // wrong length
        '3': <Object>[1, 'x'], // wrong type
        '4': <int>[6, 2], // inverted
        'nope': <int>[1, 2], // unparseable surah
      },
      'defaultRangeBehaviour': 'last_used',
    });

    expect(settings.lastRanges, <int, AyahRange>{
      1: const AyahRange(startAyah: 2, endAyah: 5),
    });
    expect(
      settings.rememberedRangeFor(1),
      const AyahRange(startAyah: 2, endAyah: 5),
    );
    expect(settings.rememberedRangeFor(2), isNull);
  });

  test('a remembered range is ignored while the behaviour is whole-surah', () {
    const AppSettings settings = AppSettings(
      lastRanges: <int, AyahRange>{1: AyahRange(startAyah: 2, endAyah: 5)},
    );

    expect(settings.defaultRangeBehaviour, RangeBehaviour.wholeSurah);
    expect(settings.rememberedRangeFor(1), isNull);
  });

  // --- the removed-enum-value migration -------------------------------------

  group('connect-mode migration', () {
    test('a stored "pairwise" reads as cumulative and is rewritten', () async {
      // Exactly what a device that had pairwise selected holds on disk. The
      // mode is persisted by `name`, never by index, so removing a case cannot
      // shift the meaning of any other stored value.
      await seedRaw(<String, dynamic>{
        'reciterId': 'ahmed_khalil_shaheen',
        'defaultRepeatCount': 5,
        'defaultConnectMode': 'pairwise',
        'themeMode': 'dark',
        'arabicFontSize': 30.0,
      });

      final SettingsLocalDataSource source = await openSource();
      final AppSettings settings = await source.read();

      // Mapped to the nearest surviving joining mode — not silently dropped
      // to whatever the default happens to be.
      expect(settings.defaultConnectMode, ConnectMode.cumulative);
      // Everything else survives the migration untouched.
      expect(settings.reciterId, 'ahmed_khalil_shaheen');
      expect(settings.defaultRepeatCount, 5);
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.arabicFontSize, 30.0);

      // And the box no longer holds the retired string, so the remap is not
      // recomputed on every launch.
      expect((await readRaw())?['defaultConnectMode'], 'cumulative');
    });

    test('a stored "continuous" is not disturbed by the migration', () async {
      // The index-shift hazard, checked directly: `continuous` sits at a
      // different ordinal than it did before `pairwise` was removed, and must
      // still read back as itself.
      await seedRaw(<String, dynamic>{'defaultConnectMode': 'continuous'});

      final SettingsLocalDataSource source = await openSource();
      expect((await source.read()).defaultConnectMode, ConnectMode.continuous);
      expect((await readRaw())?['defaultConnectMode'], 'continuous');
    });

    test('a surviving value is left alone and not rewritten', () async {
      await seedRaw(<String, dynamic>{
        'defaultConnectMode': 'none',
        'arabicFontSize': 21.0,
      });

      final SettingsLocalDataSource source = await openSource();
      expect((await source.read()).defaultConnectMode, ConnectMode.none);

      // Untouched: no rewrite means the rest of the map is not normalised
      // behind the reader's back either.
      final Map<dynamic, dynamic>? raw = await readRaw();
      expect(raw?['defaultConnectMode'], 'none');
      expect(raw?.containsKey('homeViewMode'), isFalse);
    });

    test('an unreadable value is rewritten too', () async {
      await seedRaw(<String, dynamic>{'defaultConnectMode': 'telepathy'});

      final SettingsLocalDataSource source = await openSource();
      expect((await source.read()).defaultConnectMode, ConnectMode.continuous);
      expect((await readRaw())?['defaultConnectMode'], 'continuous');
    });

    test('decodeStored reports how each value was read', () {
      expect(
        ConnectMode.decodeStored('cumulative').status,
        StoredConnectModeStatus.current,
      );
      expect(
        ConnectMode.decodeStored('pairwise').status,
        StoredConnectModeStatus.retired,
      );
      expect(ConnectMode.decodeStored('pairwise').mode, ConnectMode.cumulative);
      expect(ConnectMode.decodeStored('pairwise').needsRewrite, isTrue);
      expect(
        ConnectMode.decodeStored(null).status,
        StoredConnectModeStatus.absent,
      );
      expect(ConnectMode.decodeStored(null).needsRewrite, isFalse);
      expect(
        ConnectMode.decodeStored(17).status,
        StoredConnectModeStatus.unreadable,
      );
      // An int is what an ordinal-based build would have written; it is
      // reported as unreadable rather than being interpreted as an index.
      expect(ConnectMode.decodeStored(17).raw, '17');
    });

    test('pairwise is the only retired value', () {
      expect(ConnectMode.retiredStorageValues.keys, <String>['pairwise']);
      expect(
        ConnectMode.values.map((ConnectMode m) => m.name),
        containsAll(<String>['cumulative', 'continuous', 'none']),
      );
      expect(
        ConnectMode.values.map((ConnectMode m) => m.name),
        isNot(contains('pairwise')),
      );
    });
  });

  test('every mode agrees with SessionConfig on its finalFullPass default', () {
    // SessionConfig's initialiser spells the default out because it is const
    // and cannot call a getter. This is what keeps the two from drifting.
    for (final ConnectMode mode in ConnectMode.values) {
      expect(
        SessionConfig(
          surahNumber: 1,
          startAyah: 1,
          endAyah: 3,
          connectMode: mode,
        ).finalFullPass,
        mode.defaultFinalFullPass,
        reason: '${mode.name} disagrees',
      );
    }
  });
}
