import 'package:flutter/material.dart';

/// The only place raw colour literals are allowed to appear.
/// Widgets read colours from `Theme.of(context)` or from these tokens.
///
/// Every ratio quoted below is a measured WCAG 2.1 relative-luminance contrast
/// ratio, not an estimate. `test/core/brand_contrast_test.dart` recomputes the
/// load-bearing ones on every run, so a token cannot be nudged without the
/// suite noticing.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Brand constants, taken from the launcher icon: a gold mihrab arch and an
  // open, lit book on deep green. The UI used to wear an older palette — lapis
  // forest on cream — while the icon had already moved to green and gold, so the
  // icon and the app did not look like the same product. The owner settled it
  // on 2026-09-19 (docs/UI_OVERHAUL.md): the app follows the icon.
  //
  // The values are not the icon's pixels copied over. Each was moved, within
  // the icon's hue, to the nearest value that clears the contrast it needs;
  // `brand_contrast_test` recomputes every ratio quoted here on every run.
  // ---------------------------------------------------------------------------

  /// Primary brand: the icon's ground. Headings and filled controls on light,
  /// raised fills in dark mode. 9.0:1 on [cream].
  static const Color forest = Color(0xFF0B4E35);

  /// Dark-mode reading surface: the shadow inside the icon's arch, taken a
  /// step darker. The step is not taste — at the icon's own #06301F the two
  /// mode-blind status colours cannot clear 3:1 here and 4.5:1 on [cream] at
  /// once; at this value they can. 15.0:1 against [cream].
  static const Color forestDeep = Color(0xFF04241A);

  /// ACCENT ONLY — never a text colour on [cream]. The pairing measures
  /// 1.8:1, which fails every WCAG threshold including the 3:1 floor for
  /// non-text UI components; no amount of weight or size rescues it, and
  /// darkening it until it passes stops it being gold. Gold is permitted as:
  /// the frame and ornaments around a page, the active rung in the mark, a
  /// progress-bar fill, an icon tint on green, and a focus ring. Nowhere
  /// else. This is measurement, not taste — please do not re-litigate it.
  static const Color gold = Color(0xFFE1B45C);

  /// Light reading surface: the icon's book page, eased toward white. The
  /// page itself (#FAEDD5) is right for a glowing book an inch across and too
  /// yellow for a screen read for an hour.
  static const Color cream = Color(0xFFF9F4E6);

  /// The splash's ground: frame 0 of the launch animation, the cave interior.
  ///
  /// Appears in exactly three places that must agree, or the launch visibly
  /// seams: `flutter_native_splash`'s `color`/`color_dark` in pubspec.yaml,
  /// `@color/splash_background` in values{,-night}/colors.xml, and the
  /// ColoredBox behind the Flutter splash. Not a reading surface and not a
  /// theme colour — it is only ever the backdrop of the launch.
  static const Color caveDark = Color(0xFF1C1209);

  // ---------------------------------------------------------------------------
  // Mode-specific secondaries.
  //
  // These two tokens deliberately differ per mode. A single value cannot clear
  // 4.5:1 against both cream and forest-deep — a single `muted` and a single
  // `sabr` were tried under the first palette, measured 4.29/3.80 and 4.45/3.67, and failed on both
  // sides. Splitting them per mode is how Material 3 solves the same problem.
  // Do not collapse them back into one value.
  // ---------------------------------------------------------------------------

  /// Secondary text and disabled state, light mode. A green-grey, so that it
  /// belongs to the palette rather than sitting beside it. 4.68:1 on [cream].
  static const Color mutedLight = Color(0xFF65706B);

  /// Secondary text and disabled state, dark mode. 5.3:1 on [forestDeep].
  static const Color mutedDark = Color(0xFF7F978B);

  /// Completion states only, light mode. An emerald, lighter and bluer than
  /// [forest], so "memorized" reads as a state and not as more brand.
  /// 4.66:1 on [cream].
  static const Color sabrLight = Color(0xFF337A63);

  /// Completion states only, dark mode. 5.2:1 on [forestDeep].
  static const Color sabrDark = Color(0xFF3FA182);

  // ---------------------------------------------------------------------------
  // Semantic aliases. Every token below resolves to a brand constant or to a
  // point on the cream/forest ramps — there is one palette, not two.
  // ---------------------------------------------------------------------------

  /// Filled controls, light mode. `onPrimary` is [cream] (8.87:1).
  static const Color primary = forest;

  /// Filled controls, dark mode. `onPrimary` is [forestDeep] (15.02:1).
  /// Not [gold]: a filled gold control is a gold *surface*, which the brand
  /// forbids, and gold-as-fill is reserved for progress.
  static const Color primaryDark = cream;

  /// The active rung. Accent only — see the note on [gold].
  static const Color accent = gold;

  // Light surfaces. The ramp runs cream -> white, because `mutedLight` clears
  // 4.5:1 only against backgrounds at or lighter than cream; a card therefore
  // lifts toward white rather than tinting downward.
  static const Color lightBackground = cream;

  /// Raised cards. mutedLight 5.05:1, forest 9.57:1.
  static const Color lightSurface = Color(0xFFFFFDF6);

  /// Recessed fills — progress tracks, chips. Non-text use: see the note in
  /// the Phase 1 report about the one label still sitting on this token.
  static const Color lightSurfaceVariant = Color(0xFFEEE8D6);

  /// Hairline rules. Cream darkened; decorative, carries no information.
  static const Color lightOutline = Color(0xFFDED6C0);

  // Dark surfaces. Mirror logic: `mutedDark` clears 4.5:1 only at or below
  // forest-deep's luminance, so forest-deep is the *surface* and the page sits one
  // notch beneath it.
  static const Color darkBackground = Color(0xFF031A11);

  /// Reading surface. mutedDark 5.27:1, cream 15.02:1.
  static const Color darkSurface = forestDeep;

  /// Raised fills. cream 8.87:1.
  static const Color darkSurfaceVariant = forest;

  /// Hairline rules. Forest lightened; decorative.
  static const Color darkOutline = Color(0xFF1A5A42);

  // Text.
  static const Color lightTextPrimary = forest; // 8.87:1 on cream
  static const Color lightTextSecondary = mutedLight; // 4.68:1 on cream
  static const Color darkTextPrimary = cream; // 15.02:1 on forestDeep
  static const Color darkTextSecondary = mutedDark; // 5.27:1 on forestDeep

  // Semantic.
  /// 5.95:1 on [cream]. Unreadable on forest-deep (2.52:1) — dark mode uses
  /// [errorDark].
  static const Color error = Color(0xFFB3261E);

  /// 5.69:1 on [forestDeep]. `onError` is [forestDeep].
  static const Color errorDark = Color(0xFFEE7268);

  static const Color success = sabrLight;

  // Memorization status. These are borders and fills, never text, so the bar
  // is 3:1 rather than 4.5:1 — and each value clears it against *both* cream
  // and forest-deep, because the widgets that read them are mode-blind.
  static const Color statusNotStarted = mutedLight; // 4.68 / 3.21
  static const Color statusInProgress = gold; // 1.76 on cream — see report
  static const Color statusMemorized = sabrLight; // 4.66 / 3.23

  /// Wash behind the ayah currently sounding. Gold at 20% — a fill, not text.
  /// Forest stays at 7.95:1 over it on cream; cream at 10.0:1 over it on
  /// forest-deep.
  static const Color ayahHighlight = Color(0x33E1B45C);

  /// Fully transparent. A token rather than `Colors.transparent`, so the rule
  /// "no colour literal outside this file" has no exceptions to argue about —
  /// see `test/core/colour_literal_test.dart`.
  static const Color transparent = Color(0x00000000);

  // ---------------------------------------------------------------------------
  // Launch animation.
  //
  // These sit over photography, not over a theme surface, so they are not
  // theme-aware and do not appear in either ColorScheme — the splash looks the
  // same in light and dark because the plates do. They are listed here rather
  // than in the splash widget because `colour_literal_test` requires every
  // literal to live in this file, and because a colour no contrast test can
  // see is a colour nobody can check.
  // ---------------------------------------------------------------------------

  /// The wordmark on the splash: warm off-white, over the lit plaza.
  static const Color splashName = Color(0xFFFFFAEE);

  /// The slogan: pale gold, a step back from the name.
  static const Color splashSlogan = Color(0xFFF7DBA0);

  /// The hairline rule between them.
  static const Color splashHairline = Color(0xFFE2BE74);

  /// Soft drop shadow that holds the splash text over a bright, busy plate.
  static const Color splashTextShadow = Color(0x28160899);

  /// The sun bloom's core. Painted at a few percent alpha, so it reads as
  /// light rather than as a white shape.
  static const Color splashBloom = Color(0xFFFFFFFF);

  /// Wash behind the whole block of a connect step. Gold at 8%.
  /// Forest 8.5:1 over it on cream; cream 12.94:1 over it on forest-deep.
  static const Color blockHighlight = Color(0x14E1B45C);
}
