import 'package:flutter/material.dart';

import '../desktop.dart';

/// Fluent geometry, density and typography, laid over the app's own theme on
/// a desktop.
///
/// The brand does not change here: every colour still comes from the
/// [ThemeData] handed in, which is built from `AppColors` (CLAUDE.md A.3).
/// What changes is everything Windows readers judge an app's nativeness by —
/// how round a corner is, how tall a button is, how large body text is, how
/// far apart two things sit — because those are conventions of the platform
/// rather than of the product. A Windows reader should feel the app belongs
/// on their desk; an Arabic reader should still see the same green, gold and
/// cream they see on their phone.
///
/// Every number below is Microsoft's, from the Windows 11 design guidance:
/// geometry (corner radius), content layout and spacing, and the type ramp.
/// Nothing here is invented, and nothing is a matter of taste — which is why
/// each one is named rather than inlined.
///
/// Typography names no font family. The app declares none either — the UI
/// face is deliberately the platform's (`AppTextStyles.uiFontFamily` is not
/// bundled yet), and on Windows the platform's face is Segoe UI, which is
/// Microsoft's own UI font for Arabic. So adopting the ramp's *metrics* is
/// all it takes to be set in the system font at system sizes.
abstract final class WindowsDesign {
  /// In-page controls — buttons, text fields, list backplates, bars.
  ///
  /// `ControlCornerRadius`, Microsoft's default.
  static const double controlRadius = 4;

  /// Top-level containers — cards, dialogs, flyouts, menus.
  ///
  /// `OverlayCornerRadius`. A tooltip is the documented exception and takes
  /// [controlRadius] instead, being too small for 8.
  static const double overlayRadius = 8;

  /// The 4px grid everything lands on: 8 between a control and its header or
  /// its neighbour, 12 between a control and its label or between two content
  /// areas, 16 from a surface's edge to the text inside it.
  static const double gapTight = 8;
  static const double gapRelated = 12;
  static const double gapEdge = 16;

  /// A standard control's height. Fluent's touch target is 40 and its
  /// pointer-first control is 32; a window on a desk is pointer-first.
  static const double controlHeight = 32;

  /// The window's own header. Fluent's title area, not Material's 56.
  static const double headerHeight = 48;

