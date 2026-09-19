import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../services/audio/memorization_player_service.dart';
import '../services/audio/session_media_controls.dart';
import '../services/reciter_image_cache.dart';
import 'di/injection.dart';

/// The app's one-time startup work, as a future the splash can wait on.
///
/// This used to be `await`ed before `runApp`, which meant nothing rendered
/// until Hive had opened its boxes and the service locator was populated — the
/// launch was as slow as the slowest box. Holding it as a future instead lets
/// the splash animation and the initialisation run at the same time, and the
/// splash finishes on whichever takes longer.
///
/// Started from `main` and read by the splash. A plain static rather than a
/// registration in [sl], because [sl] is precisely what this sets up.
class AppBootstrap {
  const AppBootstrap._();

  static Future<void>? _future;

  /// Starts the work on first access, and hands back the same future after
  /// that. Reading this twice must not open the boxes twice.
  static Future<void> get future => _future ??= _run();

  static Future<void> _run() async {
    await Hive.initFlutter();
    await configureDependencies();
    // Here rather than inside configureDependencies: registering with the
    // system's media session is a platform call, and dependency registration
    // has to stay runnable under `flutter test`. Tests replace this whole
    // future, so they never reach it.
    await SessionMediaControls.start(
      playerService: sl<MemorizationPlayerService>(),
      imageCache: sl<ReciterImageCache>(),
    );
  }

  /// Stands in for the real startup when the harness has already done it.
  ///
  /// Tests set up Hive and the locator themselves, so the splash must not
  /// re-run either; it only needs a future that is already complete.
  @visibleForTesting
  static void overrideWith(Future<void> future) => _future = future;

  @visibleForTesting
  static void reset() => _future = null;
}
