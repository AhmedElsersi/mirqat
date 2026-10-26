import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/features/mushaf/widgets/paper_turn.dart';

/// The paper turn: the next page lying flat beneath the current one, and the
/// current leaf folded over it along a crease that comes in from the lifted
/// corner and reaches the binding as the turn lands. The geometry is tested
/// as arithmetic; the widget is tested inside the same kind of pager the
/// mushaf uses — LTR axis, reversed.
void main() {
  group('the pose', () {
    test('a page at rest lies flat, neither turning nor beneath a turn', () {
      final PaperTurnPose pose = PaperTurn.poseFor(0, spread: false);
      expect(pose.fold, 0);
      expect(pose.tilt, 0);
      expect(pose.turning, isFalse);
      expect(pose.hidden, isFalse);
      expect(pose.shade, 0);
      expect(pose.underShade, 0);
    });

    test('the lift-off is gentle: near flat the crease moves slower than '
        'the drag', () {
      // Smoothstep: at a twentieth of the turn the crease is well under a
      // twentieth of the way to the binding.
      expect(PaperTurn.poseFor(0.05, spread: false).fold, lessThan(0.05));
    });

    test('the crease comes in from the free edge and reaches the binding '
        'only as the pager lands, standing upright by then', () {
      // Symmetric easing passes through its own middle.
      expect(PaperTurn.poseFor(0.5, spread: false).fold, closeTo(0.5, 1e-9));
      final PaperTurnPose late = PaperTurn.poseFor(0.999, spread: false);
      expect(late.fold, closeTo(1, 0.01));
      expect(late.tilt, closeTo(0, 0.01));
      expect(PaperTurn.poseFor(1.0, spread: false).fold, 0);
      expect(PaperTurn.poseFor(1.0, spread: false).turning, isFalse);
    });

    test('lifted by its corner, the crease leans at first and stands up as '
        'it travels', () {
      final double early = PaperTurn.poseFor(0.1, spread: false).tilt;
      final double mid = PaperTurn.poseFor(0.5, spread: false).tilt;
      final double late = PaperTurn.poseFor(0.9, spread: false).tilt;
      expect(early, greaterThan(0));
      expect(early, lessThanOrEqualTo(PaperTurn.corner));
      expect(mid, lessThan(early));
      expect(late, lessThan(mid));
    });

    test('on a spread the binding is the centre fold, and the crease stops '
        'there', () {
      expect(PaperTurn.poseFor(0.25, spread: true).spine, 0.5);
      expect(PaperTurn.poseFor(0.999, spread: true).fold, closeTo(0.5, 0.01));
      expect(PaperTurn.poseFor(0.25, spread: false).spine, 1);
    });

    test('a positive delta is the leaf being folded', () {
      final PaperTurnPose pose = PaperTurn.poseFor(0.25, spread: false);
      expect(pose.turning, isTrue);
      expect(pose.hidden, isFalse);
      expect(pose.fold, greaterThan(0));
    });

    test('a negative delta is the leaf lying beneath a turn: flat, and '
        'painted by the leaf being folded off it', () {
      for (final double delta in <double>[-0.1, -0.5, -0.9]) {
        final PaperTurnPose pose = PaperTurn.poseFor(delta, spread: false);
        expect(pose.hidden, isTrue, reason: '$delta');
        expect(pose.turning, isFalse, reason: '$delta');
        expect(pose.fold, 0, reason: '$delta');
      }
    });

    test('the crease is in shadow from the first lift; the fold throws its '
        'shadow on the page beneath most midway, and none once it has lain '
        'down', () {
      final PaperTurnPose early = PaperTurn.poseFor(0.1, spread: false);
      final PaperTurnPose mid = PaperTurn.poseFor(0.5, spread: false);
      final PaperTurnPose late = PaperTurn.poseFor(0.999, spread: false);
      expect(early.shade, greaterThan(0));
      expect(late.shade, greaterThan(early.shade));
      expect(late.shade, lessThan(1));
      expect(early.underShade, greaterThan(0));
      expect(mid.underShade, greaterThan(early.underShade));
      expect(late.underShade, lessThan(mid.underShade));
    });
  });

  group('the geometry', () {
    const Size size = Size(100, 160);

    test('at rest the crease lies on the free edge, so the flat side is the '
        'whole page and nothing is folded over', () {
      final PaperTurnPose rest = PaperTurn.poseFor(0, spread: false);
      final Rect page = Offset.zero & size;
      expect(
        PaperTurn.sideOfCrease(rest, size, page, free: false).getBounds(),
        page,
      );
      expect(
        PaperTurn.sideOfCrease(rest, size, page, free: true).getBounds().width,
        0,
      );
      expect(PaperTurn.foldMatrix(rest, size), Matrix4.identity());
    });

    test('the crease leans with its foot ahead: it crosses the bottom edge '
        'further from the free edge than the top', () {
      final PaperTurnPose pose = PaperTurn.poseFor(0.5, spread: false);
      final double foot = PaperTurn.creaseX(pose, size, size.height);
      final double head = PaperTurn.creaseX(pose, size, 0);
      expect(foot, closeTo(50, 1e-9));
      expect(head, lessThan(foot));
    });

    test('the mirror carries the free edge over the crease, onto the page: '
        'the foot of the free edge lands twice the fold away from it', () {
      final PaperTurnPose pose = PaperTurn.poseFor(0.999, spread: false);
      // Upright by now, so the mirror is a plain reflection in x.
      final Matrix4 m = PaperTurn.foldMatrix(pose, size);
      final Offset landed = MatrixUtils.transformPoint(
        m,
        Offset(0, size.height),
      );
      expect(landed.dx, closeTo(2 * pose.fold * size.width, 0.5));
      expect(landed.dy, closeTo(size.height, 0.5));
      // A point on the crease stays where it is.
      final Offset foot = Offset(pose.fold * size.width, size.height);
      final Offset still = MatrixUtils.transformPoint(m, foot);
      expect(still.dx, closeTo(foot.dx, 1e-6));
      expect(still.dy, closeTo(foot.dy, 1e-6));
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
