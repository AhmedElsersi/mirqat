import 'package:flutter/material.dart';

/// The only place raw colour literals are allowed to appear.
/// Widgets read colours from `Theme.of(context)` or from these tokens.
class AppColors {
  const AppColors._();

  // Brand
  static const Color primary = Color(0xFF1F6B54);
  static const Color primaryDark = Color(0xFF7FCBAE);
  static const Color accent = Color(0xFFC9A227);

  // Light surfaces
  static const Color lightBackground = Color(0xFFFBF9F4);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEFEAE0);
  static const Color lightOutline = Color(0xFFD9D2C4);

  // Dark surfaces
  static const Color darkBackground = Color(0xFF10171A);
  static const Color darkSurface = Color(0xFF172126);
  static const Color darkSurfaceVariant = Color(0xFF222F35);
  static const Color darkOutline = Color(0xFF33444C);

  // Text
  static const Color lightTextPrimary = Color(0xFF16211D);
  static const Color lightTextSecondary = Color(0xFF5C6862);
  static const Color darkTextPrimary = Color(0xFFF2F5F3);
  static const Color darkTextSecondary = Color(0xFFA6B3AD);

  // Semantic
  static const Color error = Color(0xFFB3261E);
  static const Color success = Color(0xFF2E7D51);

  // Memorization status
  static const Color statusNotStarted = Color(0xFFBDC4C0);
  static const Color statusInProgress = Color(0xFFC9A227);
  static const Color statusMemorized = Color(0xFF2E7D51);

  /// Wash behind the ayah currently sounding.
  static const Color ayahHighlight = Color(0x331F6B54);

  /// Wash behind the whole block of a connect step.
  static const Color blockHighlight = Color(0x1AC9A227);
}
