import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/app_text_styles.dart';

/// How prominently an ayah is drawn within the current step.
enum AyahEmphasis {
  /// The ayah sounding right now.
  current,

  /// Inside the step's block, but not the one currently sounding.
  inBlock,

  /// Outside the current block — present for context, held back.
  context,
}

/// One ayah inside a flowing block, for [AyahText.flowing].
class FlowingAyah {
  const FlowingAyah({
    required this.number,
    required this.text,
    this.emphasis = AyahEmphasis.current,
    this.selected = false,
    this.onTap,
  });

  final int number;

  /// Verbatim ayah text, loaded from the JSON assets.
  final String text;

  final AyahEmphasis emphasis;

  /// Whether this ayah is inside the reader's selected range. Draws a tint
  /// behind the words; it does not touch the family or the size.
  final bool selected;

  final VoidCallback? onTap;
}

/// The **only** widget permitted to render Quranic text.
///
/// It hardcodes [AppTextStyles.ayah] and deliberately exposes no `style`
/// parameter and no [TextStyle] override. That is the whole point: IBM Plex
/// Sans Arabic contains U+06E1, U+0671 and the rest of the Quranic mark set,
/// so an ayah accidentally set in the UI font renders cleanly, with no tofu
/// and no error — just diacritic placement that is not the mushaf's. The
/// mistake is invisible on screen, so it is prevented structurally instead:
/// one widget, no escape hatch, and a source scan in
/// `test/core/font_enforcement_test.dart` that fails if a second renderer
/// appears.
///
/// Two constructors, one family:
///
///  * the default one renders a single ayah;
///  * [AyahText.flowing] renders a whole surah as one justified block, ayahs
///    running together with numbered end-markers the way a mushaf reads.
///
/// [AyahEmphasis] and [FlowingAyah.selected] vary colour and weight only.
/// Neither can reach the family or the size.
class AyahText extends StatefulWidget {
  const AyahText({
    required this.text,
    required this.fontSize,
    this.emphasis = AyahEmphasis.current,
    this.textAlign = TextAlign.justify,
    super.key,
  }) : ayahs = null;

  /// A whole surah as one continuous, justified block.
  ///
  /// Not a list of cards and not a column of separate [Text]s: both break the
  /// line-filling that makes a mushaf page readable, and both put a gap where
  /// scripture runs on. It is a single [Text.rich], so the paragraph justifies
  /// across ayah boundaries, while each ayah keeps its own tap target and its
  /// own emphasis.
  const AyahText.flowing({
    required List<FlowingAyah> this.ayahs,
    required this.fontSize,
    this.textAlign = TextAlign.justify,
    super.key,
  }) : text = '',
       emphasis = AyahEmphasis.current;

  /// Verbatim ayah text, loaded from the JSON assets. Never generated, never
  /// normalised, never trimmed (CLAUDE.md A.2 rule 1).
  final String text;

  /// Non-null for [AyahText.flowing].
  final List<FlowingAyah>? ayahs;

  /// The reader's chosen Arabic size, in design pixels; `.sp` is applied
  /// inside [AppTextStyles.ayah].
  final double fontSize;

  final AyahEmphasis emphasis;

  final TextAlign textAlign;

  /// The ayah number, in Arabic-Indic digits and nothing else.
  ///
  /// **Do not prepend U+06DD ARABIC END OF AYAH.** It looks like the right
  /// character — Unicode describes it as enclosing the digits that follow —
  /// but this font does not work that way, and adding it renders *two*
  /// medallions side by side: an empty one and a numbered one. That shipped
  /// once; this comment is why it will not again.
  ///
  /// Measured from the shipped face's own tables rather than assumed:
  ///
  ///   * `GSUB` lookup 36 is a ligature substitution over the Arabic-Indic
  ///     digits that maps a digit *sequence* straight to a single
  ///     pre-composed glyph — `'١٩٢'` becomes one glyph whose bounding box is
  ///     1477 x 1825 units on a 2048 em. There are 664 such glyphs, one per
  ///     ayah number. The medallion and its number are one glyph in the font.
  ///   * U+06DD is a *separate* glyph with an identical 1477 x 1825 box and a
  ///     positive advance of 1595 — the same rosette, empty, taking its own
  ///     space on the line.
  ///
  /// So the digits alone already are the numbered medallion. U+06DD is an
  /// independent ornament, not an enclosure.
  ///
  /// Deliberately not `toLocalisedString()`: the marker is part of the mushaf
  /// page, so it stays in Arabic-Indic digits even when the UI is in English,
  /// for the same reason [AyahText] hardcodes `TextDirection.rtl`.
  static String ayahNumberMarker(int number) {
    const int arabicIndicZero = 0x0660;
    final StringBuffer digits = StringBuffer();
    for (final int codeUnit in '$number'.codeUnits) {
      digits.writeCharCode(arabicIndicZero + (codeUnit - 0x30));
    }
    return digits.toString();
  }

