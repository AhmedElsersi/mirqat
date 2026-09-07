/// Route paths and names. Typed arguments travel in `state.extra`.
class AppRoutes {
  const AppRoutes._();

  static const String surahListPath = '/';
  static const String surahListName = 'surah_list';

  static const String sessionSetupPath = '/surah/:surahNumber/setup';
  static const String sessionSetupName = 'session_setup';

  static const String playerPath = '/session';
  static const String playerName = 'player';

  static const String progressPath = '/surah/:surahNumber/progress';
  static const String progressName = 'progress';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  /// Path parameter shared by the surah-scoped routes.
  static const String surahNumberParam = 'surahNumber';
}
