/// How much there is to pronounce in a piece of Quranic text, in letter-units.
///
/// The aligner asks one thing of the text: roughly how long should this ayah
/// take? A bare letter count answers that well for ordinary words and badly
/// for two things, both of which the text marks itself:
///
///  * **A word with no vowel marks at all is a run of letter names.** The
///    muqatta'at — `الٓمٓ`, `كٓهيعٓصٓ` — are five characters and eleven seconds:
///    each letter is recited as its name, and the ones under a maddah are held. Counted as ordinary letters
///    they are expected to take a second, the cut after them lands early, and
///    the next ayah is left a fragment. Every vowelled word in this text
///    carries harakat, so their absence identifies these words with no list of
///    surahs anywhere (CLAUDE.md A.2 rule 2).
///  * **A maddah sign marks a vowel held for several counts.**
///
/// The text is only read, never changed (A.2 rule 1): this counts code points
/// and returns a number.
int recitationWeight(String text) {
  int total = 0;
  for (final String word in text.split(RegExp(r'\s+'))) {
    int letters = 0;
    int maddahs = 0;
    bool vowelled = false;
    for (final int rune in word.runes) {
      if (rune >= 0x0621 && rune <= 0x064A) letters++;
      if (rune >= 0x064B && rune <= 0x0652) vowelled = true;
      if (rune == 0x0653) maddahs++;
    }
    if (letters == 0) continue;
    total += vowelled
        ? letters + _countsPerMaddah * maddahs
        : letters * _unitsPerLetterName + _unitsPerHeldName * maddahs;
  }
  return total;
}

/// A letter recited as its name — `طه` is "ṭā hā", about a second each.
const int _unitsPerLetterName = 3;

/// What a maddah adds to a letter name. The text marks which names are held:
/// in `كٓهيعٓصٓ` the kaf, 'ayn and sad carry the sign and run six counts, the
/// ha and ya do not and run two. Treating every name as held made `طه` — no
/// maddah at all, two seconds long — look like a five-second ayah cut short.
const int _unitsPerHeldName = 5;

/// The extra length of a held vowel, in letters.
const int _countsPerMaddah = 3;

/// The isti'adhah's length, in the same letter-units.
///
/// A constant because it has to be: the isti'adhah is not Quranic text and has
/// no row in `quran.db` to be measured from. It only sizes a segment that is
/// cut and thrown away, so it needs to be roughly right, not exact.
const int kIstiadhahWeight = 24;

/// One weight per segment a recording is expected to split into, in the order
/// they are recited: the isti'adhah if the recording has one, the basmala if
/// it has one, then every ayah.
///
/// [basmalaText] is Al-Fatiha 1:1 out of `quran.db` — the basmala's words are
/// in the catalog, not in a constant here.
List<int> segmentWeights({
  required List<String> ayahTexts,
  required String basmalaText,
  required bool hasBasmala,
  required bool hasIstiadhah,
}) => <int>[
  if (hasIstiadhah) kIstiadhahWeight,
  if (hasBasmala) recitationWeight(basmalaText),
  for (final String text in ayahTexts) recitationWeight(text),
];
