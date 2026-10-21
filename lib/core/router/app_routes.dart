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

  /// Search: a surah by name, an ayah by its words, a page by its number.
  static const String searchPath = '/search';
  static const String searchName = 'search';

  /// An ayah beside the ayahs it is easily confused with. An `AyahRef` in
  /// `state.extra`.
  static const String similarPath = '/similar';
  static const String similarName = 'similar';

  /// Every phrase the Quran repeats across its ayahs, one card each.
  static const String mutashabihatPath = '/mutashabihat';
  static const String mutashabihatName = 'mutashabihat';

  /// One such phrase and every ayah it occurs in. The phrase id, an `int`,
  /// in `state.extra`.
  static const String mutashabihatPhrasePath = '/mutashabihat/phrase';
  static const String mutashabihatPhraseName = 'mutashabihat-phrase';

  /// The reader's practice, in plain numbers.
  static const String statsPath = '/stats';
  static const String statsName = 'stats';

  /// The hifz plan: made, and followed.
  static const String hifzPlanPath = '/plan';
  static const String hifzPlanName = 'hifz_plan';

  /// Every range kept on the review ladder.
  static const String reviewsPath = '/reviews';
  static const String reviewsName = 'reviews';

  /// Every ayah the reader stumbles at.
  static const String weakSpotsPath = '/weak-spots';
  static const String weakSpotsName = 'weak_spots';

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
  static const String ideaPath = 'idea';
  static const String ideaName = 'app_idea';
  static const String developerPath = 'developer';
  static const String developerName = 'developer';

  /// The saved-recitations list. A child of settings, so the back button
  /// returns there rather than to the home screen.
  static const String downloadsPath = 'downloads';

  /// The reader's progress saved to a file and taken back in.
  static const String backupPath = 'backup';
  static const String backupName = 'backup';

  /// The mushaf's face and text size, with a preview.
  static const String mushafFontPath = 'mushaf-font';
  static const String mushafFontName = 'mushaf_font';
  static const String downloadsName = 'downloads';

  /// The whole-mushaf download, a child of the saved-recitations route's
  /// parent for the same reason: back returns to settings.
  static const String mushafDownloadPath = 'download-mushaf';
  static const String mushafDownloadName = 'mushaf_download';

  /// Path parameter shared by the surah-scoped routes.
  static const String surahNumberParam = 'surahNumber';
}
