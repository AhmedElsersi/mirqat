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
  const IslamicFrame({required this.child, this.band, super.key});

  final Widget child;

  /// Width of the ornamented band. Defaults to a fraction of the frame's own
  /// width, held between 9 and 16 logical pixels: thick enough for the
  /// lozenges to read, thin enough that the text barely shrinks for it.
  final double? band;

  /// The band for a frame [width] wide.
  static double bandFor(double width) => (width * 0.03).clamp(9.0, 16.0);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints box) {
      final double b = band ?? bandFor(box.maxWidth);
      return CustomPaint(
        painter: _FramePainter(band: b),
        child: Padding(
          // The band, then a breath of page before the first letter.
          padding: EdgeInsets.all(b + b * 0.55),
          child: child,
        ),
      );
    },
  );
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.band});

  final double band;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect outer = Offset.zero & size;
    final Rect inner = outer.deflate(band);
    final double rule = math.max(1.0, band * 0.11);

    final Paint ground = Paint()..color = AppColors.forest;
    final Paint gold = Paint()
      ..color = AppColors.gold
      ..isAntiAlias = true;
    final Paint goldLine = Paint()
      ..color = AppColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = rule
      ..isAntiAlias = true;

    // The band itself.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(outer)
        ..addRect(inner),
      ground,
    );

    // Gold rules on both edges of the band, and a hairline just inside it —
    // the double line is what makes a border read as illumination rather
    // than as a box.
    canvas
      ..drawRect(outer.deflate(rule / 2), goldLine)
      ..drawRect(inner.inflate(rule / 2), goldLine)
      ..drawRect(
        inner.deflate(band * 0.28),
        goldLine..strokeWidth = math.max(0.75, rule * 0.6),
      );

    // Lozenges along each side, between the corner squares. The count is
    // chosen so they divide the side exactly: a pattern that ends on half a
    // lozenge is the first thing the eye finds.
    final double half = band * 0.27;
    final double dot = band * 0.07;

    void run(Offset from, Offset to) {
      final double length = (to - from).distance;
      final int cells = math.max(1, (length / (band * 1.7)).round());
      final Offset step = (to - from) / cells.toDouble();
      for (int i = 0; i < cells; i++) {
        final Offset c = from + step * (i + 0.5);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - half)
            ..lineTo(c.dx + half, c.dy)
            ..lineTo(c.dx, c.dy + half)
            ..lineTo(c.dx - half, c.dy)
            ..close(),
          gold,
        );
        if (i > 0) canvas.drawCircle(from + step * i.toDouble(), dot, gold);
      }
    }

    final double m = band / 2;
    run(Offset(band, m), Offset(size.width - band, m));
    run(
      Offset(band, size.height - m),
      Offset(size.width - band, size.height - m),
    );
    run(Offset(m, band), Offset(m, size.height - band));
    run(
      Offset(size.width - m, band),
      Offset(size.width - m, size.height - band),
    );

    // An eight-pointed star in each corner: two squares, one turned an
    // eighth. The oldest figure in Islamic geometric ornament, and the one
    // that marks a quarter of a hizb in the margin of every mushaf.
    for (final Offset c in <Offset>[
      Offset(m, m),
      Offset(size.width - m, m),
      Offset(m, size.height - m),
      Offset(size.width - m, size.height - m),
    ]) {
      paintEightPointStar(canvas, c, band * 0.40, gold);
      canvas.drawCircle(c, band * 0.11, ground);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.band != band;
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

    for (final double x in <double>[h * 0.5, size.width - h * 0.5]) {
      final Offset c = Offset(x, h / 2);
      paintEightPointStar(canvas, c, h * 0.5, gold);
      paintEightPointStar(canvas, c, h * 0.5 - rule * 1.6, ground);
      paintEightPointStar(canvas, c, h * 0.2, gold);
    }
  }

  @override
  bool shouldRepaint(_CartouchePainter old) => false;
}
