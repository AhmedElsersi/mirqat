import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/screen/developer_screen.dart';
import '../../features/about/screen/how_to_use_screen.dart';
import '../../features/about/screen/info_page_screen.dart';
import '../../features/history/screen/history_screen.dart';
import '../../features/mushaf/mushaf_args.dart';
import '../../features/mushaf/screen/mushaf_screen.dart';
import '../../features/onboarding/screen/onboarding_screen.dart';
import '../../features/progress/screen/progress_screen.dart';
import '../../features/settings/cubit/settings_cubit.dart';
import '../../features/settings/cubit/settings_state.dart';
import '../../features/settings/screen/downloads_screen.dart';
import '../../features/settings/screen/session_settings_screen.dart';
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
                  if (!context.mounted) return;
                  _leaveSplash(context);
                },
              ),
            ),
      ),
      GoRoute(
        path: AppRoutes.onboardingPath,
        name: AppRoutes.onboardingName,
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.surahListPath,
        name: AppRoutes.surahListName,
        builder: (BuildContext context, GoRouterState state) =>
            const SurahListScreen(),
      ),
      GoRoute(
        path: AppRoutes.progressPath,
        name: AppRoutes.progressName,
        builder: (BuildContext context, GoRouterState state) =>
            ProgressScreen(surahNumber: _surahNumberOf(state)),
      ),
      GoRoute(
        path: AppRoutes.mushafPath,
        name: AppRoutes.mushafName,
        builder: (BuildContext context, GoRouterState state) => MushafScreen(
          args: state.extra as MushafArgs? ?? const MushafArgs(),
        ),
      ),
      GoRoute(
        path: AppRoutes.historyPath,
        name: AppRoutes.historyName,
        builder: (BuildContext context, GoRouterState state) =>
            const HistoryScreen(),
      ),
      GoRoute(
        path: AppRoutes.settingsPath,
        name: AppRoutes.settingsName,
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: AppRoutes.sessionSettingsPath,
            name: AppRoutes.sessionSettingsName,
            builder: (BuildContext context, GoRouterState state) =>
                const SessionSettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.howToUsePath,
            name: AppRoutes.howToUseName,
            builder: (BuildContext context, GoRouterState state) =>
                const HowToUseScreen(),
          ),
          GoRoute(
            path: AppRoutes.goalPath,
            name: AppRoutes.goalName,
            builder: (BuildContext context, GoRouterState state) =>
                const InfoPageScreen(page: InfoPage.goal),
          ),
          GoRoute(
            path: AppRoutes.aboutUsPath,
            name: AppRoutes.aboutUsName,
            builder: (BuildContext context, GoRouterState state) =>
                const InfoPageScreen(page: InfoPage.about),
          ),
          GoRoute(
            path: AppRoutes.developerPath,
            name: AppRoutes.developerName,
            builder: (BuildContext context, GoRouterState state) =>
                const DeveloperScreen(),
          ),
          GoRoute(
            path: AppRoutes.downloadsPath,
            name: AppRoutes.downloadsName,
            builder: (BuildContext context, GoRouterState state) =>
                const DownloadsScreen(),
          ),
        ],
      ),
    ],
  );

  /// How long the splash will hold its last frame for the stored settings.
  /// They are a read from the device, so this is never reached in practice;
  /// it is there so that storage that never answers cannot keep anyone on the
  /// splash.
  static const Duration settingsWait = Duration(seconds: 1);

  /// Hands over from the splash once it is known whether the introduction
  /// has been seen.
  ///
  /// The settings cubit is created lazily, and this is the first thing to
  /// read it — so at this instant it has loaded nothing, and deciding on its
  /// state as it stands would send every first launch straight past the
  /// introduction.
  static Future<void> _leaveSplash(BuildContext context) async {
    final SettingsCubit cubit = context.read<SettingsCubit>();
    if (!cubit.state.settingsRead) {
      await cubit.stream
          .firstWhere((SettingsState s) => s.settingsRead)
          .timeout(settingsWait, onTimeout: () => cubit.state);
    }
    if (context.mounted) context.go(landingAfterSplash(cubit.state));
  }

  /// Where the splash gives way to: the introduction for someone who has not
  /// seen it, the home page for everyone else.
  ///
  /// Settings that have not been read count as "seen". They are read from the
  /// device in milliseconds and the splash lasts seconds, so this is the
  /// launch where storage failed — and an introduction shown by mistake, to
  /// someone who has used the app for a year, is the worse of the two errors.
  /// Read, not *ready*: ready also waits for the reciters, which may wait on
  /// the network, and a slow connection is no reason to skip the introduction.
  static String landingAfterSplash(SettingsState settings) =>
      settings.settingsRead && !settings.settings.onboardingSeen
      ? AppRoutes.onboardingPath
      : AppRoutes.surahListPath;

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
