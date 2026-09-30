import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The illuminated border of a mushaf page: a green band between gold rules,
/// carrying a run of gold lozenges, with an eight-pointed star in each corner.
///
/// Drawn, not loaded. There is no image behind this and no SVG package
/// (CLAUDE.md A.4): it is a few lines and polygons, so it is sharp at any
/// size, costs nothing in the bundle, and has no "wrong resolution". The
/// colours are the icon's — a gold arch on deep green — which is what makes
/// the page and the launcher look like the same object.
///
/// It only ever surrounds Quranic text and never overlaps it
/// (A.2 rule 7): the child is laid out strictly inside the inner rule.
class IslamicFrame extends StatelessWidget {
  const IslamicFrame({required this.child, this.band, this.labels, super.key});

  final Widget child;

  /// Width of the ornamented band at the sides. Defaults to a fraction of the
  /// frame's own width, held between 18 and 30 logical pixels: wide enough for
  /// the woven lattice and its guard stripes to read as illumination rather
  /// than as a rule. It was half this at first, to spare the text; the owner
  /// asked for the ornament to have presence, and a page that no longer fits
  /// simply scrolls, as a printed page larger than the glass would.
  final double? band;

  /// What the borders say about the page — surah and juz along the top, the
  /// page number at the foot, the hizb in the right-hand border — the way a
  /// printed mushaf writes them in its margins. With labels the top and
  /// bottom bands are taller than the sides, so that the words in them can be
  /// read rather than merely present.
  final FrameLabels? labels;

  /// The side band for a frame [width] wide.
  static double bandFor(double width) => (width * 0.055).clamp(18.0, 30.0);

  /// The top and bottom band: the side band, or taller when it carries words.
  static double crossBandFor(double band, {required bool labelled}) =>
      labelled ? band * 1.4 : band;

