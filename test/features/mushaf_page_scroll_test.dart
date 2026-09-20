import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
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

Future<void> pump(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
}) async {
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
            textScale: textScale,
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

  group('the reader\'s text size', () {
    double wordSize(WidgetTester tester) => tester
        .widget<AyahText>(
          find
              .byWidgetPredicate((Widget w) => w is AyahText && !w.isMarker)
              .first,
        )
        .fontSize;

    /// How many rows of text are on the page: the distinct heights its words
    /// sit at.
    int rowsOf(WidgetTester tester) => tester
        .widgetList<AyahText>(find.byType(AyahText))
        .map((AyahText w) => tester.getCenter(find.byWidget(w)).dy.round())
        .toSet()
        .length;

    testWidgets('larger: the text grows and the lines re-break, with every '
        'word kept and nothing overflowing', (WidgetTester tester) async {
      await pump(tester, const Size(390, 844));
      final double printed = wordSize(tester);
      expect(rowsOf(tester), 15);

      await pump(tester, const Size(390, 844), textScale: 1.5);
      expect(tester.takeException(), isNull);
      expect(wordSize(tester), closeTo(printed * 1.5, 0.01));
      // No printed line fits at one and a half times its size, so the page
      // has more rows than it has printed lines. (Whether it then scrolls
      // depends on the glass; the test font is small enough that here it
      // does not, and the wide-screen test above is what covers scrolling.)
      expect(rowsOf(tester), greaterThan(15));
      // Every word of the page is still on it.
      expect(
        find.byWidgetPredicate((Widget w) => w is AyahText && !w.isMarker),
        findsNWidgets(15 * 6),
      );
    });

    testWidgets('smaller: the printed lines are kept, only set smaller', (
      WidgetTester tester,
    ) async {
      await pump(tester, const Size(390, 844));
      final double printed = wordSize(tester);

      await pump(tester, const Size(390, 844), textScale: 0.75);
      expect(tester.takeException(), isNull);
      expect(wordSize(tester), closeTo(printed * 0.75, 0.01));
      expect(rowsOf(tester), 15);
    });

    testWidgets('at the largest size on a small phone it still lays out', (
      WidgetTester tester,
    ) async {
      await pump(tester, const Size(320, 568), textScale: 40 / 24);
      expect(tester.takeException(), isNull);
    });
  });
}
