import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/islamic_frame.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/word.dart';
import '../cubit/mushaf_page.dart';
import 'page_reflow.dart';

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
    this.veiled,
    this.memorizationView = MemorizationView.off,
    this.stumbled = const <AyahRef>{},
    this.marked,
    this.ribbon = true,
    required this.selected,
    required this.onWordLongPress,
    this.onTap,
    this.isSelected,
    this.isHeldBack,
    this.textScale = 1,
    super.key,
  });

  final MushafPage page;
  final int linesPerFullPage;
  final AyahRef? highlighted;

  /// The ayah a recall round is asking back: its words are drawn covered —
  /// a soft band where the letters are, the letters themselves withheld —
  /// until the answering play lifts the veil. The words and their layout are
  /// untouched (A.2 rule 1 is about the bytes, and they are not read here at
  /// all); only their ink is withheld, by the reader's own setting, the way a
  /// hand covers the page in a tasmee'. The ayah's number stays legible so
  /// the reader knows which ayah is being asked.
  final AyahRef? veiled;

  /// How much of the page the reader has asked to be covered while reading
  /// ([MemorizationView]). Covered the same way [veiled] is — ink withheld,
  /// place and bytes untouched — and a tap on a covered word reveals its ayah
  /// until the next tap.
  final MemorizationView memorizationView;

  /// Ayahs the reader stumbles at, dotted underneath. Empty when the reader
  /// has asked for the page without them.
  final Set<AyahRef> stumbled;

  /// The ayah the reader marked as where they stopped, if it is on this page.
  final AyahRef? marked;

  /// Whether the page that holds [marked] hangs a ribbon down its edge.
  final bool ribbon;
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

  /// The reader's text size, as a multiple of the size at which a printed
  /// line exactly fills the page. 1 is the mushaf as it is printed. Below 1
  /// the same lines are set smaller. Above 1 no printed line fits any more,
  /// so the page's lines are re-broken at the larger size (see [reflowPage])
  /// and the page scrolls.
  final double textScale;

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

  /// The ayah the reader has uncovered by tapping one of its covered words,
  /// under the memorization view. One at a time; the next tap covers it
  /// again.
  AyahRef? _peeked;

  @override
  void didUpdateWidget(MushafPageView old) {
    super.didUpdateWidget(old);
    if (old.page.number != widget.page.number) {
      _widthPerEm.clear();
      _peeked = null;
    }
    if (old.memorizationView != widget.memorizationView) _peeked = null;
  }

  /// A tap anywhere on the page. While an ayah is uncovered it covers it
  /// again and does nothing else — the reader is checking a word, not asking
  /// for the bar.
  void _onPageTap() {
    if (_peeked != null) {
      setState(() => _peeked = null);
      return;
    }
    widget.onTap?.call();
  }

  /// A tap on a recited word: under the memorization view a covered word
  /// uncovers its ayah, and a word of the uncovered ayah covers it again.
  void _onWordTap(Word w) {
    if (_peeked == w.ref) {
      setState(() => _peeked = null);
      return;
    }
    if (_coveredByView(w)) {
      setState(() => _peeked = w.ref);
      return;
    }
    _onPageTap();
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
            side: _hizbLabel(p.hizb, p.rub),
          );
          final EdgeInsets insets = IslamicFrame.insetsFor(
            box.maxWidth,
            labelled: true,
          );
          final double width = box.maxWidth - insets.horizontal;
          final double room = box.maxHeight - insets.vertical;

          // The width decides the size of the text: at a scale of 1 a line
          // is as large as it can be and still fit across the page. The
          // height never squeezes it. Where the page is taller than the
          // glass — a short phone, a tablet on its side, a thick frame, a
          // reader who has asked for larger text — the page scrolls, frame
          // and all, the way a printed page larger than the window would.
          // Where there is room to spare, the lines spread to fill it.
          final double fontSize = _fontSizeFor(width) * widget.textScale;
          final List<PageLine> lines = widget.textScale > 1
              ? reflowPage(
                  lines: widget.page.lines,
                  maxWidth: width * _safety,
                  gap: fontSize * _minGapEm,
                  widthOf: (Word w) => _width(w) * fontSize,
                )
              : widget.page.lines;

          final int slots = math.max(widget.linesPerFullPage, lines.length);
          final double pitch = math.max(room / slots, fontSize * _lineHeight);

          final Widget text = Column(
            // A page with a neighbour's lines left out starts at the top,
            // like the opening of a chapter. A page that is simply short
            // stays centred, as the mushaf prints it.
            mainAxisAlignment: widget.page.partial
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: <Widget>[
              for (final PageLine line in lines)
                SizedBox(
                  height: pitch,
                  width: width,
                  child: _line(context, line, fontSize),
                ),
            ],
          );
          // The breath of bare page between the band and the first letter:
          // the ribbon hangs from there, as though tucked under the band.
          final double breath =
              insets.top -
              IslamicFrame.crossBandFor(
                IslamicFrame.bandFor(box.maxWidth),
                labelled: true,
              );
          final Widget page = IslamicFrame(
            labels: labels,
            child: SizedBox(
              width: width,
              height: pitch * slots,
              child: !(widget.ribbon && _holdsMark)
                  ? text
                  : Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        text,
                        PositionedDirectional(
                          top: -breath,
                          // A mushaf opens from the right whatever the
                          // interface language: the ribbon hangs at the
                          // page's opening edge.
                          start: fontSize * 0.35,
                          child: ReadingRibbon(
                            width: fontSize * 1.7,
                            height: pitch * slots * 0.18,
                          ),
                        ),
                      ],
                    ),
            ),
          );

          final bool fits = pitch * slots <= room + 0.5;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onPageTap,
            child: fits ? page : SingleChildScrollView(child: page),
          );
        },
      ),
    );
  }

  /// The side border's words: the hizb, and — where the page opens past its
  /// start — which quarter of it, the way a printed mushaf marks the rub',
  /// the nisf and the three-quarters in its margin. The rub' number runs
  /// 1..240 over the whole mushaf, four to a hizb, so `(rub - 1) % 4` is the
  /// quarter the page opens in.
  static String? _hizbLabel(int? hizb, int? rub) {
    if (hizb == null) return null;
    final String n = hizb.toLocalisedString();
    final String key = switch (rub == null ? 0 : (rub - 1) % 4) {
      1 => LocaleKeys.mushafHizbQuarterLabel,
      2 => LocaleKeys.mushafHizbHalfLabel,
      3 => LocaleKeys.mushafHizbThreeQuartersLabel,
      _ => LocaleKeys.mushafHizbLabel,
    };
    return key.tr(args: <String>[n]);
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
        AyahLine(:final List<Word> words, :final bool centered) => CustomPaint(
          painter: _TintBands(
            widths: <double>[for (final Word w in words) _width(w) * fontSize],
            tints: <WordTint>[for (final Word w in words) _tintFor(w)],
            underlined: <bool>[for (final Word w in words) _isStumbled(w)],
            centredGap: centered ? fontSize * _minGapEm : null,
            bandHeight: fontSize * _lineHeight,
            colors: Theme.of(context).colorScheme,
          ),
          child: centered
              ? _centred(_words(words, fontSize), fontSize)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _words(words, fontSize),
                ),
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
        // Tinted with its ayah, whose last glyph it is, so that a marked run
        // does not break at every ayah's end.
        AyahText.word(
          text: w.text,
          fontSize: fontSize,
          isMarker: true,
          tint: _tintFor(w),
          paintsTint: false,
          heldBack: widget.isHeldBack?.call(w) ?? false,
        )
      else if (widget.isHeldBack?.call(w) ?? false)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onPageTap,
          child: AyahText.word(
            text: w.text,
            fontSize: fontSize,
            heldBack: true,
          ),
        )
      else
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _onWordTap(w),
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
                paintsTint: false,
                veiled: _isVeiled(w),
              ),
            ),
          ),
        ),
  ];

  /// Whether the reader's mark is on this page: a word of the marked ayah
  /// is printed here.
  bool get _holdsMark {
    final AyahRef? mark = widget.marked;
    if (mark == null) return false;
    for (final PageLine line in widget.page.lines) {
      final List<Word> words = switch (line) {
        AyahLine(:final List<Word> words) => words,
        BasmalaLine(:final List<Word> words) => words,
        SurahHeaderLine() => const <Word>[],
      };
      if (words.any(mark.contains)) return true;
    }
    return false;
  }

  /// A covered word keeps the band of the ayah under the reader's finger or
  /// being recited — which ayah that is matters more than that it is
  /// covered — and otherwise shows the quiet band that says words lie there.
  WordTint _tintFor(Word w) {
    if (widget.isHeldBack?.call(w) ?? false) return WordTint.none;
    if (widget.selected?.contains(w) ?? false) return WordTint.selected;
    if (widget.highlighted?.contains(w) ?? false) return WordTint.highlighted;
    if (_isVeiled(w)) return WordTint.veiled;
    if (widget.marked?.contains(w) ?? false) return WordTint.marked;
    if (widget.isSelected?.call(w) ?? false) return WordTint.ranged;
    return WordTint.none;
  }

  /// Whether [w] belongs to an ayah the reader stumbles at. Its marker too:
  /// the dots then run to the ayah's end, as a pencil line would.
  bool _isStumbled(Word w) =>
      !(widget.isHeldBack?.call(w) ?? false) && widget.stumbled.contains(w.ref);

  /// Whether [w]'s ink is withheld: a word of the ayah a recall round is
  /// asking back, or one the memorization view covers and the reader has not
  /// uncovered. The ayah-number medallion never is — it says which ayah is
  /// being asked, and where each one ends.
  bool _isVeiled(Word w) {
    if (w.isMarker) return false;
    if (widget.veiled?.contains(w) ?? false) return true;
    return _coveredByView(w) && _peeked != w.ref;
  }

  /// Whether the memorization view covers [w]: every recited word, or every
  /// one but the first of its ayah. Words on the page only because they
  /// share a line with the section being read are not the reader's to
  /// recite, and stay as they are.
  bool _coveredByView(Word w) {
    if (w.isMarker || (widget.isHeldBack?.call(w) ?? false)) return false;
    return switch (widget.memorizationView) {
      MemorizationView.off => false,
      MemorizationView.firstWords => w.position != 1,
      MemorizationView.markersOnly => true,
    };
  }
}

