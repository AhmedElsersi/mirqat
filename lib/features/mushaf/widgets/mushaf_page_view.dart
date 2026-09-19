import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../data/models/word.dart';
import '../cubit/mushaf_page.dart';

/// One mushaf page, fitted to the space it is given. It never scrolls.
///
/// ONE font size per page, derived from the space and the data:
///  * height — the page is laid out for the fullest page's line count, so a
///    short page (the opening two) keeps the same line pitch, centred, rather
///    than stretching eight lines to fill fifteen slots;
///  * width — every line's measured natural width, plus a minimum gap between
///    words, must fit.
/// The smaller wins. Justified lines then spread their words edge to edge with
/// spaceBetween; centred lines sit in the middle.
class MushafPageView extends StatefulWidget {
  const MushafPageView({
    required this.page,
    required this.linesPerFullPage,
    required this.highlighted,
    required this.selected,
    required this.onWordTap,
    super.key,
  });

  final MushafPage page;
  final int linesPerFullPage;
  final AyahRef? highlighted;
  final AyahRef? selected;
  final ValueChanged<Word> onWordTap;

  @override
  State<MushafPageView> createState() => _MushafPageViewState();
}

class _MushafPageViewState extends State<MushafPageView> {
  /// Widths are measured once at this size and scaled: glyph advances are
  /// linear in font size, and re-measuring every word on every layout would
  /// be a text layout pass per word per frame.
  static const double _referenceSize = 100;

  /// The narrowest gap allowed between two words, in ems.
  static const double _minGapEm = 0.3;

  /// Headroom so rounding never tips a full line over the edge.
  static const double _safety = 0.985;

  final Map<int, double> _widthPerEm = <int, double>{};
  double? _lineHeightPerEm;

  double _width(Word w) => _widthPerEm.putIfAbsent(
    w.id,
    () =>
        AyahText.mushafWordWidth(w.text, fontSize: _referenceSize) /
        _referenceSize,
  );

  double get _lineHeight => _lineHeightPerEm ??=
      AyahText.mushafLineHeight(fontSize: _referenceSize) / _referenceSize;

  @override
  void didUpdateWidget(MushafPageView old) {
    super.didUpdateWidget(old);
    if (old.page.number != widget.page.number) _widthPerEm.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // A narrow margin of bare page outside the frame, so the ornament is
      // seen whole rather than running into the edge of the glass.
      padding: EdgeInsetsDirectional.symmetric(horizontal: 6.w, vertical: 4.h),
      child: IslamicFrame(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) {
            final int slots = math.max(
              widget.linesPerFullPage,
              widget.page.lines.length,
            );
            final double pitch = box.maxHeight / slots;
            final double fontSize = _fontSizeFor(box.maxWidth, pitch);

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (final PageLine line in widget.page.lines)
                  SizedBox(
                    height: pitch,
                    width: box.maxWidth,
                    child: _line(context, line, fontSize),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _fontSizeFor(double width, double pitch) {
    double size = pitch / _lineHeight;
    for (final PageLine line in widget.page.lines) {
      final List<Word> words = switch (line) {
        AyahLine(:final List<Word> words) => words,
        BasmalaLine(:final List<Word> words) => words,
        SurahHeaderLine() => const <Word>[],
      };
      if (words.isEmpty) continue;
      final double ems =
          words.map(_width).reduce((double a, double b) => a + b) +
          _minGapEm * (words.length - 1);
      size = math.min(size, width / ems);
    }
    return size * _safety;
  }

  Widget _line(BuildContext context, PageLine line, double fontSize) =>
      switch (line) {
        SurahHeaderLine(:final surah) => _SurahHeader(
          name: surah.nameAr,
          fontSize: fontSize,
        ),
        BasmalaLine(:final List<Word> words) => _centred(<Widget>[
          // Belongs to no ayah: drawn, never tappable.
          for (final Word w in words)
            AyahText.word(text: w.text, fontSize: fontSize),
        ], fontSize),
        AyahLine(:final List<Word> words, :final bool centered) =>
          centered
              ? _centred(_words(words, fontSize), fontSize)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _words(words, fontSize),
                ),
      };

  Widget _centred(List<Widget> children, double fontSize) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      for (int i = 0; i < children.length; i++) ...<Widget>[
        if (i > 0) SizedBox(width: fontSize * _minGapEm),
        children[i],
      ],
    ],
  );

  List<Widget> _words(List<Word> words, double fontSize) => <Widget>[
    for (final Word w in words)
      w.isMarker
          // The ayah-number medallion: part of the line, not of the ayah.
          ? AyahText.word(text: w.text, fontSize: fontSize, isMarker: true)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onWordTap(w),
              child: AyahText.word(
                text: w.text,
                fontSize: fontSize,
                tint: _tintFor(w),
              ),
            ),
  ];

  WordTint _tintFor(Word w) {
    if (widget.selected?.contains(w) ?? false) return WordTint.selected;
    if (widget.highlighted?.contains(w) ?? false) return WordTint.highlighted;
    return WordTint.none;
  }
}

/// The decorated heading opening a surah. The name is a label, not scripture,
/// so it is set in the interface face.
class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.name, required this.fontSize});

  final String name;
  final double fontSize;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.symmetric(vertical: fontSize * 0.1),
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) =>
          SurahCartouche(name: name, height: box.maxHeight),
    ),
  );
}
