import 'package:get_it/get_it.dart';

/// The service locator.
final GetIt sl = GetIt.instance;

/// Registers every dependency. Called once from `main` before `runApp`.
///
/// Ownership per CLAUDE.md A.3:
///   - data sources, repositories and services -> `registerLazySingleton`
///   - cubits -> `registerFactory`
Future<void> configureDependencies() async {
  // Phase 1 registers the data layer here.
  // Phase 3 registers the audio services here.
  // Phase 4 registers the cubits here.
}
