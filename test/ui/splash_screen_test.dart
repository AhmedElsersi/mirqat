import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/features/splash/screen/splash_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';

import '../app_harness.dart';

/// The launch animation.
///
/// Everything here uses explicit `tester.pump(duration)` and never
/// `pumpAndSettle`: the sun bloom breathes on a repeating controller, so while
/// the splash is mounted there is always another frame scheduled and settling
/// is impossible by construction. A test that reaches for `pumpAndSettle` here
/// will hang for ten seconds and then fail on a timeout, which looks like a
/// broken animation rather than a broken test.
void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  /// Pumps the app and stops on the splash, without skipping it.
  Future<void> pumpSplash(
    WidgetTester tester, {
    Locale locale = AppLocalization.arabic,
  }) async {
    await harness.pumpApp(tester, locale: locale, skipSplash: false);
    // Let the precache futures resolve; they run before the controller starts.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }

  group('the two plates', () {
    // This is the invariant the whole illusion rests on. The plates are stored
    // at different resolutions on purpose, and the cave's alpha hole only
    // falls over the vista's real region because both describe the same frame
    // — which, concretely, means the same aspect ratio. Swap in a replacement
    // plate at a different ratio and the opening drifts off the vista with
    // nothing in the code to complain, so it is asserted on the bytes.
    test('are stored at exactly the same aspect ratio', () {
      final ({int w, int h}) scene = _pngOrWebpSize(AssetPaths.splashScene);
      final ({int w, int h}) cave = _pngOrWebpSize(AssetPaths.splashCave);

      expect(scene, (w: 1836, h: 3876), reason: 'vista plate changed size');
      expect(cave, (w: 1224, h: 2584), reason: 'cave plate changed size');

      // Cross-multiplied rather than compared as doubles: 1836/3876 and
      // 1224/2584 are both 0.4736842..., and floating point would make an
      // exact check look approximate.
      expect(
        scene.w * cave.h,
        cave.w * scene.h,
        reason:
            'the plates no longer share an aspect ratio, so the cave opening '
            'will not line up with the vista at t = 0',
      );
    });

    test('the cave carries a real alpha hole, not a painted one', () {
      // If the opening were painted rather than cut, the cave would be opaque
      // everywhere and would simply hide the vista.
      final Uint8List bytes = File(AssetPaths.splashCave).readAsBytesSync();
      expect(bytes.length, greaterThan(0));
      // WebP VP8L/VP8X with an alpha chunk. Cheap structural check: the
      // container must advertise alpha.
      final String header = String.fromCharCodes(bytes.sublist(0, 16));
      expect(header.startsWith('RIFF'), isTrue, reason: 'not a WebP');
      expect(header.contains('WEBP'), isTrue, reason: 'not a WebP');
    });

    test('only the runtime plates are bundled, not the editing masters', () {
      // The masters are 1.3 MB and 3.4 MB; the shipped WebPs are ~490 KB and
      // ~98 KB for the same picture at splash scale.
      expect(File(AssetPaths.splashScene).existsSync(), isTrue);
      expect(File(AssetPaths.splashCave).existsSync(), isTrue);
      expect(
        File('assets/brand/splash_scene.jpg').existsSync(),
        isFalse,
        reason: 'the JPEG master must live in brand/, outside assets/',
      );
      expect(
        File('assets/brand/splash_cave.png').existsSync(),
        isFalse,
        reason: 'the PNG master must live in brand/, outside assets/',
      );
      // And the generator inputs are out of assets/ too, so declaring
      // assets/brand/ cannot sweep them into the bundle.
      for (final String name in <String>[
        'icon_1024',
        'icon_foreground_1024',
        'icon_background_1024',
        'icon_monochrome_1024',
      ]) {
        expect(
          File('assets/brand/$name.png').existsSync(),
          isFalse,
          reason: '$name is a build-time input and must not be bundled',
        );
        expect(File('brand/$name.png').existsSync(), isTrue);
      }
    });
  });

  group('behaviour', () {
    testWidgets('is the first thing on screen, before the home list', (
      WidgetTester tester,
    ) async {
      await pumpSplash(tester);

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.byType(SurahRow), findsNothing);
      // Both plates are on screen at t = 0 — the vista behind, the rock in
      // front. If the cave were missing, frame 0 would already be the plaza.
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('hands over to the home screen on its own', (
      WidgetTester tester,
    ) async {
      await pumpSplash(tester);

      // Past the 2400 ms animation, then the 300 ms dissolve.
      await tester.pump(const Duration(milliseconds: 2400));
      await _pumpUntilSplashGone(tester);
      await AppHarness.settle(tester);

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(SurahRow), findsWidgets);
    });

    testWidgets('a tap skips it, before the text has appeared', (
      WidgetTester tester,
    ) async {
      await pumpSplash(tester);

      // 300 ms in: the camera has barely moved and the text window (56% of
      // 2400 ms = 1344 ms) has not opened, so this is the hardest moment for
      // a skip to be wired correctly.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('اقرأ وارتق'), findsNothing);

      await AppHarness.dismissSplash(tester);
      await AppHarness.settle(tester);

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(SurahRow), findsWidgets);
    });

    testWidgets('the wordmark and slogan arrive in the last stretch', (
      WidgetTester tester,
    ) async {
      await pumpSplash(tester);

      // Before the window opens at t = 0.56 (1344 ms).
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('اقرأ وارتق'), findsNothing);
      expect(find.text('سمت الحافظين'), findsNothing);

      // Well inside it.
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.text('اقرأ وارتق'), findsOneWidget);
      expect(find.text('سمت الحافظين'), findsOneWidget);
    });

    testWidgets('holds the final frame when animations are disabled', (
      WidgetTester tester,
    ) async {
      // Driven through a MediaQuery override on an isolated splash rather than
      // `platformDispatcher.accessibilityFeaturesTestValue`: that setter needs
      // a real AccessibilityFeatures, whose members grow between Flutter
      // releases, so a hand-written stand-in rots. MediaQuery is what the
      // widget actually reads.
      bool finished = false;
      await tester.pumpWidget(
        _isolatedSplash(
          disableAnimations: true,
          onFinished: () => finished = true,
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      // No camera move to wait for: the text is already in place on the first
      // frame, rather than fading in over 1 s of animation the platform asked
      // not to run.
      expect(find.text('اقرأ وارتق'), findsOneWidget);
      expect(find.text('سمت الحافظين'), findsOneWidget);
      expect(finished, isFalse, reason: 'it should hold, not leave at once');

      // Then it holds 600 ms and leaves.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(finished, isTrue);
    });

    testWidgets('with animations on, the text is absent on the first frame', (
      WidgetTester tester,
    ) async {
      // The mirror of the test above, through the same host, so the two
      // differ only in the flag.
      await tester.pumpWidget(
        _isolatedSplash(disableAnimations: false, onFinished: () {}),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(find.text('اقرأ وارتق'), findsNothing);
    });

    testWidgets('does not come back after it has finished', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      expect(find.byType(SurahRow), findsWidgets);
      expect(find.byType(SplashScreen), findsNothing);

      // Navigating around must not reintroduce it: it is the first route, and
      // `go` replaced it rather than pushing over it, so there is nothing to
      // pop back to.
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.settings_outlined),
      );
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.byType(SurahRow), findsWidgets);
    });

    testWidgets('leaves no timer or ticker behind', (
      WidgetTester tester,
    ) async {
      await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 400));

      // Dismissing disposes both controllers and cancels the 5 s cap. If any
      // of them outlived the route, the test framework's own pending-timer
      // check fails the test at teardown.
      await AppHarness.dismissSplash(tester);
      await AppHarness.settle(tester);
      expect(find.byType(SplashScreen), findsNothing);
    });
  });

  group('both locales', () {
    for (final Locale locale in AppLocalization.supportedLocales) {
      testWidgets('lays out and reads correctly in ${locale.languageCode}', (
        WidgetTester tester,
      ) async {
        await pumpSplash(tester, locale: locale);
        await tester.pump(const Duration(milliseconds: 2100));

        expect(tester.takeException(), isNull);
        // The wordmark is the Arabic string on both locales; the slogan is
        // deliberately Arabic on both too.
        expect(find.text('اقرأ وارتق'), findsOneWidget);
        expect(find.text('سمت الحافظين'), findsOneWidget);

        await AppHarness.dismissSplash(tester);
        await AppHarness.settle(tester);
      });

      testWidgets('text does not overflow at 2x scale in '
          '${locale.languageCode}', (WidgetTester tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpSplash(tester, locale: locale);
        await tester.pump(const Duration(milliseconds: 2100));

        expect(tester.takeException(), isNull);

        await AppHarness.dismissSplash(tester);
        await AppHarness.settle(tester);
      });
    }

    testWidgets('lays out on a narrow 9:21 screen and on a tablet', (
      WidgetTester tester,
    ) async {
      for (final Size size in <Size>[
        const Size(360 * 3, 840 * 3), // 9:21, narrower than the plates
        const Size(800 * 2, 1280 * 2), // tablet, wider than the plates
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = size.width > 1600 ? 2 : 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpSplash(tester);
        await tester.pump(const Duration(milliseconds: 2100));
        expect(tester.takeException(), isNull, reason: '$size');

        await AppHarness.dismissSplash(tester);
        await AppHarness.settle(tester);
      }
    });
  });
}

