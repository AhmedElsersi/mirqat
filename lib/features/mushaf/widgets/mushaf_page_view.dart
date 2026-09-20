import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/extensions/number_extensions.dart';
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
    required this.onWordLongPress,
    this.onTap,
    this.isSelected,
    this.isHeldBack,
    super.key,
  });

  final MushafPage page;
  final int linesPerFullPage;
  final AyahRef? highlighted;
  final AyahRef? selected;

  /// A long press on a word, which is how an ayah is chosen. Not a tap: a
  /// tap anywhere on the page belongs to [onTap], and one gesture cannot mean
  /// both "show me the controls" and "act on this ayah".
  final ValueChanged<Word> onWordLongPress;

  /// A tap anywhere on the page, words included.
  final VoidCallback? onTap;

  /// Whether a word lies in the range chosen for a session. Beside
  /// [selected], which is the one ayah under the reader's finger.
  final bool Function(Word word)? isSelected;

  /// Whether a word is on the page only because it shares a line with the
  /// surah or juz being read — printed, but not part of it, and drawn
  /// fainter. Such a word takes no long press.
  final bool Function(Word word)? isHeldBack;

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
      padding: EdgeInsetsDirectional.symmetric(horizontal: 4.w, vertical: 3.h),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final MushafPage p = widget.page;
          final FrameLabels labels = FrameLabels(
            topStart: p.surah == null
                ? null
                : LocaleKeys.mushafSurahLabel.tr(
                    args: <String>[p.surah!.nameAr],
                  ),
            topEnd: p.juz == null
                ? null
                : LocaleKeys.mushafJuzLabel.tr(
                    args: <String>[p.juz!.toLocalisedString()],
                  ),
            bottom: p.number.toLocalisedString(),
            side: p.hizb == null
                ? null
                : LocaleKeys.mushafHizbLabel.tr(
                    args: <String>[p.hizb!.toLocalisedString()],
                  ),
          );
          final EdgeInsets insets = IslamicFrame.insetsFor(
            box.maxWidth,
            labelled: true,
          );
          final double width = box.maxWidth - insets.horizontal;
          final double room = box.maxHeight - insets.vertical;

          final int slots = math.max(
            widget.linesPerFullPage,
            widget.page.lines.length,
          );

          // The width alone decides the size of the text: a line is as large
          // as it can be and still fit across the page. The height never
          // squeezes it. Where the page is taller than the glass — a short
          // phone, a tablet on its side, a thick frame — the page scrolls,
          // frame and all, the way a printed page larger than the window
          // would. Where there is room to spare, the lines spread to fill it.
          final double fontSize = _fontSizeFor(width);
          final double pitch = math.max(room / slots, fontSize * _lineHeight);

          final Widget page = IslamicFrame(
            labels: labels,
            child: SizedBox(
              width: width,
              height: pitch * slots,
              child: Column(
                // A page with a neighbour's lines left out starts at the top,
                // like the opening of a chapter. A page that is simply short
                // stays centred, as the mushaf prints it.
                mainAxisAlignment: widget.page.partial
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: <Widget>[
                  for (final PageLine line in widget.page.lines)
                    SizedBox(
                      height: pitch,
                      width: width,
                      child: _line(context, line, fontSize),
                    ),
                ],
              ),
            ),
          );

          final bool fits = pitch * slots <= room + 0.5;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: fits ? page : SingleChildScrollView(child: page),
          );
        },
      ),
    );
  }

  /// The largest size at which every line of this page fits across [width].
  double _fontSizeFor(double width) {
    double size = double.infinity;
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
    // A page with no text lines at all has nothing to measure against.
    if (!size.isFinite) size = width / 18;
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
      if (w.isMarker)
        // The ayah-number medallion: part of the line, not of the ayah.
        AyahText.word(
          text: w.text,
          fontSize: fontSize,
          isMarker: true,
          heldBack: widget.isHeldBack?.call(w) ?? false,
        )
      else if (widget.isHeldBack?.call(w) ?? false)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AyahText.word(
            text: w.text,
            fontSize: fontSize,
            heldBack: true,
          ),
        )
      else
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onLongPress: () => widget.onWordLongPress(w),
          // As tall as the line, not as the letters: the strip between
          // two lines of text belongs to the word above or below it, or a
          // long press that lands a few pixels off a word silently turns
          // into a tap on the page.
          child: SizedBox(
            height: double.infinity,
            child: Center(
              widthFactor: 1,
              child: AyahText.word(
                text: w.text,
                fontSize: fontSize,
                tint: _tintFor(w),
              ),
            ),
          ),
        ),
  ];

  WordTint _tintFor(Word w) {
    if (widget.selected?.contains(w) ?? false) return WordTint.selected;
    if (widget.highlighted?.contains(w) ?? false) return WordTint.highlighted;
    if (widget.isSelected?.call(w) ?? false) return WordTint.ranged;
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
