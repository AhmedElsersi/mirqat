import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/islamic_frame.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';

/// Fifteen lines of a few words each — the shape of a full mushaf page.
MushafPage fullPage() => MushafPage(
  number: 3,
  lines: <PageLine>[
    for (int line = 1; line <= 15; line++)
      AyahLine(
        centered: false,
        words: <Word>[
          for (int w = 0; w < 6; w++)
            Word(
              id: line * 10 + w,
              surahNumber: 2,
              ayahNumber: line,
              position: w + 1,
              text: 'كلمة',
              isMarker: false,
              page: 3,
              line: line,
            ),
        ],
      ),
  ],
);

Future<void> pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        home: Scaffold(
          body: MushafPageView(
            page: fullPage(),
            linesPerFullPage: 15,
            highlighted: null,
            selected: null,
            onWordLongPress: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The width alone sizes the text; the height never squeezes it. A page that
/// is taller than the glass scrolls, frame and all.
void main() {
  testWidgets('a tall phone shows the whole page, with nothing to scroll', (
    WidgetTester tester,
  ) async {
    await pump(tester, const Size(412, 915));
    expect(tester.takeException(), isNull);
    expect(find.byType(IslamicFrame), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('a wide, short screen scrolls the page instead of shrinking it', (
    WidgetTester tester,
  ) async {
    await pump(tester, const Size(915, 412));
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    // The frame is inside what scrolls: the page moves as one object.
    expect(
      find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(IslamicFrame),
      ),
      findsOneWidget,
    );
    // And it is genuinely taller than the screen.
    expect(tester.getSize(find.byType(IslamicFrame)).height, greaterThan(412));
  });

  testWidgets('the text is larger on the wide screen, not smaller', (
    WidgetTester tester,
  ) async {
    // The point of scrolling: width buys size, and height no longer takes it
    // back. Before, a short screen squeezed fifteen lines into its height and
    // the text shrank to fit.
    double fontSize() => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((RichText t) => t.text.style?.fontSize ?? 0)
        .reduce((double a, double b) => a > b ? a : b);

    await pump(tester, const Size(412, 915));
    final double onTallPhone = fontSize();
    await pump(tester, const Size(915, 412));
    final double onWideScreen = fontSize();

    expect(onTallPhone, greaterThan(0));
    expect(onWideScreen, greaterThan(onTallPhone * 1.5));
  });
}
