import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/features/mushaf/widgets/paper_turn.dart';

/// The paper turn: the next page lying flat beneath the current one, and the
/// current leaf folding over the spine across the whole drag — edge-on only
/// as it lands. The geometry is tested as arithmetic; the widget is tested
/// inside the same kind of pager the mushaf uses — LTR axis, reversed.
void main() {
  group('the pose', () {
    test('a page at rest lies flat, neither turning nor beneath a turn', () {
      final PaperTurnPose pose = PaperTurn.poseFor(0, spread: false);
      expect(pose.angle, 0);
      expect(pose.turning, isFalse);
      expect(pose.hidden, isFalse);
      expect(pose.shade, 0);
      expect(pose.underShade, 0);
    });

    test('the lift-off is gentle: near flat the angle grows slower than '
        'the drag', () {
      // Smoothstep: at a twentieth of the turn the fold is well under a
      // twentieth of the way to edge-on.
      final double early = PaperTurn.poseFor(0.05, spread: false).angle.abs();
      expect(early, lessThan(0.05 * math.pi / 2));
    });

    test('the leaf is tied to the hand through the whole turn: halfway it is '
        'half folded, and edge-on comes only as the turn lands', () {
      // Symmetric easing passes through its own middle: half the drag is
      // half the fold.
      expect(
        PaperTurn.poseFor(0.5, spread: false).angle,
        closeTo(-math.pi / 4, 1e-9),
      );
      // Deep into the drag the leaf still shows its face…
      final double late = PaperTurn.poseFor(0.9, spread: false).angle.abs();
      expect(late, lessThan(math.pi / 2));
      // …and reaches edge-on only at the very end, where the pager lands and
      // the page beneath simply is the page.
      expect(
        PaperTurn.poseFor(0.999, spread: false).angle,
        closeTo(-math.pi / 2, 0.01),
      );
      expect(PaperTurn.poseFor(1.0, spread: false).angle, 0);
      expect(PaperTurn.poseFor(1.0, spread: false).turning, isFalse);
    });

    test('a positive delta is the leaf being lifted, about the spine — the '
        'right edge, where a mushaf is bound', () {
      final PaperTurnPose pose = PaperTurn.poseFor(0.25, spread: false);
      expect(pose.turning, isTrue);
      expect(pose.hidden, isFalse);
      expect(pose.hinge, Alignment.centerRight);
      expect(pose.angle, lessThan(0));
    });

    test('a negative delta is the leaf lying beneath a turn: flat, and '
        'painted by the leaf being lifted off it', () {
      for (final double delta in <double>[-0.1, -0.5, -0.9]) {
        final PaperTurnPose pose = PaperTurn.poseFor(delta, spread: false);
        expect(pose.hidden, isTrue, reason: '$delta');
        expect(pose.turning, isFalse, reason: '$delta');
        expect(pose.angle, 0, reason: '$delta');
      }
    });

    test('an open spread turns about the centre spine', () {
      expect(PaperTurn.poseFor(0.25, spread: true).hinge, Alignment.center);
    });

    test('the lifted leaf falls deeper into shadow as it rises; the page '
        'beneath comes out of it', () {
      final PaperTurnPose early = PaperTurn.poseFor(0.1, spread: false);
      final PaperTurnPose late = PaperTurn.poseFor(0.8, spread: false);
      expect(early.shade, greaterThan(0));
      expect(late.shade, greaterThan(early.shade));
      expect(late.shade, lessThan(1));
      expect(early.underShade, greaterThan(0));
      expect(late.underShade, lessThan(early.underShade));
    });
  });

  group('the widget', () {
    const int count = 3;
    Widget pager(PageController controller) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.ltr,
        child: PageView.builder(
          controller: controller,
          reverse: true,
          itemCount: count,
          itemBuilder: (BuildContext context, int index) => PaperTurn(
            controller: controller,
            index: index,
            spread: false,
            under: index + 1 < count ? () => Text('page ${index + 1}') : null,
            child: Text('page $index'),
          ),
        ),
      ),
    );

    // One tree serves every frame — the Transform and the Visibility are
    // always there, reading as identity at rest — so the probes read their
    // *values*: whether any Transform inside the leaf actually rotates (a
    // rotated Y axis puts cos θ, not 1, at the matrix's first entry), and
    // whether the leaf's own Visibility is open. A leaf is found by its
    // index, because mid-turn its subtree also holds its successor's face.
    Finder leaf(int index) => find.byWidgetPredicate(
      (Widget w) => w is PaperTurn && w.index == index,
    );
    bool folded(WidgetTester tester, int index) => tester
        .widgetList<Transform>(
          find.descendant(of: leaf(index), matching: find.byType(Transform)),
        )
        .any((Transform t) => t.transform.storage[0] < 0.999);
    bool shown(WidgetTester tester, int index) => tester
        .widget<Visibility>(
          find.descendant(of: leaf(index), matching: find.byType(Visibility)),
        )
        .visible;
    Finder underFace(int index, String text) =>
        find.descendant(of: leaf(index), matching: find.text(text));

    testWidgets('at rest the leaf lies flat, shown, in the same tree a turn '
        'uses — so starting a turn re-creates nothing, and no successor face '
        'is built', (WidgetTester tester) async {
      final PageController controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(pager(controller));

      expect(folded(tester, 0), isFalse);
      expect(shown(tester, 0), isTrue);
      expect(find.text('page 1'), findsNothing);
    });

    testWidgets('mid-turn the lifted leaf folds on top while the next page '
        'lies flat and whole beneath it, to the very end of the drag', (
      WidgetTester tester,
    ) async {
      final PageController controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(pager(controller));
      final double width = tester.getSize(find.byType(PageView)).width;

      // A quarter of the way: leaf 0 is folding, still shown — and inside
      // its own subtree lies page 1's face, flat beneath it. The real leaf 1
      // is there but veiled, its state kept for when the turn lands.
      controller.jumpTo(width * 0.25);
      await tester.pump();
      expect(folded(tester, 0), isTrue);
      expect(shown(tester, 0), isTrue);
      expect(underFace(0, 'page 1'), findsOneWidget);
      expect(shown(tester, 1), isFalse);

      // Deep into the drag the leaf is still in hand, still folding — it has
      // not switched halfway, as a two-half flip would.
      controller.jumpTo(width * 0.85);
      await tester.pump();
      expect(folded(tester, 0), isTrue);
      expect(shown(tester, 0), isTrue);
      expect(underFace(0, 'page 1'), findsOneWidget);
      expect(shown(tester, 1), isFalse);

      // Landed: the page that lay beneath is the page, flat and unrotated,
      // and no successor face is built at rest.
      controller.jumpTo(width);
      await tester.pump();
      expect(folded(tester, 1), isFalse);
      expect(shown(tester, 1), isTrue);
      expect(underFace(1, 'page 2'), findsNothing);
    });

    testWidgets('a turn backward is the same scene reversed: the leaf comes '
        'back down over the page it had uncovered', (
      WidgetTester tester,
    ) async {
      final PageController controller = PageController(initialPage: 1);
      addTearDown(controller.dispose);
      await tester.pumpWidget(pager(controller));
      final double width = tester.getSize(find.byType(PageView)).width;

      // Partway back from page 1 to page 0: leaf 0 is the one in hand,
      // folding down onto page 1, which lies flat beneath it.
      controller.jumpTo(width * 0.6);
      await tester.pump();
      expect(folded(tester, 0), isTrue);
      expect(shown(tester, 0), isTrue);
      expect(underFace(0, 'page 1'), findsOneWidget);
      expect(shown(tester, 1), isFalse);

      // Landed home: leaf 0 lies flat again.
      controller.jumpTo(0);
      await tester.pump();
      expect(folded(tester, 0), isFalse);
      expect(shown(tester, 0), isTrue);
    });
  });
}
