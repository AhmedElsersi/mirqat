import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'windows_design.dart';

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
    onPrimary: AppColors.cream,
    error: AppColors.error,
    onError: AppColors.cream,
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
    onPrimary: AppColors.forestDeep,
    error: AppColors.errorDark,
    onError: AppColors.forestDeep,
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
    required Color error,
    required Color onError,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: AppColors.accent,
      // Gold is an accent, never a text colour on a light surface; ink on gold
      // measures 6.64:1, which is the only direction that pairing works.
      onSecondary: AppColors.forest,
      error: error,
      onError: onError,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: textSecondary,
      outline: outline,
    );

    return WindowsDesign.apply(
      ThemeData(
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
        // The four tabs: the page's own surface, the chosen one marked with
        // the gold the rest of the app reserves for "where you are".
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: surface,
          surfaceTintColor: AppColors.transparent,
          // The design's `--gold-soft`: a wash of gold behind the chosen
          // tab's icon, a pill — never a gold surface.
          indicatorColor: AppColors.gold.withValues(alpha: 0.2),
          indicatorShape: const StadiumBorder(),
          height: 68,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? textPrimary
                  : textSecondary,
            ),
          ),
          iconTheme: WidgetStateProperty.resolveWith(
            (Set<WidgetState> states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? textPrimary
                  : textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