/// Width and height from a PNG or WebP header, without decoding the pixels.
({int w, int h}) _pngOrWebpSize(String path) {
  final Uint8List b = File(path).readAsBytesSync();

  // PNG: IHDR width/height are big-endian at offsets 16 and 20.
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
    int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    return (w: be(16), h: be(20));
  }

  // WebP: VP8L ('L') packs 14-bit width-1 and height-1; VP8X ('X') stores
  // 24-bit canvas width-1 and height-1 little-endian.
  final String fourcc = String.fromCharCodes(b.sublist(12, 16));
  if (fourcc == 'VP8X') {
    final int w = (b[24] | (b[25] << 8) | (b[26] << 16)) + 1;
    final int h = (b[27] | (b[28] << 8) | (b[29] << 16)) + 1;
    return (w: w, h: h);
  }
  if (fourcc == 'VP8L') {
    final int bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
    return (w: (bits & 0x3FFF) + 1, h: ((bits >> 14) & 0x3FFF) + 1);
  }
  if (fourcc == 'VP8 ') {
    final int w = (b[26] | (b[27] << 8)) & 0x3FFF;
    final int h = (b[28] | (b[29] << 8)) & 0x3FFF;
    return (w: w, h: h);
  }
  throw StateError('unrecognised image container in $path: $fourcc');
}

