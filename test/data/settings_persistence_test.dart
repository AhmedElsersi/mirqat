import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:tahfiz/data/datasources/settings_local_data_source.dart';
import 'package:tahfiz/data/models/app_settings.dart';
import 'package:tahfiz/domain/entities/session_config.dart';

void main() {
  late Directory storageDir;

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('tahfiz_settings_test');
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

  test('a fresh install reads the documented defaults', () async {
    final SettingsLocalDataSource source = await openSource();

    final AppSettings settings = await source.read();

    expect(settings.reciterId, isNull);
    expect(settings.defaultRepeatCount, SessionConfig.defaultRepeatCount);
    expect(settings.defaultConnectMode, ConnectMode.cumulative);
    expect(settings.themeMode, AppThemeMode.system);
    expect(settings.arabicFontSize, AppSettings.defaultArabicFontSize);
  });

  test('settings survive an app restart', () async {
    const AppSettings chosen = AppSettings(
      reciterId: 'ahmed_khalil_shaheen',
      defaultRepeatCount: 7,
      defaultConnectMode: ConnectMode.pairwise,
      themeMode: AppThemeMode.dark,
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
      arabicFontSize: 26,
    );

    expect(AppSettings.fromMap(settings.toMap()), settings);
  });

  test('an unknown stored enum falls back rather than throwing', () {
    final AppSettings settings = AppSettings.fromMap(<String, dynamic>{
      'defaultConnectMode': 'telepathy',
      'themeMode': 'neon',
    });

    expect(settings.defaultConnectMode, ConnectMode.cumulative);
    expect(settings.themeMode, AppThemeMode.system);
  });
}
