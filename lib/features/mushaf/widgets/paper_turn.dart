import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The hinge a turning leaf folds around, and how far it has folded.
///
/// Pure arithmetic, separated out so a test can hold the geometry still
/// without pumping a pager.
class PaperTurnPose {
  const PaperTurnPose({
    required this.angle,
    required this.hinge,
    required this.turning,
    required this.hidden,
    required this.shade,
    required this.underShade,
  });

  /// Radians about the vertical hinge axis. Zero is a page lying flat. The
  /// leaf folds through the **whole** scroll — edge-on, −π/2, is reached only
  /// as the turn lands, the way a real page stays in hand until it is over
  /// the spine and only then is let go.
  final double angle;

  /// Where the hinge is: the spine. To the right of the page in a window —
  /// a mushaf is bound on the right — and the centre fold on a spread.
  final Alignment hinge;

  /// Whether this leaf is the one being lifted. It paints the whole scene:
  /// the next leaf lying flat beneath it, and itself folding over the top.
  final bool turning;

  /// Whether this leaf is the one lying *beneath* a turn. Its face is painted
  /// by the leaf being lifted off it, so the real element paints nothing —
  /// keeping its size and its state for the moment the turn lands on it.
  final bool hidden;

  /// How deep the lifted leaf's own shadow runs, 0..1 — gathered along its
  /// free edge, which is rising away from the light.
  final double shade;

  /// How deep the shadow lying across the page beneath runs, 0..1 — hugging
  /// the spine, where the lifted leaf still hangs over it, and melting away
  /// as the leaf rises off the page.
  final double underShade;
}

/// Turns the pager's slide into a leaf of paper lifting off the page beneath.
///
/// The pager itself is untouched: the same [PageController] still owns the
/// gesture, the keyboard and the session's own page turns. This only changes
/// what a turn *looks like*: the next page lies flat under the current one,
/// already whole, and the current leaf folds over the spine across the full
/// drag — tied to the hand to the very end, and only there edge-on, where the
/// pager lands and the page beneath simply *is* the page. A turn backward is
/// the same scene run in reverse: the leaf comes back down over the page it
/// had uncovered.
///
/// Mid-turn, both pages must therefore be painted at once, stacked — and a
/// pager paints its later item over its earlier one, which is the wrong way
/// round for a leaf lifting off its successor. So the leaf being lifted
/// paints the whole scene by itself — [under] builds its successor's face,
/// drawn flat beneath its own folding child — while the successor's real
/// element hides, state kept, until the turn lands on it. One painter,
/// whatever the viewport's own paint order.
///
/// The hinge is the spine, and it does not move with the UI locale: a mushaf
/// is bound on the right, so in a window the leaf turns about the page's
/// right edge, and on a desk wide enough for a spread about the centre fold —
/// the same way in Arabic and in English, because the book itself is the same
/// book (CLAUDE.md A.2 rule 4).
///
/// One widget tree serves every frame of the turn, rest included. Handing
/// back a bare child at rest and a transformed one mid-turn would re-create
/// the page element at the start and end of every turn — its state gone and a
/// frame dropped exactly when the eye is on it — so the transforms are always
/// there and simply read as identity while the leaf lies flat.
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
  /// being lifted. Null on the pager's last leaf, which has nothing under it
  /// and therefore nothing to lift off: an overscroll there stays a slide.
  final Widget Function()? under;

  /// The leaf's pose when the pager has carried it [delta] pages from flat.
  ///
  /// The hinge is the spine, and a mushaf's spine lies to the **right** of
  /// the page being read, whatever the UI locale (CLAUDE.md A.2 rule 4) — on
  /// a spread it is the centre fold. A positive delta is this leaf being
  /// carried off: it folds about the spine, free edge swinging up toward the
  /// reader, the way a hand lifts a mushaf's page over its binding. A
  /// negative delta is this leaf lying beneath its predecessor's turn, where
  /// the predecessor paints its face; the real leaf hides.
  ///
  /// The angle runs through a smoothstep rather than linearly: paper lifts
  /// off and lands gently, and the angular motion is slowest exactly where
  /// the projection changes fastest — near edge-on — which is where a linear
  /// flip looks most like a snapping card.
  static PaperTurnPose poseFor(double delta, {required bool spread}) {
    final double d = delta.clamp(-1.0, 1.0);
    final Alignment hinge = spread ? Alignment.center : Alignment.centerRight;
    if (d == 0 || d.abs() >= 1) {
      return PaperTurnPose(
        angle: 0,
        hinge: hinge,
        turning: false,
        hidden: false,
        shade: 0,
        underShade: 0,
      );
    }
    if (d < 0) {
      // Beneath a turn: flat, and painted by the leaf being lifted off it.
      return PaperTurnPose(
        angle: 0,
        hinge: hinge,
        turning: false,
        hidden: true,
        shade: 0,
        underShade: 0,
      );
    }
    final double progress = d * d * (3 - 2 * d);
    return PaperTurnPose(
      angle: -progress * math.pi / 2,
      hinge: hinge,
      turning: true,
      hidden: false,
      // The lifted leaf loses the light as it rises; the page beneath gains
      // it, its shadow deepest while the leaf still lies close over it.
      shade: 0.32 * math.sin(progress * math.pi / 2),
      underShade: 0.26 * math.cos(progress * math.pi / 2),
    );
  }

  @override
  State<PaperTurn> createState() => _PaperTurnState();
}

