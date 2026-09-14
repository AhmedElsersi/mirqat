/// Route paths and names. Typed arguments travel in `state.extra`.
class AppRoutes {
  const AppRoutes._();

  /// The launch animation. First route, and reachable only on a cold start —
  /// nothing in the app navigates back to it.
  static const String splashPath = '/splash';
  static const String splashName = 'splash';

  static const String surahListPath = '/';
  static const String surahListName = 'surah_list';

  /// The reading page for one surah. Replaced the session-setup form: tapping
  /// a surah lands on the text, not on a dialog.
  static const String readerPath = '/surah/:surahNumber';
  static const String readerName = 'reader';

  static const String playerPath = '/session';
  static const String playerName = 'player';

  static const String progressPath = '/surah/:surahNumber/progress';
  static const String progressName = 'progress';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  /// Path parameter shared by the surah-scoped routes.
  static const String surahNumberParam = 'surahNumber';
}
