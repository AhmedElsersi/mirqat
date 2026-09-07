import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the light and dark [ThemeData] from the [AppColors] tokens.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(
    brightness: Brightness.light,
    primary: AppColors.primary,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceVariant: AppColors.lightSurfaceVariant,
    outline: AppColors.lightOutline,
    textPrimary: AppColors.lightTextPrimary,
    textSecondary: AppColors.lightTextSecondary,
    onPrimary: AppColors.lightSurface,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    primary: AppColors.primaryDark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceVariant: AppColors.darkSurfaceVariant,
    outline: AppColors.darkOutline,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    onPrimary: AppColors.darkBackground,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color surfaceVariant,
    required Color outline,
    required Color textPrimary,
    required Color textSecondary,
    required Color onPrimary,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: AppColors.accent,
      onSecondary: AppColors.lightTextPrimary,
      error: AppColors.error,
      onError: AppColors.lightSurface,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: textSecondary,
      outline: outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      dividerTheme: DividerThemeData(color: outline, space: 1, thickness: 1),
    );
  }
}