class _PaperTurnState extends State<PaperTurn> {
  /// The successor's face, built once when a turn begins and handed back
  /// identical every frame after, so the page under the leaf is not re-built
  /// sixty times a second while the leaf moves over it.
  Widget? _under;

  Widget _underFace() {
    if (widget.under == null) return const SizedBox.shrink();
    return _under ??= widget.under!();
  }

  @override
  Widget build(BuildContext context) {
    // The turning leaf's shadow, in the theme's own ink — the same ink the
    // fold between two facing pages is drawn with.
    final Color ink = Theme.of(context).colorScheme.shadow;
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
          // The last leaf has nothing beneath it to be lifted off, so an
          // overscroll bounce past the end stays the pager's own slide.
          if (delta > 0 && widget.under == null) delta = 0;
          // At rest, or far enough away that the pager has it offscreen,
          // everything below collapses to identity — but the tree stays.
          final bool resting = delta == 0 || delta.abs() >= 1;
          final PaperTurnPose pose = PaperTurn.poseFor(
            resting ? 0 : delta,
            spread: widget.spread,
          );
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
            child: Stack(
              fit: StackFit.passthrough,
              children: <Widget>[
                // The next page, lying flat and whole beneath the lifted
                // leaf, in shadow near the spine where the leaf hangs over
                // it. Built only mid-turn; its real element hides meanwhile.
                Positioned.fill(
                  child: IgnorePointer(
                    child: pose.turning
                        ? Stack(
                            fit: StackFit.passthrough,
                            children: <Widget>[
                              _underFace(),
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: _underShadow(
                                      ink,
                                      pose.underShade,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                Transform(
                  alignment: pose.hinge,
                  transform: Matrix4.identity()
                    // A touch of perspective, or the fold reads as a squeeze.
                    ..setEntry(3, 2, 0.0012)
                    ..rotateY(pose.angle),
                  // Beneath a turn, the leaf shows nothing — but it keeps its
                  // size and its state, so the page a landing turn uncovers
                  // is the page that was already there.
                  child: Visibility(
                    visible: !veiled,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: <Widget>[
                        leaf!,
                        // The lifted leaf falls into its own shadow, gathered
                        // along the free edge rising away from the light.
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerRight,
                                  end: Alignment.centerLeft,
                                  colors: <Color>[
                                    ink.withValues(alpha: pose.shade * 0.25),
                                    ink.withValues(alpha: pose.shade),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: widget.child,
      ),
    );
  }

  /// The lifted leaf's shadow across the page beneath: against the spine in
  /// a window, and astride the centre fold on a spread.
  LinearGradient _underShadow(Color ink, double depth) {
    final Color lit = ink.withValues(alpha: depth * 0.1);
    final Color shadowed = ink.withValues(alpha: depth);
    return widget.spread
        ? LinearGradient(
            colors: <Color>[lit, shadowed, lit],
            stops: const <double>[0, 0.5, 1],
          )
        : LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[lit, shadowed],
          );
  }
}
