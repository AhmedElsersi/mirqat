/// The app in a window on a desk (core/desktop.dart): nothing scaled, the
/// mushaf page held to a printed page's width and centred, the lists to a
/// column, and the keyboard turning pages — and, in a window wide enough for
/// it, two pages facing each other the way a printed mushaf lies open.
///
/// Pumped as Windows through `debugDefaultTargetPlatformOverride`, which is
/// what `isDesktop` reads — so the same test on a Mac still lays the phone
/// out as a phone, and this one lays the desk out as a desk.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/desktop.dart';
import 'package:mirqat/features/home/widgets/juz_widgets.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_fold.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';

import '../app_harness.dart';

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  testWidgets('a narrow desktop window: the lists a column, one page a '
      'printed page wide and centred, the arrows turning it', (
    WidgetTester tester,
  ) async {
    // Put back before the body ends: the framework checks its debug
    // variables there, ahead of any tearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(isDesktop, isTrue);
    // Under the width a spread needs, so this is the one-page layout.
    tester.view.physicalSize = const Size(960, 900);
    expect(spreadFits(960), isFalse);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await harness.pumpApp(tester);
    expect(tester.takeException(), isNull);
    final Rect tabs = tester.getRect(find.byType(TabBarView));
    expect(tabs.width, lessThanOrEqualTo(kDesktopContentWidth));
    expect(
      (tabs.left - (960 - tabs.right)).abs(),
      lessThan(2),
      reason: 'centred',
    );

    await AppHarness.swipeToAjzaa(tester);
    final MushafCubit cubit = await AppHarness.openReading(
      tester,
      find.byType(JuzRow).first,
    );
    expect(tester.takeException(), isNull);
    final Rect page = tester.getRect(find.byType(MushafPageView).first);
    expect(page.width, lessThanOrEqualTo(kDesktopPageWidth));
    expect(page.width, greaterThan(kDesktopPageWidth - 2));
    expect((page.left - (960 - page.right)).abs(), lessThan(2));

    final int before = cubit.state.currentPage;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await AppHarness.frames(tester, 600);
    expect(cubit.state.currentPage, before + 1, reason: 'left = next page');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await AppHarness.frames(tester, 600);
    expect(cubit.state.currentPage, before, reason: 'right = previous page');

    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await AppHarness.frames(tester, 600);
    expect(cubit.state.currentPage, before + 1);
    expect(tester.takeException(), isNull);
    // The turns above left reads in flight under the fake clock; they are let
    // finish here, or they hold the database against the next test.
    await AppHarness.settleReads(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a wide desktop window: two pages facing each other, the '
      'earlier one on the right, and a key turning the leaf', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    expect(spreadFits(1400), isTrue);

    await harness.pumpApp(tester);
    await AppHarness.swipeToAjzaa(tester);
    final MushafCubit cubit = await AppHarness.openReading(
      tester,
      find.byType(JuzRow).first,
    );
    // The facing page is warmed beside the one being read; it is built from
    // the database, so it is waited for rather than assumed.
    await tester.runAsync(() async {
      for (int i = 0; i < 500; i++) {
        if (cubit.state.pages.containsKey(cubit.state.currentPage + 1)) break;
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await AppHarness.frames(tester);
    expect(tester.takeException(), isNull);

    final List<MushafPageView> open = tester
        .widgetList<MushafPageView>(find.byType(MushafPageView))
        .toList();
    expect(open.length, 2, reason: 'two pages lie open');
    expect(open.map((MushafPageView p) => p.page.number), <int>[
      cubit.state.currentPage,
      cubit.state.currentPage + 1,
    ]);

    final Rect right = tester.getRect(find.byType(MushafPageView).first);
    final Rect left = tester.getRect(find.byType(MushafPageView).last);
    expect(
      right.left,
      greaterThan(left.right - 1),
      reason: 'the earlier page is the right-hand one, as a mushaf is bound',
    );
    expect(right.width, lessThanOrEqualTo(kDesktopPageWidth));
    expect(left.width, lessThanOrEqualTo(kDesktopPageWidth));
    expect((right.width - left.width).abs(), lessThan(2));
    expect(
      (left.left - (1400 - right.right)).abs(),
      lessThan(2),
      reason: 'the open spread is centred in the window',
    );
    expect(find.byType(MushafFold), findsOneWidget);

    // One key turns the whole leaf: both pages, as a hand does.
    final int before = cubit.state.currentPage;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await AppHarness.frames(tester, 600);
    expect(cubit.state.currentPage, before + 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await AppHarness.frames(tester, 600);
    expect(cubit.state.currentPage, before);
    expect(tester.takeException(), isNull);
    await AppHarness.settleReads(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
