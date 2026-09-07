import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Text style tokens.
///
/// These are getters, not `const` fields, because `.sp` needs `ScreenUtil`
/// to be initialised before it can resolve.
class AppTextStyles {
  const AppTextStyles._();

  /// Family for Quranic text. `null` falls back to the platform Arabic font
  /// until an Uthmani-capable font is bundled.
  static const String? quranFontFamily = null;

  static TextStyle get displayLarge =>
      TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w700, height: 1.3);

  static TextStyle get titleLarge =>
      TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w600, height: 1.35);

  static TextStyle get titleMedium =>
      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, height: 1.4);

  static TextStyle get bodyLarge =>
      TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get bodyMedium =>
      TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w400, height: 1.5);

  static TextStyle get labelSmall =>
      TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500, height: 1.4);

  /// Ayah text. Generous line height so diacritics are never crowded, and
  /// never a style that could clip or ellipsize (CLAUDE.md A.2 rule 7).
  static TextStyle ayah({required double fontSize}) => TextStyle(
    fontFamily: quranFontFamily,
    fontSize: fontSize.sp,
    fontWeight: FontWeight.w400,
    height: 2.0,
  );
}
