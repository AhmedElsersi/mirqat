/// Application-wide constants.
///
/// Nothing here may describe a specific surah or reciter — those live only in
/// the JSON catalog under `assets/data/` (see CLAUDE.md A.2 rule 2).
class AppConstants {
  const AppConstants._();

  // --- Session defaults (CLAUDE.md / Part B, SessionConfig) ---
  static const int defaultRepeatCount = 3;
  static const int minRepeatCount = 1;
  static const int maxRepeatCount = 999;

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

  /// From this shortest side up, the screen is a tablet, and dimensions are
  /// scaled from [tabletDesignWidth] x [tabletDesignHeight] instead.
  ///
  /// `flutter_screenutil` multiplies every `.w`, `.h` and `.r` by the ratio of
  /// the screen to the design. Against a phone-sized design a 13-inch iPad is
  /// 2.75 times as wide, so every padding, avatar and row came out nearly
  /// three times its size — while the theme's text, which is not scaled,
  /// stayed at 14 to 16 points. The result was small text adrift in huge rows,
  /// and a grid whose tiles overflowed. Against a tablet-sized design the
  /// same iPad scales by about a third, which is what a tablet wants.
  ///
  /// 700, so that the smallest iPad (744) is a tablet and no phone is — the
  /// largest phones are about 440 wide.
  static const double tabletShortestSide = 700;
  static const double tabletDesignWidth = 768;
  static const double tabletDesignHeight = 1024;

  /// Where the home grid goes from two columns to three.
  ///
  /// 600dp is Material 3's compact/medium window boundary, not a number picked
  /// to suit one device. Compared against the real window width rather than a
  /// ScreenUtil-scaled value: the question is how much room there is, and
  /// `.w` would answer a different one.
  static const double tabletBreakpoint = 600;

  // --- Storage ---
  static const String progressBoxName = 'memorization_progress';
  static const String settingsBoxName = 'settings';
  static const String readingHistoryBoxName = 'reading_history';

  // Download state is NOT here: it lives in its own writable `downloads.db`
  // (see DownloadsDatabase), not in a Hive box and never in `quran.db`, which
  // ships read-only and is replaced wholesale on a schema bump
  // (CLAUDE.md A.2 rule 6).

  /// Schema version of `assets/data/quran.db` (its own `meta.schema_version`
  /// row, kept in step with `tool/build_quran_data.py`). `QuranDatabase`
  /// copies the bundled file to `quran_v<version>.db` on first run and
  /// deletes any other `quran_v*.db` it finds, so bumping this is what makes
  /// an app update replace a stale copy instead of opening it read-only
  /// forever.
  static const int quranDatabaseSchemaVersion = 2;
}
