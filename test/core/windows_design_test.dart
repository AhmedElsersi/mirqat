/// The Windows look (core/theme/windows_design.dart): Fluent geometry,
/// density and type over the app's own colours.
///
/// Pumped as Windows through `debugDefaultTargetPlatformOverride`, which is
/// what `isDesktop` reads — so a phone keeps the phone's theme and only a
/// window gets this one.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/theme/app_colors.dart';
import 'package:mirqat/core/theme/app_theme.dart';
import 'package:mirqat/core/theme/window_chrome.dart';
import 'package:mirqat/core/theme/windows_design.dart';

/// Runs [body] with the platform reported as Windows.
T asWindows<T>(T Function() body) {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  try {
    return body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  // The frame group speaks over a platform channel, which needs the test
  // binding up; the theme groups are pure Dart and do not care.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('off a desktop', () {
    test('the theme is the phone theme, untouched', () {
      final ThemeData phone = AppTheme.light;

      // Material's finger-first density, and the app bar still centred as a
      // phone centres it.
      expect(phone.visualDensity, VisualDensity.standard);
      expect(phone.appBarTheme.centerTitle, isTrue);
    });

    test('apply hands back exactly what it was given', () {
      final ThemeData base = ThemeData(useMaterial3: true);

      expect(WindowsDesign.apply(base), same(base));
    });
  });

  group('in a window', () {
    test('the brand is not touched: the colours are still the app’s', () {
      final ThemeData light = asWindows(() => AppTheme.light);
      final ThemeData dark = asWindows(() => AppTheme.dark);

      expect(light.colorScheme.primary, AppColors.primary);
      expect(light.colorScheme.secondary, AppColors.accent);
      expect(light.scaffoldBackgroundColor, AppColors.lightBackground);
      expect(dark.colorScheme.primary, AppColors.primaryDark);
      expect(dark.scaffoldBackgroundColor, AppColors.darkBackground);
    });

    test('Fluent geometry: 4 on controls, 8 on what floats over them', () {
      final ThemeData theme = asWindows(() => AppTheme.light);

      BorderRadius radiusOf(ShapeBorder? shape) =>
          ((shape! as RoundedRectangleBorder).borderRadius as BorderRadius);

      expect(
        radiusOf(theme.cardTheme.shape),
        BorderRadius.circular(WindowsDesign.overlayRadius),
      );
      expect(
        radiusOf(theme.dialogTheme.shape),
        BorderRadius.circular(WindowsDesign.overlayRadius),
      );
      expect(
        radiusOf(theme.popupMenuTheme.shape),
        BorderRadius.circular(WindowsDesign.overlayRadius),
      );
      expect(
        radiusOf(theme.listTileTheme.shape),
        BorderRadius.circular(WindowsDesign.controlRadius),
      );
      expect(
        radiusOf(
          theme.filledButtonTheme.style!.shape!.resolve(<WidgetState>{}),
        ),
        BorderRadius.circular(WindowsDesign.controlRadius),
      );
      // The documented exception: a tooltip is too small for 8.
      expect(
        (theme.tooltipTheme.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(WindowsDesign.controlRadius),
      );
    });

    test('a button is 32 tall, as a pointer-first control is', () {
      final ThemeData theme = asWindows(() => AppTheme.light);
      final ButtonStyle style = theme.filledButtonTheme.style!;

      expect(
        style.minimumSize!.resolve(<WidgetState>{})!.height,
        WindowsDesign.controlHeight,
      );
      expect(theme.visualDensity, VisualDensity.compact);
    });

    test('the header titles the page at its leading edge, not centred', () {
      final ThemeData theme = asWindows(() => AppTheme.light);

      expect(theme.appBarTheme.centerTitle, isFalse);
      expect(theme.appBarTheme.toolbarHeight, WindowsDesign.headerHeight);
      expect(theme.appBarTheme.titleSpacing, WindowsDesign.gapEdge);
    });

    test('the Windows type ramp, to the epx', () {
      final TextTheme text = asWindows(() => AppTheme.light).textTheme;

      void ramp(TextStyle? style, double size, double lineHeight, int weight) {
        expect(style?.fontSize, size);
        expect(style?.height, lineHeight / size);
        expect(style?.fontWeight?.value, weight);
      }

      ramp(text.bodySmall, 12, 16, 400); // Caption
      ramp(text.bodyMedium, 14, 20, 400); // Body
      ramp(text.bodyLarge, 14, 20, 400); // Body
      ramp(text.titleSmall, 14, 20, 600); // Body Strong
      ramp(text.labelLarge, 14, 20, 600); // Body Strong
      ramp(text.titleMedium, 18, 24, 600); // Body Large Strong
      ramp(text.titleLarge, 20, 28, 600); // Subtitle
      ramp(text.headlineMedium, 28, 36, 600); // Title
      ramp(text.displayLarge, 40, 52, 600); // Title Large
    });

    test('nothing is bold: Semibold is the ramp’s heaviest weight', () {
      final TextTheme text = asWindows(() => AppTheme.light).textTheme;

      final List<TextStyle?> every = <TextStyle?>[
        text.displayLarge,
        text.displayMedium,
        text.displaySmall,
        text.headlineLarge,
        text.headlineMedium,
        text.headlineSmall,
        text.titleLarge,
        text.titleMedium,
        text.titleSmall,
        text.bodyLarge,
        text.bodyMedium,
        text.bodySmall,
        text.labelLarge,
        text.labelMedium,
        text.labelSmall,
      ];

      for (final TextStyle? style in every) {
        expect(style, isNotNull);
        expect(
          style!.fontWeight!.value,
          lessThanOrEqualTo(FontWeight.w600.value),
          reason: 'the Windows ramp has no Bold; Semibold carries emphasis',
        );
        // Italic is off the ramp too — it costs legibility.
        expect(style.fontStyle ?? FontStyle.normal, FontStyle.normal);
      }
    });

    test('a list row reads Body over Caption, as Fluent lists do', () {
      final ThemeData theme = asWindows(() => AppTheme.light);

      expect(theme.listTileTheme.titleTextStyle?.fontSize, 14);
      expect(theme.listTileTheme.subtitleTextStyle?.fontSize, 12);
      expect(theme.listTileTheme.horizontalTitleGap, WindowsDesign.gapRelated);
    });

    test(
      'no font family is named: the platform’s face is the Windows face',
      () {
        final TextTheme text = asWindows(() => AppTheme.light).textTheme;

        // Segoe UI is what Windows gives an app that asks for nothing, and it
        // is Microsoft's own UI font for Arabic — so the ramp is applied over
        // whatever the platform hands us, and no family is set here.
        expect(text.bodyMedium?.fontFamily, isNull);
        expect(text.titleLarge?.fontFamily, isNull);
      },
    );
  });

  group('the window frame', () {
    setUp(WindowChrome.reset);

    test('is left alone off Windows', () async {
      // The host of these tests is a Mac, so this is the real answer rather
      // than a mocked one: nothing is sent, and nothing throws.
      expect(WindowChrome.supported, isFalse);
      await WindowChrome.follow(AppTheme.dark);
    });

    test('is told the theme’s own colours, once per change', () async {
      final List<MethodCall> sent = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(WindowChrome.channel, (
            MethodCall call,
          ) async {
            sent.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowChrome.channel, null),
      );
      WindowChrome.debugSupportedOverride = true;

      final ThemeData dark = AppTheme.dark;
      await WindowChrome.follow(dark);

      expect(sent, hasLength(1));
      expect(sent.single.method, 'applyTheme');
      final Map<Object?, Object?> args =
          sent.single.arguments as Map<Object?, Object?>;
      expect(args['dark'], isTrue);
      // The caption takes the page's own colour, so the window reads as one
      // piece from its top edge down.
      expect(args['caption'], dark.scaffoldBackgroundColor.toARGB32());
      expect(args['text'], dark.colorScheme.onSurface.toARGB32());
      expect(args['border'], dark.colorScheme.outline.toARGB32());

      // A window resize rebuilds; the frame is not told the same thing twice.
      await WindowChrome.follow(dark);
      expect(sent, hasLength(1));

      // The reader switches to light: that it is told.
      await WindowChrome.follow(AppTheme.light);
      expect(sent, hasLength(2));
      expect((sent.last.arguments as Map<Object?, Object?>)['dark'], isFalse);
    });

    test('a runner that does not know the channel is not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            WindowChrome.channel,
            (MethodCall call) async =>
                throw PlatformException(code: 'unavailable'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(WindowChrome.channel, null),
      );
      WindowChrome.debugSupportedOverride = true;

      // An older Windows refuses the attributes; the app keeps running and
      // the frame simply stays as Windows drew it (A.2 rule 3's spirit).
      await WindowChrome.follow(AppTheme.light);
    });
  });
}
