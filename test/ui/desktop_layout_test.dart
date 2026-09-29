/// The app in a window on a desk (core/desktop.dart): nothing scaled, the
/// mushaf page held to a printed page's width and centred, the lists to a
/// column, and the keyboard turning pages.
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
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';

import '../app_harness.dart';

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  testWidgets('a desktop window: the lists a column, the page a printed '
      'page wide and centred, the arrows turning pages', (
    WidgetTester tester,
  ) async {
    // Put back before the body ends: the framework checks its debug
    // variables there, ahead of any tearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(isDesktop, isTrue);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await harness.pumpApp(tester);
    expect(tester.takeException(), isNull);
    final Rect tabs = tester.getRect(find.byType(TabBarView));
    expect(tabs.width, lessThanOrEqualTo(kDesktopContentWidth));
    expect(
      (tabs.left - (1400 - tabs.right)).abs(),
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
    expect((page.left - (1400 - page.right)).abs(), lessThan(2));

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
    debugDefaultTargetPlatformOverride = null;
  });
}
