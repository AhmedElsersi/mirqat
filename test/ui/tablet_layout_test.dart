import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/app_constants.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/features/home/widgets/juz_widgets.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/features/surah_list/widgets/surah_tile.dart';

import '../app_harness.dart';

/// The app runs on iPad. Every dimension in it is scaled from a design size,
/// and scaled from a *phone's* a 13-inch iPad came out nearly three times too
/// big everywhere but the text — and the ajzaa grid overflowed on every tile.
/// Found when the App Store screenshots were taken, which is a poor time to
/// find it; these walk the same screens at tablet sizes.
void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  const Map<String, Size> tablets = <String, Size>{
    'iPad Pro 13-inch': Size(1032, 1376),
    'iPad mini': Size(744, 1133),
    'iPad 11-inch, on its side': Size(1210, 834),
  };

  void useScreen(WidgetTester tester, Size size) {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final MapEntry<String, Size> tablet in tablets.entries) {
    testWidgets('${tablet.key}: scales from the tablet design, and nothing '
        'overflows', (WidgetTester tester) async {
      useScreen(tester, tablet.value);
      await harness.pumpApp(tester);
      expect(tester.takeException(), isNull);

      // About a third larger at most — not the 2.75 a phone's design gave.
      expect(ScreenUtil().scaleWidth, lessThan(1.7));
      expect(
        ScreenUtil().scaleWidth,
        closeTo(tablet.value.width / AppConstants.tabletDesignWidth, 0.01),
      );
      expect(find.byType(SurahRow), findsWidgets);

      await AppHarness.setHomeView(tester, HomeViewMode.grid);
      expect(find.byType(SurahTile), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'the surah grid');

      await AppHarness.swipeToAjzaa(tester);
      expect(find.byType(JuzTile), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'the ajzaa grid');

      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.settings_outlined),
      );
      expect(tester.takeException(), isNull, reason: 'settings');
    });
  }

  testWidgets('a reading page and its session sheet lay out on a tablet', (
    WidgetTester tester,
  ) async {
    useScreen(tester, tablets.values.first);
    await harness.pumpApp(tester);
    await AppHarness.openReading(tester, find.byType(SurahRow).first);
    expect(tester.takeException(), isNull);
    await AppHarness.showReadingBar(tester);
    await AppHarness.openSessionSheet(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone is still scaled from the phone design', (
    WidgetTester tester,
  ) async {
    useScreen(tester, const Size(440, 956));
    await harness.pumpApp(tester);
    expect(
      ScreenUtil().scaleWidth,
      closeTo(440 / AppConstants.designWidth, 0.01),
    );
  });
}
