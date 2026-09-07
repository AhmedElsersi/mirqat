import 'package:go_router/go_router.dart';

import '../../features/surah_list/screen/surah_list_screen.dart';
import 'app_routes.dart';

/// GoRouter configuration. Typed arguments travel in `state.extra`.
class AppRouter {
  const AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.surahListPath,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.surahListPath,
        name: AppRoutes.surahListName,
        builder: (context, state) => const SurahListScreen(),
      ),
    ],
  );
}
