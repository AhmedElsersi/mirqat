import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/player_args.dart';
import '../../features/player/screen/player_screen.dart';
import '../../features/progress/screen/progress_screen.dart';
import '../../features/reader/screen/reader_screen.dart';
import '../../features/settings/screen/settings_screen.dart';
import '../../features/splash/screen/splash_screen.dart';
import '../../features/surah_list/screen/surah_list_screen.dart';
import 'app_routes.dart';

/// GoRouter configuration. Typed arguments travel in `state.extra`.
class AppRouter {
  const AppRouter._();

  /// Builds a router. Deliberately not a static instance: a shared one carries
  /// its navigation history across app instances, which leaks between tests
  /// and would survive a restart of the widget tree.
  /// How long the splash takes to dissolve into the home screen.
  static const Duration splashFadeOut = Duration(milliseconds: 300);

  static GoRouter create() => GoRouter(
    initialLocation: AppRoutes.splashPath,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.splashPath,
        name: AppRoutes.splashName,
        // A CustomTransitionPage purely for the *reverse* transition: the
        // splash appears instantly (it is the first thing on screen, so there
        // is nothing to transition from) and dissolves over 300 ms on the way
        // out, with the home screen already built underneath. Fading the
        // splash's own content to transparent instead would reveal the bare
        // scaffold colour for those 300 ms, which is the flash this avoids.
        pageBuilder: (BuildContext context, GoRouterState state) =>
            CustomTransitionPage<void>(
              key: state.pageKey,
              transitionDuration: Duration.zero,
              reverseTransitionDuration: splashFadeOut,
              transitionsBuilder:
                  (
                    BuildContext context,
                    Animation<double> animation,
                    Animation<double> secondary,
                    Widget child,
                  ) => FadeTransition(opacity: animation, child: child),
              child: SplashScreen(
                onFinished: () {
                  // `go`, not `push`: the splash is a cold-start moment and
                  // must not sit under the home screen waiting to be popped
                  // back to.
                  if (context.mounted) context.go(AppRoutes.surahListPath);
                },
              ),
            ),
      ),
      GoRoute(
        path: AppRoutes.surahListPath,
        name: AppRoutes.surahListName,
        builder: (BuildContext context, GoRouterState state) =>
            const SurahListScreen(),
      ),
      GoRoute(
        path: AppRoutes.readerPath,
        name: AppRoutes.readerName,
        builder: (BuildContext context, GoRouterState state) =>
            ReaderScreen(surahNumber: _surahNumberOf(state)),
      ),
      GoRoute(
        path: AppRoutes.progressPath,
        name: AppRoutes.progressName,
        builder: (BuildContext context, GoRouterState state) =>
            ProgressScreen(surahNumber: _surahNumberOf(state)),
      ),
      GoRoute(
        path: AppRoutes.playerPath,
        name: AppRoutes.playerName,
        builder: (BuildContext context, GoRouterState state) =>
            PlayerScreen(args: state.extra! as PlayerArgs),
      ),
      GoRoute(
        path: AppRoutes.settingsPath,
        name: AppRoutes.settingsName,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
    ],
  );

  static int _surahNumberOf(GoRouterState state) {
    final String? raw = state.pathParameters[AppRoutes.surahNumberParam];
    final int? parsed = raw == null ? null : int.tryParse(raw);
    if (parsed == null) {
      throw ArgumentError(
        'Route ${state.uri} carries no valid '
        '"${AppRoutes.surahNumberParam}" path parameter.',
      );
    }
    return parsed;
  }
}
