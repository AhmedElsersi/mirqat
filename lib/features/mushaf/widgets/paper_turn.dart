import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Where the crease of a folding leaf lies, and how far the fold has come.
///
/// Pure arithmetic, separated out so a test can hold the geometry still
/// without pumping a pager.
class PaperTurnPose {
  const PaperTurnPose({
    required this.fold,
    required this.tilt,
    required this.spine,
    required this.turning,
    required this.hidden,
    required this.shade,
    required this.underShade,
  });

  /// Where the crease crosses the leaf's bottom edge, as a fraction of the
  /// leaf's width from its free edge. Zero is a page lying flat; it runs to
  /// [spine] as the turn lands, where the whole sheet has gone over.
  final double fold;

  /// The crease's lean from the vertical, in radians, its foot leading: a
  /// page is lifted by its bottom corner, so the crease starts slanted and
  /// stands upright as the fold reaches the binding.
  final double tilt;

  /// Where the binding is, as a fraction of the leaf's width from the free
  /// edge: the far edge of a page read alone, the centre of an open spread.
  final double spine;

  /// Whether this leaf is the one being folded. It paints the whole scene:
  /// the next leaf lying flat beneath it, and itself folding over the top.
  final bool turning;

  /// Whether this leaf is the one lying *beneath* a turn. Its face is painted
  /// by the leaf being folded off it, so the real element paints nothing —
  /// keeping its size and its state for the moment the turn lands on it.
  final bool hidden;

  /// How deep the crease's own shadow runs across the folded-over back of
  /// the sheet, 0..1 — the paper darkest where it bends.
  final double shade;

  /// How deep the shadow the raised fold throws on the page beneath runs,
  /// 0..1 — along the crease, where the sheet stands off the page.
  final double underShade;
}

/// Turns the pager's slide into a leaf of paper folding over the page beneath.
///
/// The pager itself is untouched: the same [PageController] still owns the
/// gesture, the keyboard and the session's own page turns. This only changes
/// what a turn *looks like*. The next page lies flat under the current one,
/// already whole. The current leaf is folded the way a hand folds a bound
/// page: a crease comes in from the lifted bottom corner, slanted at first and
/// standing upright as it travels, and the sheet beyond the crease is turned
/// over onto the part still lying flat — so what the reader sees over the
/// crease is the sheet's blank back, the paper darkest where it bends, with
/// its shadow thrown ahead of it. The page beneath appears behind the crease,
/// in the raised fold's shadow. The crease reaches the binding exactly as the
/// pager lands, where the page beneath simply *is* the page. A turn backward
/// is the same scene run in reverse: the fold comes back down over the page
/// it had uncovered.
///
/// Mid-turn, both pages must therefore be painted at once, stacked — and a
/// pager paints its later item over its earlier one, which is the wrong way
/// round for a leaf folding off its successor. So the leaf being folded
/// paints the whole scene by itself — [under] builds its successor's face,
/// drawn flat beneath its own folding child — while the successor's real
/// element hides, state kept, until the turn lands on it. One painter,
/// whatever the viewport's own paint order.
///
/// The binding does not move with the UI locale: a mushaf is bound on the
/// right, so the free edge the fold comes in from is the page's left edge,
/// and the crease travels right — the same way in Arabic and in English,
/// because the book itself is the same book (CLAUDE.md A.2 rule 4). On a desk
/// wide enough for a spread the binding is the centre fold, and the leaf
/// folds over onto the facing page.
///
/// One widget tree serves every frame of the turn, rest included. Handing
/// back a bare child at rest and a clipped one mid-turn would re-create the
/// page element at the start and end of every turn — its state gone and a
/// frame dropped exactly when the eye is on it — so the clip and the fold are
/// always there and simply read as the whole page while the leaf lies flat.
class PaperTurn extends StatefulWidget {
  const PaperTurn({
    required this.controller,
    required this.index,
    required this.spread,
    required this.child,
    this.under,
    super.key,
  });

  final PageController controller;

  /// This leaf's place in the pager.
  final int index;

  /// Whether the mushaf lies open at two facing pages.
  final bool spread;

