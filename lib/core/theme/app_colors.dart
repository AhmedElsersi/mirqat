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
  // Brand constants (docs/BRAND_GUIDE.md §4).
  // Drawn from manuscript illumination: lapis, gold leaf, vellum.
  //
  // NOTE: the app's UI still wears the ORIGINAL palette — lapis ink and warm
  // vellum — while the brand around it has moved to green and gold: the
  // launcher icon is a gold mihrab arch on #0C5238, and the splash is the cave
  // interior, #1C1209. So the icon and the first screen do not currently share
  // a palette with the rest of the app.
  //
  // Reconciling them is a design decision with measured accessibility
  // consequences — every ratio below is recomputed by brand_contrast_test on
  // every run — so it is deliberately NOT done here. Raised in the report.
  // ---------------------------------------------------------------------------

  /// Primary brand. Headings on light, icon ground, dark-mode raised fills.
  /// 14.09:1 on [vellum].
  static const Color ink = Color(0xFF16233F);

  /// Dark-mode reading surface. 16.33:1 against [vellum].
  static const Color inkDeep = Color(0xFF0E1626);

  /// ACCENT ONLY — never a text colour on [vellum]. The pairing measures
  /// 2.12:1, which fails every WCAG threshold including the 3:1 floor for
  /// non-text UI components; no amount of weight or size rescues it, and
  /// darkening it until it passes stops it being gold. Gold is permitted as:
  /// the active rung in the mark, a progress-bar fill, an icon tint on ink,
  /// and a focus ring. Nowhere else. This is measurement, not taste — please
  /// do not re-litigate it.
  static const Color gold = Color(0xFFC8A54B);

  /// Light reading surface. Warm, and easier than white over a long session.
  static const Color vellum = Color(0xFFF7F3EA);

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
  // 4.5:1 against both vellum and ink-deep — the guide's original single
  // `muted` and `sabr` measured 4.29/3.80 and 4.45/3.67 and failed on both
  // sides. Splitting them per mode is how Material 3 solves the same problem.
  // Do not collapse them back into one value.
  // ---------------------------------------------------------------------------

  /// Secondary text and disabled state, light mode. 4.62:1 on [vellum].
  static const Color mutedLight = Color(0xFF666E7F);

  /// Secondary text and disabled state, dark mode. 4.63:1 on [inkDeep].
  static const Color mutedDark = Color(0xFF798193);

  /// Completion states only, light mode. 4.69:1 on [vellum].
  static const Color sabrLight = Color(0xFF2D7968);

  /// Completion states only, dark mode. 4.67:1 on [inkDeep].
  static const Color sabrDark = Color(0xFF35907B);

  // ---------------------------------------------------------------------------
  // Semantic aliases. Every token below resolves to a brand constant or to a
  // point on the vellum/ink ramps — there is one palette, not two.
  // ---------------------------------------------------------------------------

  /// Filled controls, light mode. `onPrimary` is [vellum] (14.09:1).
  static const Color primary = ink;

  /// Filled controls, dark mode. `onPrimary` is [inkDeep] (16.33:1).
  /// Not [gold]: a filled gold control is a gold *surface*, which the brand
  /// forbids, and gold-as-fill is reserved for progress.
  static const Color primaryDark = vellum;

  /// The active rung. Accent only — see the note on [gold].
  static const Color accent = gold;

  // Light surfaces. The ramp runs vellum -> white, because `mutedLight` clears
  // 4.5:1 only against backgrounds at or lighter than vellum; a card therefore
  // lifts toward white rather than tinting downward.
  static const Color lightBackground = vellum;

  /// Raised cards. mutedLight 5.03:1, ink 15.33:1.
  static const Color lightSurface = Color(0xFFFFFDF7);

  /// Recessed fills — progress tracks, chips. Non-text use: see the note in
  /// the Phase 1 report about the one label still sitting on this token.
  static const Color lightSurfaceVariant = Color(0xFFEDE7D9);

  /// Hairline rules. Vellum darkened; decorative, carries no information.
  static const Color lightOutline = Color(0xFFDDD5C4);

  // Dark surfaces. Mirror logic: `mutedDark` clears 4.5:1 only at or below
  // ink-deep's luminance, so ink-deep is the *surface* and the page sits one
  // notch beneath it.
  static const Color darkBackground = Color(0xFF0A101C);

  /// Reading surface. mutedDark 4.63:1, vellum 16.33:1.
  static const Color darkSurface = inkDeep;

  /// Raised fills. vellum 14.09:1.
  static const Color darkSurfaceVariant = ink;

  /// Hairline rules. Ink lightened; decorative.
  static const Color darkOutline = Color(0xFF26314A);

  // Text.
  static const Color lightTextPrimary = ink; // 14.09:1 on vellum
  static const Color lightTextSecondary = mutedLight; // 4.62:1 on vellum
  static const Color darkTextPrimary = vellum; // 16.33:1 on inkDeep
  static const Color darkTextSecondary = mutedDark; // 4.63:1 on inkDeep

  // Semantic.
  /// 5.90:1 on [vellum]. Unreadable on ink-deep (2.77:1) — dark mode uses
  /// [errorDark].
  static const Color error = Color(0xFFB3261E);

  /// 5.60:1 on [inkDeep]. `onError` is [inkDeep].
  static const Color errorDark = Color(0xFFE6685E);

  static const Color success = sabrLight;

  // Memorization status. These are borders and fills, never text, so the bar
  // is 3:1 rather than 4.5:1 — and each value clears it against *both* vellum
  // and ink-deep, because the widgets that read them are mode-blind.
  static const Color statusNotStarted = mutedLight; // 4.62 / 3.53
  static const Color statusInProgress = gold; // 2.12 on vellum — see report
  static const Color statusMemorized = sabrLight; // 4.69 / 3.48

  /// Wash behind the ayah currently sounding. Gold at 20% — a fill, not text.
  /// Ink stays at 12.24:1 over it on vellum; vellum at 11.48:1 over it on
  /// ink-deep.
  static const Color ayahHighlight = Color(0x33C8A54B);

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
  /// Ink 13.35:1 over it on vellum; vellum 14.57:1 over it on ink-deep.
  static const Color blockHighlight = Color(0x14C8A54B);
}
