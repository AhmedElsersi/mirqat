import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/widgets/ayah_text.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/surah.dart';

/// The surah as a mushaf page: one continuous, justified block of text with
/// numbered end-markers, not a list of cards.
///
/// The bismillah is catalog-driven, never surah-driven. For
/// [BismillahMode.separatePreamble] it is an unnumbered header above ayah 1;
/// for [BismillahMode.countedAsAyah1] it already *is* ayah 1 and no header is
/// drawn, because drawing one would show the same words twice; for
/// [BismillahMode.none] there is nothing to draw. Nothing here asks which
/// surah it is looking at.
///
/// [bismillahText] arrives from the cubit, read out of quran.db. It is
/// never a literal in this file: the basmala is Quranic text, so it is loaded
/// verbatim like everything else (CLAUDE.md A.2 rule 1). Null means the
/// catalog offered no verbatim source, and the header is then simply not
/// drawn — showing nothing is correct, inventing the words is not.
class SurahReadingView extends StatelessWidget {
  const SurahReadingView({
    required this.surah,
    required this.ayahs,
    required this.fontSize,
    required this.bismillahText,
    required this.isSelected,
    required this.onAyahTap,
    required this.scrollController,
    super.key,
  });

  final Surah surah;
  final List<Ayah> ayahs;
  final double fontSize;

  /// The basmala, verbatim from quran.db, or null when none was found.
  final String? bismillahText;

  final bool Function(int ayahNumber) isSelected;
  final ValueChanged<int> onAyahTap;

  /// Held by the screen, not created here, so scroll position survives the
  /// drawer opening and closing.
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final bool anySelected = ayahs.any((Ayah a) => isSelected(a.number));

    return SingleChildScrollView(
      controller: scrollController,
      padding: EdgeInsetsDirectional.symmetric(horizontal: 20.w, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (surah.needsBismillahPreamble && bismillahText != null)
            _BismillahHeader(text: bismillahText!, fontSize: fontSize),
          AyahText.flowing(
            fontSize: fontSize,
            ayahs: <FlowingAyah>[
              for (final Ayah ayah in ayahs)
                FlowingAyah(
                  number: ayah.number,
                  // Byte-for-byte from quran.db (CLAUDE.md A.2 rule 1).
                  text: ayah.text,
                  selected: isSelected(ayah.number),
                  // With nothing selected the whole surah is in play, so every
                  // ayah reads at full strength. Once a range exists, the rest
                  // of the page steps back rather than disappearing.
                  emphasis: !anySelected || isSelected(ayah.number)
                      ? AyahEmphasis.current
                      : AyahEmphasis.context,
                  onTap: () => onAyahTap(ayah.number),
                ),
            ],
          ),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }
}

/// The standalone bismillah, for surahs that recite it without numbering it.
///
/// Rendered through [AyahText] like every other piece of Quranic text.
class _BismillahHeader extends StatelessWidget {
  const _BismillahHeader({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(top: 8.h, bottom: 16.h),
      child: AyahText(
        text: text,
        // A shade smaller than the body: it is a header over the surah, and at
        // full size it competes with ayah 1 for the eye.
        fontSize: fontSize * 0.9,
        textAlign: TextAlign.center,
      ),
    );
  }
}
