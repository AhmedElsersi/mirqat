import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/settings_local_data_source.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/daily_wird.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';

import '../quran_db_fixtures.dart';

/// Settings kept in a field, written as slowly as a disk would: the echo of
/// one save is still arriving while the next is being written.
class _SlowSettings implements SettingsLocalDataSource {
  AppSettings stored = const AppSettings();

  @override
  Future<void> open() async {}

  @override
  Future<AppSettings> read() async => stored;

  @override
  Future<void> write(AppSettings settings) async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    stored = settings;
  }
}

void main() {
  WirdRange range(int surah, int from, int to) => WirdRange(
    from: AyahRef(surah, from),
    to: AyahRef(surah, to),
  );

  test('saves one after another keep each other: the whole wird set at '
      'once is all three parts, not the first and the last', () async {
    final _SlowSettings local = _SlowSettings();
    final SettingsCubit cubit = SettingsCubit(
      settingsRepository: SettingsRepositoryImpl(local),
      reciterCatalog: fixtureCatalog(),
    );
    addTearDown(cubit.close);

    // As the wird editor hands its result over: part by part, awaited.
    await cubit.setWird(WirdPart.fresh, range(2, 15, 21));
    await cubit.setWird(WirdPart.recent, range(2, 1, 8));
    await cubit.setWird(WirdPart.old, range(1, 1, 7));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    for (final DailyWird wird in <DailyWird>[
      cubit.state.settings.wird,
      local.stored.wird,
    ]) {
      expect(wird.keys, unorderedEquals(WirdPart.values));
    }
  });

  test('another writer\'s save is still taken up', () async {
    final _SlowSettings local = _SlowSettings();
    final SettingsRepositoryImpl repository = SettingsRepositoryImpl(local);
    final SettingsCubit cubit = SettingsCubit(
      settingsRepository: repository,
      reciterCatalog: fixtureCatalog(),
    );
    addTearDown(cubit.close);

    await repository.save(const AppSettings(defaultRepeatCount: 7));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.settings.defaultRepeatCount, 7);
  });
}