  final Widget child;

  /// Builds the next leaf's face — what lies beneath this one while it is
  /// being folded. Null on the pager's last leaf, which has nothing under it
  /// and therefore nothing to fold off: an overscroll there stays a slide.
  final Widget Function()? under;

  /// How far the crease leans when the corner is first lifted, in radians.
  static const double corner = math.pi / 6;

  /// The leaf's pose when the pager has carried it [delta] pages from flat.
  ///
  /// A positive delta is this leaf being carried off: the crease comes in
  /// from the free edge and travels to the binding, the sheet beyond it
  /// folded over. A negative delta is this leaf lying beneath its
  /// predecessor's turn, where the predecessor paints its face; the real
  /// leaf hides.
  ///
  /// The crease runs through a smoothstep rather than linearly: paper lifts
  /// off and lands gently, and a fold that moved at the drag's own speed
  /// would snap at both ends.
  static PaperTurnPose poseFor(double delta, {required bool spread}) {
    final double d = delta.clamp(-1.0, 1.0);
    final double spine = spread ? 0.5 : 1.0;
    if (d == 0 || d.abs() >= 1) {
      return PaperTurnPose(
        fold: 0,
        tilt: 0,
        spine: spine,
        turning: false,
        hidden: false,
        shade: 0,
        underShade: 0,
      );
    }
    if (d < 0) {
      // Beneath a turn: flat, and painted by the leaf being folded off it.
      return PaperTurnPose(
        fold: 0,
        tilt: 0,
        spine: spine,
        turning: false,
        hidden: true,
        shade: 0,
        underShade: 0,
      );
    }
    final double progress = d * d * (3 - 2 * d);
    return PaperTurnPose(
      fold: progress * spine,
      // Lifted by its corner, the crease leans; it stands upright by the
      // time it reaches the binding, so the sheet lands square.
      tilt: corner * (1 - progress),
      spine: spine,
      turning: true,
      hidden: false,
      // The crease is in shadow from the first lift; the fold it raises
      // throws most shadow on the page beneath midway, when it stands
      // highest off it, and none once it has lain down over the binding.
      shade: 0.14 + 0.22 * math.sin(progress * math.pi / 2),
      underShade: 0.3 * math.sin(progress * math.pi),
    );
  }

  /// Where the crease crosses a leaf of [size] at height [y] from its top,
  /// in the leaf's own coordinates: the free edge at x = 0.
  static double creaseX(PaperTurnPose pose, Size size, double y) =>
      pose.fold * size.width - (size.height - y) * math.tan(pose.tilt);

  /// The part of [bounds] on one side of the crease, as a polygon: the sheet
  /// beyond the crease — [free] — which is folded over, or the part still
  /// lying flat. A rectangle cut by one line, so at most five corners.
  static Path sideOfCrease(
    PaperTurnPose pose,
    Size size,
    Rect bounds, {
    required bool free,
  }) {
    // Signed distance in x from the crease: negative is the free side.
    double f(Offset p) => p.dx - creaseX(pose, size, p.dy);
    bool keep(double v) => free ? v <= 0 : v >= 0;
    final List<Offset> corners = <Offset>[
      bounds.topLeft,
      bounds.topRight,
      bounds.bottomRight,
      bounds.bottomLeft,
    ];
    final List<Offset> kept = <Offset>[];
    for (int i = 0; i < corners.length; i++) {
      final Offset a = corners[i];
      final Offset b = corners[(i + 1) % corners.length];
      final double fa = f(a);
      final double fb = f(b);
      if (keep(fa)) kept.add(a);
      if (keep(fa) != keep(fb)) {
        final double t = fa / (fa - fb);
        kept.add(Offset.lerp(a, b, t)!);
      }
    }
    final Path path = Path();
    if (kept.isEmpty) return path;
    path.addPolygon(kept, true);
    return path;
  }

