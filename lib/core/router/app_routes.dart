/// Route paths and names. Typed arguments travel in `state.extra`.
class AppRoutes {
  const AppRoutes._();

  /// The launch animation. First route, and reachable only on a cold start —
  /// nothing in the app navigates back to it.
  static const String splashPath = '/splash';
  static const String splashName = 'splash';

  static const String surahListPath = '/';
  static const String surahListName = 'surah_list';

  static const String progressPath = '/surah/:surahNumber/progress';
  static const String progressName = 'progress';

  /// The reading view — the whole mushaf, or one surah or juz of it — and the
  /// memorization session that plays over it. Optional `MushafArgs` in
  /// `state.extra`.
  static const String mushafPath = '/mushaf';
  static const String mushafName = 'mushaf';

  static const String historyPath = '/history';
  static const String historyName = 'history';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  /// The saved-recitations list. A child of settings, so the back button
  /// returns there rather than to the home screen.
  static const String downloadsPath = 'downloads';
  static const String downloadsName = 'downloads';

  /// Path parameter shared by the surah-scoped routes.
  static const String surahNumberParam = 'surahNumber';
}
