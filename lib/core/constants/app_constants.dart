/// Application-wide constants.
///
/// Nothing here may describe a specific surah or reciter — those live only in
/// the JSON catalog under `assets/data/` (see CLAUDE.md A.2 rule 2).
class AppConstants {
  const AppConstants._();

  // --- Session defaults (CLAUDE.md / Part B, SessionConfig) ---
  static const int defaultRepeatCount = 3;
  static const int minRepeatCount = 1;
  static const int maxRepeatCount = 20;

  static const int defaultIntraBlockPauseMs = 300;
  static const int defaultBetweenRepeatPauseMs = 800;
  static const int defaultBetweenStepsPauseMs = 1500;

  static const double defaultPlaybackSpeed = 1.0;
  static const double minPlaybackSpeed = 0.5;
  static const double maxPlaybackSpeed = 1.5;

  /// Duration of the single silence spacer clip used to build gaps in the
  /// playback queue. Requested gaps are rounded to the nearest multiple.
  static const int silenceSpacerMs = 400;

  // --- Layout ---
  static const double designWidth = 375;
  static const double designHeight = 812;

  // --- Storage ---
  static const String progressBoxName = 'memorization_progress';
  static const String settingsBoxName = 'settings';
}