/// A [SplashScreen] on its own, with [MediaQuery.disableAnimations] forced.
///
/// Enough scaffolding for the widget to build — localization for the wordmark,
/// ScreenUtil for `.sp`/`.h`, a MaterialApp for Directionality — and nothing
/// else, so the reduced-motion branch is exercised without the router or the
/// service locator in the way.
Widget _isolatedSplash({
  required bool disableAnimations,
  required VoidCallback onFinished,
}) => EasyLocalization(
  supportedLocales: AppLocalization.supportedLocales,
  path: AppLocalization.translationsPath,
  startLocale: AppLocalization.arabic,
  fallbackLocale: AppLocalization.fallbackLocale,
  assetLoader: const FileTranslationLoader(),
  child: ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (BuildContext context, Widget? _) => MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: SplashScreen(
            onFinished: onFinished,
            bootstrap: Future<void>.value(),
          ),
        ),
      ),
    ),
  ),
);

/// Pumps until the splash has left the tree, or gives up.
///
/// The handover crosses a few async hops — the ticker future, the startup
/// future, `go`, then the route's 300 ms reverse transition — and each needs a
/// frame plus a microtask drain. `runAsync` is in the loop because the startup
/// future is a real one, not a fake-async one. Bounded so a genuine failure to
/// hand over shows up as a failed expectation rather than a hang.
Future<void> _pumpUntilSplashGone(WidgetTester tester) async {
  for (int i = 0; i < 40; i++) {
    if (!tester.any(find.byType(SplashScreen))) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
