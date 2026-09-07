import 'package:get_it/get_it.dart';

import '../../data/datasources/asset_reader.dart';
import '../../data/datasources/progress_local_data_source.dart';
import '../../data/datasources/quran_local_data_source.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/quran_repository.dart';
import '../../domain/engine/repetition_plan_builder.dart';
import '../../services/audio/memorization_player_service.dart';

/// The service locator.
final GetIt sl = GetIt.instance;

/// Registers every dependency. Called once from `main` after Hive is
/// initialised and before `runApp`.
///
/// Ownership per CLAUDE.md A.3:
///   - data sources, repositories and services -> `registerLazySingleton`
///   - cubits -> `registerFactory`
Future<void> configureDependencies() async {
  sl.registerLazySingleton<AssetReader>(BundleAssetReader.new);

  sl.registerLazySingleton<QuranLocalDataSource>(
    () => QuranLocalDataSourceImpl(sl<AssetReader>()),
  );
  sl.registerLazySingleton<QuranRepository>(
    () => QuranRepositoryImpl(sl<QuranLocalDataSource>()),
  );

  // The progress box has to be open before anything reads it, so this one is
  // constructed eagerly rather than lazily.
  final ProgressLocalDataSourceImpl progress = ProgressLocalDataSourceImpl();
  await progress.open();
  sl.registerLazySingleton<ProgressLocalDataSource>(() => progress);
  sl.registerLazySingleton<ProgressRepository>(
    () => ProgressRepositoryImpl(sl<ProgressLocalDataSource>()),
  );

  sl.registerLazySingleton<RepetitionPlanBuilder>(RepetitionPlanBuilder.new);
  sl.registerLazySingleton<MemorizationPlayerService>(
    () => MemorizationPlayerService(quranRepository: sl<QuranRepository>()),
  );

  // Phase 4 registers the cubits here.
}