  @override
  State<AyahText> createState() => _AyahTextState();
}

class _AyahTextState extends State<AyahText> {
  /// One recognizer per ayah, by ayah number.
  ///
  /// A [TextSpan]'s recognizer is not owned by the span, so these have to be
  /// created and disposed here; handing `TapGestureRecognizer.new` to a span
  /// inside `build` leaks one per rebuild, and rebuilds happen on every scroll
  /// frame and every tap.
  final Map<int, TapGestureRecognizer> _recognizers =
      <int, TapGestureRecognizer>{};

  @override
  void dispose() {
    for (final TapGestureRecognizer r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
    super.dispose();
  }

  /// The recognizer for [ayah], retargeted at its current callback.
  ///
  /// Retargeting rather than recreating: the callback changes identity on
  /// every rebuild (it closes over the live selection), but the recognizer
  /// itself can be reused, which keeps an in-flight tap from being dropped
  /// mid-gesture.
  GestureRecognizer? _recognizerFor(FlowingAyah ayah) {
    final VoidCallback? onTap = ayah.onTap;
    if (onTap == null) return null;
    final TapGestureRecognizer recognizer = _recognizers.putIfAbsent(
      ayah.number,
      TapGestureRecognizer.new,
    );
    recognizer.onTap = onTap;
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextStyle base = AppTextStyles.ayah(fontSize: widget.fontSize);
    final List<FlowingAyah>? flow = widget.ayahs;

    if (flow == null) {
      return Text(
        widget.text,
        textAlign: widget.textAlign,
        // Scripture is RTL regardless of the app's UI locale.
        textDirection: TextDirection.rtl,
        style: _emphasised(base, widget.emphasis, colors),
      );
    }

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final FlowingAyah ayah in flow) ...<InlineSpan>[
            TextSpan(
              text: ayah.text,
              style: _emphasised(base, ayah.emphasis, colors).copyWith(
                backgroundColor: ayah.selected
                    ? colors.primary.withValues(alpha: 0.12)
                    : null,
              ),
              recognizer: _recognizerFor(ayah),
            ),
            // The end-of-ayah medallion, numbered. Presentation, not
            // scripture: the JSON carries no markers, and the number is set in
            // Arabic-Indic digits regardless of UI locale because it is part
            // of the mushaf page, not part of the interface.
            TextSpan(
              text: ' ${AyahText.ayahNumberMarker(ayah.number)} ',
              style: base.copyWith(color: colors.primary),
              recognizer: _recognizerFor(ayah),
            ),
          ],
        ],
      ),
      textAlign: widget.textAlign,
      textDirection: TextDirection.rtl,
      style: base,
    );
  }

  static TextStyle _emphasised(
    TextStyle base,
    AyahEmphasis emphasis,
    ColorScheme colors,
  ) => base.copyWith(
    color: switch (emphasis) {
      AyahEmphasis.current => colors.onSurface,
      AyahEmphasis.inBlock => colors.onSurface.withValues(alpha: 0.9),
      AyahEmphasis.context => colors.onSurface.withValues(alpha: 0.55),
    },
    fontWeight: emphasis == AyahEmphasis.current
        ? FontWeight.w600
        : FontWeight.w400,
  );

}
