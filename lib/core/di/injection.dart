import 'package:get_it/get_it.dart';

import '../../data/datasources/asset_reader.dart';
import '../../data/datasources/bundle_asset_reader.dart';
import '../../data/datasources/progress_local_data_source.dart';
import '../../data/datasources/quran_local_data_source.dart';
import '../../data/datasources/settings_local_data_source.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/quran_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/engine/repetition_plan_builder.dart';
import '../../features/player/cubit/player_cubit.dart';
import '../../features/progress/cubit/progress_cubit.dart';
import '../../features/reader/cubit/reader_cubit.dart';
import '../../features/settings/cubit/settings_cubit.dart';
import '../../features/surah_list/cubit/surah_list_cubit.dart';
import '../../services/audio/ayah_duration_service.dart';
import '../../services/audio/memorization_player_service.dart';
import '../../services/keep_awake_service.dart';

/// The service locator.
final GetIt sl = GetIt.instance;

/// Registers every dependency. Called once from `main` after Hive is
/// initialised and before `runApp`.
///
/// Ownership per CLAUDE.md A.3:
///   - data sources, repositories and services -> `registerLazySingleton`
///   - cubits -> `registerFactory`
Future<void> configureDependencies() async {
  // --- Data sources ---
  sl.registerLazySingleton<AssetReader>(BundleAssetReader.new);
  sl.registerLazySingleton<QuranLocalDataSource>(
    () => QuranLocalDataSourceImpl(sl<AssetReader>()),
  );

  // The boxes have to be open before anything reads them, so these two are
  // constructed eagerly rather than lazily.
  final ProgressLocalDataSourceImpl progress = ProgressLocalDataSourceImpl();
  await progress.open();
  sl.registerLazySingleton<ProgressLocalDataSource>(() => progress);

  final SettingsLocalDataSourceImpl settings = SettingsLocalDataSourceImpl();
  await settings.open();
  sl.registerLazySingleton<SettingsLocalDataSource>(() => settings);

  // --- Repositories ---
  sl.registerLazySingleton<QuranRepository>(
    () => QuranRepositoryImpl(sl<QuranLocalDataSource>()),
  );
  sl.registerLazySingleton<ProgressRepository>(
    () => ProgressRepositoryImpl(sl<ProgressLocalDataSource>()),
  );
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<SettingsLocalDataSource>()),
  );

  // --- Domain ---
  sl.registerLazySingleton<RepetitionPlanBuilder>(RepetitionPlanBuilder.new);

  // --- Services ---
  sl.registerLazySingleton<KeepAwakeService>(KeepAwakeService.new);
  sl.registerLazySingleton<AyahDurationService>(
    () => AyahDurationService(quranRepository: sl<QuranRepository>()),
  );
  sl.registerLazySingleton<MemorizationPlayerService>(
    () => MemorizationPlayerService(quranRepository: sl<QuranRepository>()),
  );

  // --- Cubits ---
  sl.registerFactory<SurahListCubit>(
    () => SurahListCubit(
      quranRepository: sl<QuranRepository>(),
      progressRepository: sl<ProgressRepository>(),
    ),
  );
  sl.registerFactory<ReaderCubit>(
    () => ReaderCubit(
      quranRepository: sl<QuranRepository>(),
      settingsRepository: sl<SettingsRepository>(),
      durationService: sl<AyahDurationService>(),
      planBuilder: sl<RepetitionPlanBuilder>(),
    ),
  );
  sl.registerFactory<PlayerCubit>(
    () => PlayerCubit(
      playerService: sl<MemorizationPlayerService>(),
      progressRepository: sl<ProgressRepository>(),
      keepAwakeService: sl<KeepAwakeService>(),
    ),
  );
  sl.registerFactory<ProgressCubit>(
    () => ProgressCubit(
      quranRepository: sl<QuranRepository>(),
      progressRepository: sl<ProgressRepository>(),
    ),
  );
  sl.registerFactory<SettingsCubit>(
    () => SettingsCubit(
      settingsRepository: sl<SettingsRepository>(),
      quranRepository: sl<QuranRepository>(),
    ),
  );
}
