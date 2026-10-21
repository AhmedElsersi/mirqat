import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/hifz_plan.dart';
import 'package:mirqat/features/hifz_plan/cubit/hifz_plan_cubit.dart';

import '../app_harness.dart' show FileAssetReader;
import '../quran_db_fixtures.dart';

class _Settings implements SettingsRepository {
  _Settings(this.current);

  AppSettings current;
  final StreamController<AppSettings> _changes =
      StreamController<AppSettings>.broadcast();

  @override
  Future<Either<Failure, AppSettings>> read() async =>
      Right<Failure, AppSettings>(current);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings s) async {
    current = s;
    _changes.add(s);
    return Right<Failure, AppSettings>(s);
  }

  @override
  Stream<AppSettings> get changes => _changes.stream;
}

void main() {
  late _Settings settings;

  Future<HifzPlanCubit> open([AppSettings stored = const AppSettings()]) async {
    settings = _Settings(stored);
    final HifzPlanCubit cubit = HifzPlanCubit(
      quranRepository: QuranRepositoryImpl(
        QuranLocalDataSourceImpl(const FileAssetReader(), RepoQuranDatabase()),
      ),
      settingsRepository: settings,
      clock: () => DateTime(2026, 10, 21, 9),
    );
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  test('a fresh draft is the first surah, whole', () async {
    final HifzPlanCubit cubit = await open();
    expect(cubit.state.status, LoadStatus.ready);
    expect(cubit.state.plan, isNull);
    expect(cubit.state.from, const AyahRef(1, 1));
    expect(cubit.state.to, const AyahRef(1, 7));
    expect(cubit.state.draftAyahs, 7);
  });

  test('the two ends never cross', () async {
    final HifzPlanCubit cubit = await open();
    cubit.setFrom(const AyahRef(67, 1));
    expect(cubit.state.to, const AyahRef(67, 1));
    cubit.setTo(const AyahRef(67, 30));
    cubit.setFrom(const AyahRef(67, 99));
    expect(
      cubit.state.from,
      const AyahRef(67, 30),
      reason: 'held to the surah',
    );
    cubit.setTo(const AyahRef(2, 5));
    expect(cubit.state.from, const AyahRef(2, 5));
  });

  test('making a plan cuts the range and keeps it — beside the rest of the '
      'settings, not over them', () async {
    final HifzPlanCubit cubit = await open(
      const AppSettings(reciterId: 'kept', arabicFontSize: 30),
    );
    cubit.setFrom(const AyahRef(67, 1));
    cubit.setTo(const AyahRef(67, 30));
    cubit.setDays(10);
    await cubit.create();

    final HifzPlan plan = settings.current.hifzPlan!;
    expect(cubit.state.plan, plan);
    expect(plan.portions, hasLength(10));
    expect(plan.from, const AyahRef(67, 1));
    expect(plan.to, const AyahRef(67, 30));
    expect(plan.started, DateTime(2026, 10, 21));
    expect(settings.current.reciterId, 'kept');
    expect(settings.current.arabicFontSize, 30);
  });

  test('a plan moved on elsewhere is taken up', () async {
    final HifzPlanCubit cubit = await open();
    cubit.setDays(3);
    await cubit.create();
    await settings.save(
      settings.current.copyWith(
        hifzPlan: settings.current.hifzPlan!.copyWith(completed: 2),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state.plan!.completed, 2);
  });

  test('giving it up removes the plan and nothing else', () async {
    final HifzPlanCubit cubit = await open(const AppSettings(reciterId: 'r'));
    await cubit.create();
    await cubit.delete();
    expect(cubit.state.plan, isNull);
    expect(settings.current.hifzPlan, isNull);
    expect(settings.current.reciterId, 'r');
  });
}
