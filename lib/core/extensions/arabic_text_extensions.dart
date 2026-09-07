import 'arabic_normalization_tables.dart';

/// Unicode NFC normalization, scoped to the Arabic blocks.
///
/// Why this exists: the same ayah can be encoded two ways that render
/// identically but compare unequal — `آ` as the precomposed U+0622 or as
/// U+0627 + U+0653, and combining marks in a different order. Anything that
/// compares ayah text (search, highlighting, validation) silently fails across
/// the two forms, and the symptom looks nothing like the cause.
///
/// Dart has no built-in normalizer and `unorm_dart` is not on the approved
/// package list (CLAUDE.md A.4), so this implements UAX #15 NFC over tables
/// generated from the UCD by `tools/gen_arabic_normalization_tables.py`.
///
/// **Scope.** The tables cover the Arabic blocks only. Codepoints outside them
/// are passed through with combining class 0, which is correct for Latin
/// letters, digits, spaces and punctuation, but would mis-order combining
/// marks from another script. Quranic text contains none, and the ayah
/// validator rejects text carrying non-Arabic combining marks
/// (see `QuranLocalDataSource`).
extension ArabicTextNormalization on String {
  /// Returns this string in Normalization Form C.
  String toArabicNfc() {
    if (isEmpty) return this;

    final List<int> decomposed = _decompose(runes);
    _canonicalOrder(decomposed);
    return String.fromCharCodes(_compose(decomposed));
  }

  /// Whether this string is already in NFC — cheaper to read at a call site
  /// than `s == s.toArabicNfc()`.
  bool get isArabicNfc => this == toArabicNfc();
}

/// Canonical combining class, defaulting to 0 outside the generated tables.
int arabicCcc(int codePoint) => arabicCombiningClass[codePoint] ?? 0;

/// Step 1: replace every precomposed codepoint with its canonical
/// decomposition. Arabic decompositions are a single level deep, but the loop
/// recurses anyway so a widened table cannot silently break this.
List<int> _decompose(Iterable<int> codePoints) {
  final List<int> out = <int>[];
  for (final int cp in codePoints) {
    final List<int>? parts = arabicCanonicalDecomposition[cp];
    if (parts == null) {
      out.add(cp);
    } else {
      out.addAll(_decompose(parts));
    }
  }
  return out;
}

/// Step 2: sort each run of combining marks by combining class, in place.
/// Marks of equal class keep their relative order, and class-0 characters
/// never move.
void _canonicalOrder(List<int> cps) {
  for (int i = 1; i < cps.length; i++) {
    final int cc = arabicCcc(cps[i]);
    if (cc == 0) continue;
    int j = i;
    while (j > 0) {
      final int prev = arabicCcc(cps[j - 1]);
      if (prev == 0 || prev <= cc) break;
      final int swap = cps[j - 1];
      cps[j - 1] = cps[j];
      cps[j] = swap;
      j--;
    }
  }
}

/// Step 3: recombine, per the UAX #15 composition algorithm. A starter absorbs
/// a following mark only when no mark of equal or higher combining class
/// stands between them.
List<int> _compose(List<int> cps) {
  if (cps.isEmpty) return cps;

  final List<int> out = <int>[cps.first];
  int starterPos = 0;
  int starterCh = cps.first;
  // A leading combining mark is not a starter, so nothing may compose onto it.
  int lastClass = arabicCcc(starterCh) == 0 ? 0 : 256;

  for (int i = 1; i < cps.length; i++) {
    final int ch = cps[i];
    final int chClass = arabicCcc(ch);
    final int? composite = arabicCanonicalComposition[starterCh]?[ch];

    if (composite != null && (lastClass == 0 || lastClass < chClass)) {
      out[starterPos] = composite;
      starterCh = composite;
      continue;
    }

    if (chClass == 0) {
      starterPos = out.length;
      starterCh = ch;
    }
    lastClass = chClass;
    out.add(ch);
  }
  return out;
}
