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

  /// The introduction. First launch lands here from the splash; How to use
  /// can bring it up again.
  static const String onboardingPath = '/welcome';
  static const String onboardingName = 'onboarding';

  /// Children of settings, so that back returns there.
  static const String sessionSettingsPath = 'session';
  static const String sessionSettingsName = 'session_settings';
  static const String howToUsePath = 'how-to-use';
  static const String howToUseName = 'how_to_use';
  static const String goalPath = 'goal';
  static const String goalName = 'goal';
  static const String aboutUsPath = 'about';
  static const String aboutUsName = 'about_us';
  static const String developerPath = 'developer';
  static const String developerName = 'developer';

  /// The saved-recitations list. A child of settings, so the back button
  /// returns there rather than to the home screen.
  static const String downloadsPath = 'downloads';
  static const String downloadsName = 'downloads';

  /// Path parameter shared by the surah-scoped routes.
  static const String surahNumberParam = 'surahNumber';
}