  /// The mirror across the crease: what carries the free side of the sheet
  /// over onto the flat side. Identity while the leaf lies flat.
  static Matrix4 foldMatrix(PaperTurnPose pose, Size size) {
    if (!pose.turning) return Matrix4.identity();
    final double bx = pose.fold * size.width;
    final double by = size.height;
    final double c = math.cos(2 * pose.tilt);
    final double s = math.sin(2 * pose.tilt);
    // A reflection across a line through (bx, by) leaning by the tilt.
    final double a = -c, b = s, cc = s, d = c;
    final double tx = bx - (a * bx + cc * by);
    final double ty = by - (b * bx + d * by);
    return Matrix4(a, b, 0, 0, cc, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1);
  }

  @override
  State<PaperTurn> createState() => _PaperTurnState();
}

class _PaperTurnState extends State<PaperTurn> {
  /// The successor's face, built once when a turn begins and handed back
  /// identical every frame after, so the page under the leaf is not re-built
  /// sixty times a second while the fold moves over it.
  Widget? _under;

  Widget _underFace() {
    if (widget.under == null) return const SizedBox.shrink();
    return _under ??= widget.under!();
  }

  @override
  Widget build(BuildContext context) {
    // The fold's shadows, in the theme's own ink — the same ink the fold
    // between two facing pages is drawn with.
    final Color ink = Theme.of(context).colorScheme.shadow;
    // The sheet itself. A mushaf page paints only its frame and its letters,
    // so without this the page beneath would show through the folded leaf;
    // paper is opaque, and the leaf carries its own.
    final Color paper = Theme.of(context).scaffoldBackgroundColor;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) => AnimatedBuilder(
        animation: widget.controller,
        builder: (BuildContext context, Widget? leaf) {
          final double page =
              widget.controller.hasClients &&
                  widget.controller.position.haveDimensions
              ? widget.controller.page ?? widget.index.toDouble()
              : widget.index.toDouble();
          double delta = page - widget.index;
          // The last leaf has nothing beneath it to be folded off, so an
          // overscroll bounce past the end stays the pager's own slide.
          if (delta > 0 && widget.under == null) delta = 0;
          // At rest, or far enough away that the pager has it offscreen,
          // everything below collapses to the whole page — but the tree stays.
          final bool resting = delta == 0 || delta.abs() >= 1;
          final PaperTurnPose pose = PaperTurn.poseFor(
            resting ? 0 : delta,
            spread: widget.spread,
          );
          final Size size = Size(box.maxWidth, box.maxHeight);
          // The first leaf has no predecessor to paint its face, so an
          // overscroll bounce at the front never blanks the page.
          final bool veiled = pose.hidden && widget.index > 0;
          if (!pose.turning) _under = null;

          return Transform.translate(
            // Cancels the pager's own slide, pinning the leaf in the viewport
            // so the turn happens in place. The pager's axis is LTR+reverse
            // (the next page lies to the left), under which a leaf is carried
            // `delta` page-widths to the right.
            offset: resting ? Offset.zero : Offset(-delta * box.maxWidth, 0),
            child: ClipRect(
              child: Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  // The next page, lying flat and whole beneath the folding
                  // leaf, in the raised fold's shadow along the crease. Built
                  // only mid-turn; its real element hides meanwhile.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: pose.turning
                          ? CustomPaint(
                              foregroundPainter: _UncoveredShadow(
                                pose: pose,
                                ink: ink,
                              ),
                              child: _underFace(),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  // The leaf, cut along the crease: only the part still lying
                  // flat is its printed face. Beneath a turn it shows nothing
                  // — but it keeps its size and its state, so the page a
                  // landing turn uncovers is the page that was already there.
                  Visibility(
                    visible: !veiled,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: ClipPath(
                      clipper: pose.turning
                          ? _CreaseClipper(pose: pose, free: false)
                          : null,
                      child: Stack(
                        fit: StackFit.passthrough,
                        children: <Widget>[
                          // The paper the page is printed on, under the
                          // print. Only while the leaf is being folded: at
                          // rest the page lies on the very background this
                          // would paint.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ColoredBox(
                                color: paper.withValues(
                                  alpha: pose.turning ? 1 : 0,
                                ),
                              ),
                            ),
                          ),
                          leaf!,
                        ],
                      ),
                    ),
                  ),
                  // The sheet beyond the crease, turned over onto the flat
                  // part: its blank back, darkest at the bend, with the
                  // shadow it throws ahead of its edge. Mirrored across the
                  // crease, which is exactly how a fold carries paper over.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Transform(
                        transform: PaperTurn.foldMatrix(pose, size),
                        child: CustomPaint(
                          painter: _FoldedBack(
                            pose: pose,
                            paper: paper,
                            ink: ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// The part of the leaf on one side of the crease.
class _CreaseClipper extends CustomClipper<Path> {
  const _CreaseClipper({required this.pose, required this.free});

  final PaperTurnPose pose;
  final bool free;

  @override
  Path getClip(Size size) =>
      PaperTurn.sideOfCrease(pose, size, Offset.zero & size, free: free);

  @override
  bool shouldReclip(_CreaseClipper old) =>
      old.pose.fold != pose.fold || old.pose.tilt != pose.tilt;
}

/// The shadow the raised fold throws on the page beneath, along the crease
/// and fading away from it into the uncovered page.
class _UncoveredShadow extends CustomPainter {
  const _UncoveredShadow({required this.pose, required this.ink});

  final PaperTurnPose pose;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (!pose.turning || pose.underShade <= 0) return;
    final Rect page = Offset.zero & size;
    canvas.save();
    canvas.clipPath(PaperTurn.sideOfCrease(pose, size, page, free: true));
    final Offset foot = Offset(pose.fold * size.width, size.height);
    // Into the free side, square to the crease.
    final Offset away = Offset(-math.cos(pose.tilt), math.sin(pose.tilt));
    final double reach = size.width * 0.28;
    canvas.drawRect(
      page,
      Paint()
        ..shader = ui.Gradient.linear(foot, foot + away * reach, <Color>[
          ink.withValues(alpha: pose.underShade),
          ink.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UncoveredShadow old) =>
      old.pose.fold != pose.fold ||
      old.pose.tilt != pose.tilt ||
      old.pose.underShade != pose.underShade;
}

/// The folded-over sheet, drawn in the mirror's frame: the free side of the
/// leaf as blank paper, the crease's shadow across it, and — just outside
/// the sheet's free edge, which the mirror lays on the flat page — the shadow
/// the fold's edge throws.
class _FoldedBack extends CustomPainter {
  const _FoldedBack({
    required this.pose,
    required this.paper,
    required this.ink,
  });

  final PaperTurnPose pose;
  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (!pose.turning) return;
    final Rect page = Offset.zero & size;
    final double cast = size.width * 0.12;
    final Rect wide = Rect.fromLTRB(-cast, 0, size.width, size.height);
    canvas.save();
    canvas.clipPath(PaperTurn.sideOfCrease(pose, size, wide, free: true));
    // The back of the sheet: paper, with a faint wash so it reads as the
    // unprinted side rather than a hole in the page.
    canvas.drawRect(page, Paint()..color = paper);
    canvas.drawRect(page, Paint()..color = ink.withValues(alpha: 0.04));
    // Darkest along the bend, lighter as the sheet flattens out again.
    final Offset foot = Offset(pose.fold * size.width, size.height);
    final Offset away = Offset(-math.cos(pose.tilt), math.sin(pose.tilt));
    canvas.drawRect(
      page,
      Paint()
        ..shader = ui.Gradient.linear(
          foot,
          foot + away * (size.width * 0.4),
          <Color>[
            ink.withValues(alpha: pose.shade),
            ink.withValues(alpha: pose.shade * 0.2),
            ink.withValues(alpha: 0),
          ],
          <double>[0, 0.4, 1],
        ),
    );
    // Ahead of the sheet's edge, on the page it lies over: its shadow.
    canvas.drawRect(
      Rect.fromLTRB(-cast, 0, 0, size.height),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(-cast, 0), <Color>[
          ink.withValues(alpha: 0.3),
          ink.withValues(alpha: 0),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoldedBack old) =>
      old.pose.fold != pose.fold ||
      old.pose.tilt != pose.tilt ||
      old.pose.shade != pose.shade;
}
