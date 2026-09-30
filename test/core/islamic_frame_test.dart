import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/islamic_frame.dart';

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(400, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('IslamicFrame', () {
    testWidgets('never overlaps what it frames', (WidgetTester tester) async {
      // CLAUDE.md A.2 rule 7: nothing is laid over Quranic text. The ornament
      // is a border, and the text lives strictly inside its inner rule.
      const Key inside = Key('inside');
      await pump(
        tester,
        const SizedBox(
          width: 360,
          height: 640,
          child: IslamicFrame(child: SizedBox.expand(key: inside)),
        ),
      );

      final Rect frame = tester.getRect(find.byType(IslamicFrame));
      final Rect child = tester.getRect(find.byKey(inside));
      final double band = IslamicFrame.bandFor(360);

      expect(child.left, greaterThan(frame.left + band));
      expect(child.top, greaterThan(frame.top + band));
      expect(child.right, lessThan(frame.right - band));
      expect(child.bottom, lessThan(frame.bottom - band));
    });

    testWidgets('a bookmark ribbon hangs on the band, never over the page', (
      WidgetTester tester,
    ) async {
      const Key inside = Key('inside');
      await pump(
        tester,
        const SizedBox(
          width: 360,
          height: 640,
          child: IslamicFrame(
            bookmark: true,
            child: SizedBox.expand(key: inside),
          ),
        ),
      );
      final Rect child = tester.getRect(find.byKey(inside));
      final Iterable<Rect> ribbon = tester
          .widgetList(find.byIcon(Icons.bookmark))
          .map((Widget w) => tester.getRect(find.byWidget(w)));
      expect(ribbon, isNotEmpty);
      for (final Rect r in ribbon) {
        expect(r.overlaps(child), isFalse);
      }

      await pump(
        tester,
        const SizedBox(
          width: 360,
          height: 640,
          child: IslamicFrame(child: SizedBox.expand(key: inside)),
        ),
      );
      expect(find.byIcon(Icons.bookmark), findsNothing);
    });

    test('the band has presence, and still leaves the page to the text', () {
      // Wide enough for the woven lattice and its guard stripes to read; the
      // owner asked for that after seeing a band half this width. It grows
      // with the page, but only so far.
      expect(IslamicFrame.bandFor(200), 18);
      expect(IslamicFrame.bandFor(400), 22);
      expect(IslamicFrame.bandFor(1200), 30);
      for (final double width in <double>[320, 360, 412, 768, 1024]) {
        final double taken = IslamicFrame.insetsFor(width).horizontal;
        expect(taken / width, lessThan(0.18), reason: 'at $width wide');
      }
    });

    test('the text starts clear of the band, not against it', () {
      for (final double width in <double>[320, 412, 1024]) {
        expect(
          IslamicFrame.insetsFor(width).left,
          greaterThan(IslamicFrame.bandFor(width) * 1.3),
        );
      }
    });

    testWidgets(
      'paints without error at sizes from a small phone to a tablet',
      (WidgetTester tester) async {
        for (final Size size in const <Size>[
          Size(320, 480),
          Size(412, 915),
          Size(1024, 1366),
        ]) {
          await pump(
            tester,
            SizedBox.fromSize(
              size: size * 0.9,
              child: const IslamicFrame(child: SizedBox.expand()),
            ),
            size: size,
          );
          expect(tester.takeException(), isNull, reason: '$size');
        }
      },
    );
  });

  group('SurahCartouche', () {
    testWidgets('shows the name whole: a long one shrinks, it is never cut', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        const SizedBox(
          width: 220,
          child: SurahCartouche(
            name: 'آل عمران — اسم طويل جدا للاختبار',
            height: 40,
          ),
        ),
      );

      final Text text = tester.widget<Text>(find.byType(Text));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, 1);
      // Scaled down to fit, inside the panel, with no overflow reported.
      expect(find.byType(FittedBox), findsOneWidget);
      expect(tester.takeException(), isNull);
      final Rect panel = tester.getRect(find.byType(SurahCartouche));
      final Rect label = tester.getRect(find.byType(Text));
      expect(label.width, lessThanOrEqualTo(panel.width));
    });

    testWidgets('keeps the height it is given', (WidgetTester tester) async {
      await pump(
        tester,
        const SizedBox(
          width: 300,
          child: SurahCartouche(name: 'الفاتحة', height: 48),
        ),
      );
      expect(tester.getSize(find.byType(SurahCartouche)).height, 48);
    });
  });
}
