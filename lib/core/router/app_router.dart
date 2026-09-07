import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/player/player_args.dart';
import '../../features/player/screen/player_screen.dart';
import '../../features/progress/screen/progress_screen.dart';
import '../../features/session_setup/screen/session_setup_screen.dart';
import '../../features/settings/screen/settings_screen.dart';
import '../../features/surah_list/screen/surah_list_screen.dart';
import 'app_routes.dart';

/// GoRouter configuration. Typed arguments travel in `state.extra`.
class AppRouter {
  const AppRouter._();

  /// Builds a router. Deliberately not a static instance: a shared one carries
  /// its navigation history across app instances, which leaks between tests
  /// and would survive a restart of the widget tree.
  static GoRouter create() => GoRouter(
    initialLocation: AppRoutes.surahListPath,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.surahListPath,
        name: AppRoutes.surahListName,
        builder: (BuildContext context, GoRouterState state) =>
            const SurahListScreen(),
      ),
      GoRoute(
        path: AppRoutes.sessionSetupPath,
        name: AppRoutes.sessionSetupName,
        builder: (BuildContext context, GoRouterState state) =>
            SessionSetupScreen(surahNumber: _surahNumberOf(state)),
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
