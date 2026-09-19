import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Text style tokens.
///
/// These are getters, not `const` fields, because `.sp` needs `ScreenUtil`
/// to be initialised before it can resolve.
class AppTextStyles {
  const AppTextStyles._();

  /// Family for all UI text: IBM Plex Sans Arabic, declared in pubspec.yaml
  /// as `IqraWartaqUI` across four weights (400/500/600/700).
  ///
  /// This string must match the `family:` in pubspec.yaml exactly. A mismatch
  /// does not fail the build — Flutter silently falls back to the platform
  /// face — so the two are renamed together or not at all.
  static const String uiFontFamily = 'IqraWartaqUI';

  /// Family for Quranic text: UthmanicHafs V22, declared in pubspec.yaml — the
  /// font that ships with the script export `quran.db` is built from. Verified
  /// by `tools/check_font_coverage.py` to cover all 81 codepoints in quran.db's
  /// ayah and word text, including U+0671 alef wasla, U+06E1 Uthmani sukun,
  /// U+0670 superscript alef, U+0653 maddah and the ayah-number digits.
  ///
  /// This constant, and [ayah] below, are the only places the family is named
  /// in Dart. `test/core/font_enforcement_test.dart` proves it, because the
  /// failure mode here is invisible: IBM Plex Sans Arabic *contains* the
  /// Quranic mark repertoire, so an ayah rendered in the UI font shows no tofu
  /// and no error — it just silently stops being the mushaf's diacritic
  /// placement.
  static const String quranFontFamily = 'QuranUthmani';

  static TextStyle get displayLarge => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 28.sp,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static TextStyle get titleLarge => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 20.sp,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static TextStyle get titleMedium => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 16.sp,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static TextStyle get bodyLarge => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 15.sp,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static TextStyle get bodyMedium => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 13.sp,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static TextStyle get labelSmall => TextStyle(
    fontFamily: uiFontFamily,
    fontSize: 11.sp,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );

  /// Ayah text. The one and only style permitted to use [quranFontFamily].
  ///
  /// `height: 2.0` is not decoration: Uthmani diacritics stack tall — a
  /// superscript alef above a shadda above a letter — and clip at the default
  /// line height. Never a style that could truncate or ellipsize
  /// (CLAUDE.md A.2 rule 7).
  ///
  /// Call this from `AyahText` only. Nothing else may render Quranic text.
  static TextStyle ayah({required double fontSize}) => TextStyle(
    fontFamily: quranFontFamily,
    fontSize: fontSize.sp,
    fontWeight: FontWeight.w400,
    height: 2.0,
  );

  /// One word on a mushaf page.
  ///
  /// [fontSize] is exact logical pixels — no `.sp`, no stretched line height —
  /// because the page computes it to fit the screen and must never scroll.
  ///
  /// Call this from `AyahText` only, like [ayah].
  static TextStyle mushafWord({required double fontSize}) => TextStyle(
    fontFamily: quranFontFamily,
    fontSize: fontSize,
    fontWeight: FontWeight.w400,
  );
}