/// Paints the tint behind a line's words: one band for each run of
/// neighbouring words that share a tint, under the words and the spaces
/// between them, so that a marked ayah is a stroke of highlighter along the
/// line rather than a box per word.
///
/// It works the words' places out the way the line lays itself out: right to
/// left, each at its measured width, the room left over shared equally
/// between them (or a fixed gap, for a centred line). Nothing here touches a
/// word: it is colour behind the text, and the text is drawn over it as it is.
class _TintBands extends CustomPainter {
  const _TintBands({
    required this.widths,
    required this.tints,
    required this.underlined,
    required this.centredGap,
    required this.bandHeight,
    required this.colors,
  });

  final List<double> widths;
  final List<WordTint> tints;

  /// Words dotted underneath: a stumbled ayah's. A line of dots rather than a
  /// tint, so it never competes with the recitation's band or the mark's.
  final List<bool> underlined;

  /// The fixed gap of a centred line, or null for a justified one.
  final double? centredGap;
  final double bandHeight;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = widths.length;
    if (n == 0) return;
    final double total = widths.fold(0, (double a, double b) => a + b);
    final double gap =
        centredGap ?? (n > 1 ? (size.width - total) / (n - 1) : 0);

    // The right-hand edge of the first word: the line's own edge when it is
    // justified, the start of the centred block when it is not.
    double right = centredGap == null
        ? size.width
        : (size.width + total + gap * (n - 1)) / 2;
    final double top = (size.height - bandHeight) / 2;
    final double runStart = right;