  /// From the frame's outer edge to where its child begins: the band, then a
  /// breath of bare page before the first letter. Public so that a page can
  /// work out how much room its text really has.
  static EdgeInsets insetsFor(
    double width, {
    double? band,
    bool labelled = false,
  }) {
    final double b = band ?? bandFor(width);
    final double breath = b * 0.45;
    return EdgeInsets.symmetric(
      horizontal: b + breath,
      vertical: crossBandFor(b, labelled: labelled) + breath,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints box) {
      final double b = band ?? bandFor(box.maxWidth);
      final FrameLabels? l = labels;
      final bool labelled = l != null && !l.isEmpty;
      final double cross = crossBandFor(b, labelled: labelled);

      return Stack(
        children: <Widget>[
          CustomPaint(
            painter: _FramePainter(band: b, crossBand: cross),
            child: Padding(
              padding: insetsFor(box.maxWidth, band: b, labelled: labelled),
              child: child,
            ),
          ),
          // The labels sit on the band and nowhere else: never over the page,
          // and so never over a word of it (CLAUDE.md A.2 rule 7).
          if (labelled) ...<Widget>[
            Positioned(
              top: 0,
              left: b * 1.6,
              right: b * 1.6,
              height: cross,
              // A mushaf page reads right to left whatever the interface
              // language, so the surah is on the right and the juz on the left.
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    _Plaque(text: l.topStart, height: cross * 0.74),
                    _Plaque(text: l.topEnd, height: cross * 0.74),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: b * 1.6,
              right: b * 1.6,
              height: cross,
              child: Center(
                child: _Plaque(text: l.bottom, height: cross * 0.74),
              ),
            ),
            Positioned(
              top: cross * 1.4,
              bottom: cross * 1.4,
              right: 0,
              width: b,
              child: Center(
                child: RotatedBox(
                  quarterTurns: 1,
                  child: _Plaque(text: l.side, height: b * 0.8),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// The words a frame carries in its borders. Any of them may be absent; an
/// absent one leaves the weave unbroken there.
class FrameLabels {
  const FrameLabels({this.topStart, this.topEnd, this.bottom, this.side});

  /// Top border, on the side a page begins — the surah.
  final String? topStart;

  /// Top border, far side — the juz.
  final String? topEnd;

  /// Bottom border, centred — the page number.
  final String? bottom;

  /// The right-hand border, turned to run along it — the hizb.
  final String? side;

  bool get isEmpty =>
      topStart == null && topEnd == null && bottom == null && side == null;
}

/// A small gold-ruled panel set into the band, interrupting the weave.
class _Plaque extends StatelessWidget {
  const _Plaque({required this.text, required this.height});

  final String? text;
  final double height;

  @override
  Widget build(BuildContext context) {
    final String? label = text;
    if (label == null || label.isEmpty) return const SizedBox.shrink();

    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * 0.55),
      decoration: ShapeDecoration(
        color: AppColors.forest,
        shape: StadiumBorder(
          side: BorderSide(
            color: AppColors.gold,
            width: math.max(1.0, height * 0.06),
          ),
        ),
      ),
      // Sized to its words. `alignment:` on the Container itself would make
      // it swell to whatever room it is offered — the whole length of the
      // border, for the two plaques that are not inside a Row.
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          textScaler: TextScaler.noScaling,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontSize: height * 0.56,
            height: 1.0,
            color: AppColors.cream,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.band, required this.crossBand});

  /// The band at the sides.
  final double band;

  /// The band along the top and bottom — taller when it carries labels.
  final double crossBand;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect outer = Offset.zero & size;
    final Rect inner = Rect.fromLTRB(
      band,
      crossBand,
      size.width - band,
      size.height - crossBand,
    );
    final double rule = math.max(1.2, band * 0.075);
    final double hair = math.max(0.8, rule * 0.55);

    final Paint ground = Paint()..color = AppColors.forest;
    final Paint gold = Paint()
      ..color = AppColors.gold
      ..isAntiAlias = true;
    Paint line(double width) => Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;

    // The band itself.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(outer)
        ..addRect(inner),
      ground,
    );

    // Across its width the band reads: gold rule, guard stripe, hairline,
    // the woven zone, hairline, guard stripe, gold rule. The two hairlines
    // fence the lattice in, and that fencing is most of what separates an
    // illuminated border from a patterned one.
    final double guard = band * 0.2;
    canvas
      ..drawRect(outer.deflate(rule / 2), line(rule))
      ..drawRect(inner.inflate(rule / 2), line(rule))
      ..drawRect(outer.deflate(guard), line(hair))
      ..drawRect(inner.inflate(guard), line(hair))
      // And one more, just inside the band, on the page itself.
      ..drawRect(inner.deflate(band * 0.16), line(hair));

    // The woven zone: two zigzags, one the mirror of the other, so that they
    // cross and recross into a chain of lozenges with a gold seed in each.
    // The cell count is whatever divides the side exactly — a weave that ends
    // on half a lozenge is the first thing the eye finds.
    final double seed = math.max(1.0, band * 0.055);

    // [thickness] is the band being woven along: the zone is what is left of
    // it between the guard stripes.
    void weave(Offset from, Offset to, double thickness) {
      final double reach = thickness / 2 - guard - hair;
      final Offset along = to - from;
      final double length = along.distance;
      final int cells = math.max(1, (length / (reach * 2.6)).round());
      final Offset step = along / cells.toDouble();
      final Offset across = Offset(-along.dy, along.dx) / length * reach;

      final Path over = Path()..moveTo((from + across).dx, (from + across).dy);
      final Path under = Path()..moveTo((from - across).dx, (from - across).dy);
      for (int i = 0; i < cells; i++) {
        final Offset mid = from + step * (i + 0.5);
        final Offset end = from + step * (i + 1.0);
        over
          ..lineTo((mid - across).dx, (mid - across).dy)
          ..lineTo((end + across).dx, (end + across).dy);
        under
          ..lineTo((mid + across).dx, (mid + across).dy)
          ..lineTo((end - across).dx, (end - across).dy);
        // A seed where the strands part widest, a smaller one where they cross.
        canvas.drawCircle(from + step * i.toDouble(), seed, gold);
        canvas.drawCircle(mid, seed * 0.6, gold);
      }
      canvas.drawCircle(to, seed, gold);
      canvas
        ..drawPath(over, line(hair * 1.25))
        ..drawPath(under, line(hair * 1.25));
    }

    final double mx = band / 2;
    final double my = crossBand / 2;
    weave(Offset(band, my), Offset(size.width - band, my), crossBand);
    weave(
      Offset(band, size.height - my),
      Offset(size.width - band, size.height - my),
      crossBand,
    );
    weave(Offset(mx, crossBand), Offset(mx, size.height - crossBand), band);
    weave(
      Offset(size.width - mx, crossBand),
      Offset(size.width - mx, size.height - crossBand),
      band,
    );

    // Corner pieces: a gold-ruled cell holding an eight-pointed star — two
    // squares, one turned an eighth. The oldest figure in Islamic geometric
    // ornament, and the one that marks a quarter of a hizb in the margin of
    // every mushaf.
    final double star = math.min(band, crossBand) * 0.36;
    for (final Offset c in <Offset>[
      Offset(mx, my),
      Offset(size.width - mx, my),
      Offset(mx, size.height - my),
      Offset(size.width - mx, size.height - my),
    ]) {
      final Rect cell = Rect.fromCenter(
        center: c,
        width: band,
        height: crossBand,
      );
      canvas
        ..drawRect(cell, ground)
        ..drawRect(cell.deflate(rule / 2), line(rule));
      paintEightPointStar(canvas, c, star, gold);
      paintEightPointStar(canvas, c, star - rule * 1.5, ground);
      paintEightPointStar(canvas, c, star * 0.42, gold);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.band != band || old.crossBand != crossBand;
}

/// Two overlapping squares about [centre], the second turned 45°.
void paintEightPointStar(
  Canvas canvas,
  Offset centre,
  double radius,
  Paint paint,
) {
  for (final double turn in <double>[0, math.pi / 4]) {
    final Path square = Path();
    for (int k = 0; k < 4; k++) {
      final double a = turn + k * math.pi / 2;
      final Offset p = centre + Offset(math.cos(a), math.sin(a)) * radius;
      k == 0 ? square.moveTo(p.dx, p.dy) : square.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(square..close(), paint);
  }
}

/// The panel a surah's name sits in at the head of the surah: a green field
/// between gold rules, closed at each end by an eight-pointed star.
///
/// The name is a label, not scripture, so it is set in the interface face —
/// and in cream, not gold: gold on this green is legible, cream is easy.
class SurahCartouche extends StatelessWidget {
  const SurahCartouche({required this.name, required this.height, super.key});

  final String name;

  /// The panel's height. Everything else — the stars, the rules, the text —
  /// is proportioned from it.
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: double.infinity,
    child: CustomPaint(
      painter: _CartouchePainter(),
      child: Center(
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: height * 1.25),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name,
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: height * 0.46,
                height: 1.0,
                color: AppColors.cream,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _CartouchePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double rule = math.max(1.0, h * 0.035);
    final Paint ground = Paint()..color = AppColors.forest;
    final Paint gold = Paint()
      ..color = AppColors.gold
      ..isAntiAlias = true;
    final Paint goldLine = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = rule
      ..isAntiAlias = true;

    // The field runs between the two stars' centres, a little shorter than
    // they are tall, so the stars stand proud of it at both ends.
    final Rect field = Rect.fromLTRB(
      h * 0.5,
      h * 0.14,
      size.width - h * 0.5,
      h * 0.86,
    );
    canvas
      ..drawRect(field, ground)
      ..drawRect(field, goldLine)
      ..drawRect(
        field.deflate(h * 0.09),
        goldLine..strokeWidth = math.max(0.75, rule * 0.6),
      );

    // A touch smaller than the panel is tall, so the points clear whatever
    // the cartouche sits against instead of touching it.
    for (final double x in <double>[h * 0.5, size.width - h * 0.5]) {
      final Offset c = Offset(x, h / 2);
      paintEightPointStar(canvas, c, h * 0.46, gold);
      paintEightPointStar(canvas, c, h * 0.46 - rule * 1.6, ground);
      paintEightPointStar(canvas, c, h * 0.18, gold);
    }
  }

  @override
  bool shouldRepaint(_CartouchePainter old) => false;
}