  /// [base], made to look like it belongs on Windows. Off a desktop, [base]
  /// is returned untouched — a phone is not a window.
  static ThemeData apply(ThemeData base) {
    if (!isDesktop) return base;

    final ColorScheme colors = base.colorScheme;
    final TextTheme text = _ramp(base.textTheme);
    final BorderSide hairline = BorderSide(color: colors.outline);
    final RoundedRectangleBorder control = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(controlRadius),
    );
    final RoundedRectangleBorder overlay = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(overlayRadius),
    );

    return base.copyWith(
      // Fluent is pointer-first and tighter than Material's finger-first
      // default; this is what takes a row from 56 tall to 40.
      visualDensity: VisualDensity.compact,
      textTheme: text,
      primaryTextTheme: text,

      // The header carries the page's name at the leading edge, not centred:
      // a Windows app titles its page the way it reads. Directional, so an
      // Arabic window titles from the right without being told.
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: false,
        toolbarHeight: headerHeight,
        titleTextStyle: text.titleLarge,
        titleSpacing: gapEdge,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      cardTheme: base.cardTheme.copyWith(
        shape: overlay.copyWith(side: hairline),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),

      // A stroke and no shadow: Fluent separates layers with a hairline and
      // the material behind them, where Material 3 would raise a surface.
      dialogTheme: base.dialogTheme.copyWith(
        shape: overlay,
        elevation: 0,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        shape: overlay.copyWith(side: hairline),
        elevation: 0,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            overlay.copyWith(side: hairline),
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
        ),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(overlayRadius),
          ),
        ),
        elevation: 0,
      ),
      // The documented exception: a tooltip is too small for 8.
      tooltipTheme: base.tooltipTheme.copyWith(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.fromBorderSide(hairline),
          borderRadius: BorderRadius.circular(controlRadius),
        ),
        textStyle: text.bodySmall,
      ),

      filledButtonTheme: FilledButtonThemeData(style: _buttonStyle(text)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _buttonStyle(text)),
      textButtonTheme: TextButtonThemeData(style: _buttonStyle(text)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _buttonStyle(
          text,
        ).copyWith(side: WidgetStatePropertyAll<BorderSide>(hairline)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(control),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size.square(controlHeight),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(control),
          textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
          side: WidgetStatePropertyAll<BorderSide>(hairline),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(shape: control, side: hairline),

      // Primary text at Body, the line under it at Caption — Fluent's own
      // recipe for a multi-line list row.
      listTileTheme: base.listTileTheme.copyWith(
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall,
        minVerticalPadding: gapTight / 2,
        horizontalTitleGap: gapRelated,
        shape: control,
      ),

      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: gapRelated,
          vertical: gapTight,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: hairline,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: hairline,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
      ),

      // A bar is a bar: rounded ends at the control radius, never a stadium.
      progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
        borderRadius: BorderRadius.circular(controlRadius),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: 4,
        overlayShape: SliderComponentShape.noOverlay,
      ),

      // Windows scrollbars sit in the gutter and are seen when they matter.
      scrollbarTheme: base.scrollbarTheme.copyWith(
        thickness: const WidgetStatePropertyAll<double>(gapTight),
        radius: const Radius.circular(controlRadius),
        thumbVisibility: const WidgetStatePropertyAll<bool>(false),
        interactive: true,
      ),

      dividerTheme: base.dividerTheme.copyWith(space: 1, thickness: 1),
    );
  }

  /// A Fluent button: 32 tall, 12 in from each end, a 4px corner, and its
  /// label in Body Strong.
  static ButtonStyle _buttonStyle(TextTheme text) => ButtonStyle(
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(controlRadius),
      ),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, controlHeight)),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsetsDirectional.symmetric(horizontal: gapRelated),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
    elevation: const WidgetStatePropertyAll<double>(0),
  );

  /// The Windows type ramp, in effective pixels, over whatever family the
  /// platform gives us.
  ///
  /// | Fluent style      | size/line | weight   | Material slot        |
  /// |-------------------|-----------|----------|----------------------|
  /// | Caption           | 12/16     | regular  | bodySmall, label*    |
  /// | Body              | 14/20     | regular  | bodyMedium, bodyLarge|
  /// | Body Strong       | 14/20     | semibold | titleSmall, labelLarge|
  /// | Body Large Strong | 18/24     | semibold | titleMedium          |
  /// | Subtitle          | 20/28     | semibold | titleLarge           |
  /// | Title             | 28/36     | semibold | headline*            |
  /// | Title Large       | 40/52     | semibold | display*             |
  ///
  /// Bold and italic are not on the ramp at all: Microsoft asks for Semibold
  /// in place of Bold, and leaves italic out because it costs legibility for
  /// dyslexic readers. So nothing here is heavier than w600 — which is also
  /// why this cannot simply scale the app's phone styles.
  static TextTheme _ramp(TextTheme base) {
    TextStyle style(double size, double lineHeight, {bool strong = false}) =>
        TextStyle(
          fontSize: size,
          height: lineHeight / size,
          fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
        );

    final TextStyle caption = style(12, 16);
    final TextStyle body = style(14, 20);
    final TextStyle bodyStrong = style(14, 20, strong: true);

    return base.copyWith(
      displayLarge: style(40, 52, strong: true),
      displayMedium: style(40, 52, strong: true),
      displaySmall: style(28, 36, strong: true),
      headlineLarge: style(28, 36, strong: true),
      headlineMedium: style(28, 36, strong: true),
      headlineSmall: style(20, 28, strong: true),
      titleLarge: style(20, 28, strong: true),
      titleMedium: style(18, 24, strong: true),
      titleSmall: bodyStrong,
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: caption,
      labelLarge: bodyStrong,
      labelMedium: caption,
      labelSmall: caption,
    );
  }
}