    int i = 0;
    while (i < n) {
      final WordTint tint = tints[i];
      final double runRight = right;
      double runLeft = right - widths[i];
      right = runLeft - gap;
      int j = i + 1;
      while (j < n && tints[j] == tint) {
        runLeft = right - widths[j];
        right = runLeft - gap;
        j++;
      }
      final Color? color = AyahText.tintColor(colors, tint);
      if (color != null) {
        canvas.drawRRect(
          RRect.fromLTRBR(
            runLeft - 2,
            top,
            runRight + 2,
            top + bandHeight,
            const Radius.circular(4),
          ),
          Paint()..color = color,
        );
      }
      i = j;
    }

    if (!underlined.contains(true)) return;
    final Paint dot = Paint()..color = colors.error.withValues(alpha: 0.75);
    final double radius = (bandHeight * 0.022).clamp(0.8, 2.0);
    final double step = radius * 3.5;
    final double y = top + bandHeight - radius * 2;
    double wordRight = runStart;
    for (int k = 0; k < n; k++) {
      final double wordLeft = wordRight - widths[k];
      if (underlined[k]) {
        for (double x = wordRight - radius; x >= wordLeft; x -= step) {
          canvas.drawCircle(Offset(x, y), radius, dot);
        }
      }
      wordRight = wordLeft - gap;
    }
  }

  @override
  bool shouldRepaint(_TintBands old) =>
      old.centredGap != centredGap ||
      old.bandHeight != bandHeight ||
      old.colors != colors ||
      !_same(old.widths, widths) ||
      !_same(old.tints, tints) ||
      !_same(old.underlined, underlined);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

/// The reading mark's ribbon: a tall band of the bookmark's gold hung down
/// the page's opening edge with a notched foot, the way a ribbon marks a
/// printed mushaf. A light wash, so the letters under it stay legible, and
/// deaf to touch, so a press on the page beneath still opens its ayah.
class ReadingRibbon extends StatelessWidget {
  const ReadingRibbon({required this.width, required this.height, super.key});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: CustomPaint(
        size: Size(width, height),
        painter: _RibbonPainter(fill: colors.secondary.withValues(alpha: 0.25)),
      ),
    );
  }
}

/// A wash of colour and nothing more: no edge, so the ribbon reads as a
/// tint on the page rather than a thing laid on it.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter({required this.fill});

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final double notch = size.width * 0.45;
    final Path ribbon = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - notch)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.fill != fill;
}
