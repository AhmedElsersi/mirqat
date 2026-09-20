import 'package:get_it/get_it.dart';

import '../../data/datasources/asset_reader.dart';
import '../../data/datasources/bundle_asset_reader.dart';
import '../../data/datasources/downloads_database.dart';
import '../../data/datasources/downloads_local_data_source.dart';
import '../../data/datasources/progress_local_data_source.dart';
import '../../data/datasources/quran_database.dart';
import '../../data/datasources/quran_local_data_source.dart';
import '../../data/datasources/quran_pages_local_data_source.dart';
import '../../data/datasources/reading_history_local_data_source.dart';
import '../../data/datasources/settings_local_data_source.dart';
import '../../data/repositories/downloads_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/quran_pages_repository.dart';
import '../../data/repositories/quran_repository.dart';
import '../../data/repositories/reading_history_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/engine/repetition_plan_builder.dart';
import '../../features/about/cubit/app_info_cubit.dart';
import '../../features/home/cubit/home_index_cubit.dart';
import '../../features/mushaf/cubit/mushaf_cubit.dart';
import '../../features/progress/cubit/progress_cubit.dart';
import '../../features/session/cubit/audio_pack_cubit.dart';
import '../../features/session/cubit/session_cubit.dart';
import '../../features/settings/cubit/downloads_cubit.dart';
import '../../features/settings/cubit/settings_cubit.dart';
import '../../features/surah_list/cubit/surah_list_cubit.dart';
import '../../features/update/cubit/update_cubit.dart';
import '../../services/app_info_service.dart';
import '../../services/app_version_service.dart';
import '../../services/audio/audio_availability.dart';
import '../../services/audio/audio_pack_service.dart';
import '../../services/audio/audio_resolver.dart';
import '../../services/audio/audio_storage.dart';
import '../../services/audio/ayah_duration_service.dart';
import '../../services/audio/manifest_service.dart';
import '../../services/audio/memorization_player_service.dart';
import '../../services/audio/pack_fetcher.dart';
import '../../services/audio/reciter_catalog.dart';
import '../../services/keep_awake_service.dart';
import '../../services/link_opener.dart';
import '../../services/reciter_image_cache.dart';

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
  sl.registerLazySingleton<QuranDatabase>(QuranDatabase.new);
  sl.registerLazySingleton<QuranLocalDataSource>(
    () => QuranLocalDataSourceImpl(sl<AssetReader>(), sl<QuranDatabase>()),
  );
  sl.registerLazySingleton<QuranPagesLocalDataSource>(
    () => QuranPagesLocalDataSourceImpl(sl<QuranDatabase>()),
  );

  // The boxes have to be open before anything reads them, so these three are
  // constructed eagerly rather than lazily.
  final ProgressLocalDataSourceImpl progress = ProgressLocalDataSourceImpl();
  await progress.open();
  sl.registerLazySingleton<ProgressLocalDataSource>(() => progress);

  final SettingsLocalDataSourceImpl settings = SettingsLocalDataSourceImpl();
  await settings.open();
  sl.registerLazySingleton<SettingsLocalDataSource>(() => settings);

  final ReadingHistoryLocalDataSourceImpl history =
      ReadingHistoryLocalDataSourceImpl();
  await history.open();
  sl.registerLazySingleton<ReadingHistoryLocalDataSource>(() => history);
  sl.registerLazySingleton<ReadingHistoryRepository>(
    () => ReadingHistoryRepositoryImpl(sl<ReadingHistoryLocalDataSource>()),
  );

  // Its own database, and lazily: unlike the Hive boxes it opens itself on
  // first use, so nothing here touches sqflite before a test has had the
  // chance to swap the engine.
  sl.registerLazySingleton<DownloadsDatabase>(DownloadsDatabase.new);
  sl.registerLazySingleton<DownloadsLocalDataSource>(
    () => DownloadsLocalDataSourceImpl(sl<DownloadsDatabase>()),
    dispose: (DownloadsLocalDataSource source) =>
        (source as DownloadsLocalDataSourceImpl).dispose(),
  );

  // --- Repositories ---
  sl.registerLazySingleton<QuranRepository>(
    () => QuranRepositoryImpl(sl<QuranLocalDataSource>()),
  );
  sl.registerLazySingleton<QuranPagesRepository>(
    () => QuranPagesRepositoryImpl(sl<QuranPagesLocalDataSource>()),
  );
  sl.registerLazySingleton<ProgressRepository>(
    () => ProgressRepositoryImpl(sl<ProgressLocalDataSource>()),
  );
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<SettingsLocalDataSource>()),
  );
  sl.registerLazySingleton<DownloadsRepository>(
    () => DownloadsRepositoryImpl(sl<DownloadsLocalDataSource>()),
  );

  // --- Domain ---
  sl.registerLazySingleton<RepetitionPlanBuilder>(RepetitionPlanBuilder.new);

  // --- Services ---
  sl.registerLazySingleton<KeepAwakeService>(KeepAwakeService.new);
  // Both hold something that outlives a screen — a broadcast controller and
  // its subscription — so both are closed when the locator is reset.
  sl.registerLazySingleton<ManifestService>(
    () => ManifestService(sl<AssetReader>()),
    dispose: (ManifestService s) => s.dispose(),
  );
  sl.registerLazySingleton<ReciterCatalog>(
    () => ReciterCatalog(
      quranRepository: sl<QuranRepository>(),
      manifestService: sl<ManifestService>(),
    ),
    dispose: (ReciterCatalog c) => c.dispose(),
  );
  sl.registerLazySingleton<AudioAvailability>(
    () => AudioAvailability(reciterCatalog: sl<ReciterCatalog>()),
  );
  sl.registerLazySingleton<AudioStorage>(AudioStorage.new);
  sl.registerLazySingleton<ReciterImageCache>(
    () => ReciterImageCache(audioStorage: sl<AudioStorage>()),
    dispose: (ReciterImageCache c) => c.close(),
  );
  sl.registerLazySingleton<AudioResolver>(
    () => AudioResolver(
      quranRepository: sl<QuranRepository>(),
      manifestService: sl<ManifestService>(),
      audioStorage: sl<AudioStorage>(),
      settingsRepository: sl<SettingsRepository>(),
    ),
  );
  sl.registerLazySingleton<AudioPackService>(
    () => AudioPackService(
      manifestService: sl<ManifestService>(),
      audioStorage: sl<AudioStorage>(),
      downloadsRepository: sl<DownloadsRepository>(),
      quranRepository: sl<QuranRepository>(),
      settingsRepository: sl<SettingsRepository>(),
      // Built on first use: the platform downloader starts a native service,
      // and most launches never download anything.
      packFetcher: BackgroundDownloaderPackFetcher.new,
    ),
    dispose: (AudioPackService s) => s.dispose(),
  );
  sl.registerLazySingleton<AyahDurationService>(
    () => AyahDurationService(
      quranRepository: sl<QuranRepository>(),
      audioResolver: sl<AudioResolver>(),
    ),
  );
  sl.registerLazySingleton<MemorizationPlayerService>(
    () => MemorizationPlayerService(audioResolver: sl<AudioResolver>()),
  );

  // --- Cubits ---
  sl.registerFactory<SurahListCubit>(
    () => SurahListCubit(
      quranRepository: sl<QuranRepository>(),
      progressRepository: sl<ProgressRepository>(),
      audioAvailability: sl<AudioAvailability>(),
    ),
  );
  sl.registerLazySingleton<AppInfoService>(
    () => AppInfoService(sl<AssetReader>()),
    dispose: (AppInfoService s) => s.dispose(),
  );
  sl.registerLazySingleton<AppVersionService>(AppVersionService.new);
  sl.registerFactory<UpdateCubit>(
    () => UpdateCubit(
      appInfoService: sl<AppInfoService>(),
      appVersionService: sl<AppVersionService>(),
    ),
  );
  sl.registerLazySingleton<LinkOpener>(LinkOpener.new);
  sl.registerFactory<AppInfoCubit>(
    () => AppInfoCubit(appInfoService: sl<AppInfoService>()),
  );
  sl.registerFactory<HomeIndexCubit>(
    () => HomeIndexCubit(
      quranRepository: sl<QuranRepository>(),
      pagesRepository: sl<QuranPagesRepository>(),
      historyRepository: sl<ReadingHistoryRepository>(),
    ),
  );
  sl.registerFactory<SessionCubit>(
    () => SessionCubit(
      quranRepository: sl<QuranRepository>(),
      settingsRepository: sl<SettingsRepository>(),
      reciterCatalog: sl<ReciterCatalog>(),
      durationService: sl<AyahDurationService>(),
      planBuilder: sl<RepetitionPlanBuilder>(),
      playerService: sl<MemorizationPlayerService>(),
      progressRepository: sl<ProgressRepository>(),
      keepAwakeService: sl<KeepAwakeService>(),
    ),
  );
  sl.registerFactory<AudioPackCubit>(
    () => AudioPackCubit(packService: sl<AudioPackService>()),
  );
  sl.registerFactory<MushafCubit>(
    () => MushafCubit(
      pagesRepository: sl<QuranPagesRepository>(),
      quranRepository: sl<QuranRepository>(),
      historyRepository: sl<ReadingHistoryRepository>(),
    ),
  );
  sl.registerFactory<ProgressCubit>(
    () => ProgressCubit(
      quranRepository: sl<QuranRepository>(),
      progressRepository: sl<ProgressRepository>(),
    ),
  );
  sl.registerFactory<DownloadsCubit>(
    () => DownloadsCubit(
      packService: sl<AudioPackService>(),
      quranRepository: sl<QuranRepository>(),
      reciterCatalog: sl<ReciterCatalog>(),
    ),
  );
  sl.registerFactory<SettingsCubit>(
    () => SettingsCubit(
      settingsRepository: sl<SettingsRepository>(),
      reciterCatalog: sl<ReciterCatalog>(),
      appVersionService: sl<AppVersionService>(),
    ),
  );
}
