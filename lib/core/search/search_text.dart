/// What a typed search becomes before it is compared.
///
/// Quranic text is NEVER passed through this (CLAUDE.md A.2 rule 1). The
/// ayah side of every comparison is `quran.db`'s `text_search` column,
/// computed at build time by `searchable()` in `tool/build_quran_data.py`
/// from the final text — the `text` column itself is untouched and is the
/// only thing ever rendered. This function applies the SAME rules to what
/// the user types (and to surah names, which are labels, not scripture), so
/// that the two sides meet in the middle.
/// `test/core/search_text_db_test.dart` asserts the two implementations
/// agree on every ayah of the built database — change one, change both.
///
/// Rules, per character:
///  * the alef family and the hamza (ا أ إ آ ٱ ء) are dropped outright: the
///    Uthmani rasm writes them where modern typing does not (العالمين is
///    written ٱلۡعَٰلَمِين, قرآن is written قُرۡءَان), so they cannot be
///    matched on;
///  * ؤ becomes و, ئ and ى become ي, and ة becomes ه — the pairs people type
///    interchangeably;
///  * every other Arabic letter (U+0621..U+064A) stays as it is;
///  * whitespace collapses to a single space;
///  * everything else — diacritics, Quranic annotation marks, superscript
///    letters, tatweel, digits, Latin — is dropped.
String searchableQuery(String input) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.runes) {
    switch (rune) {
      // The alef family and the hamza: dropped.
      case 0x0621 || 0x0622 || 0x0623 || 0x0625 || 0x0627 || 0x0671:
        break;
      case 0x0624: // ؤ
        out.write('و');
      case 0x0626 || 0x0649: // ئ ى
        out.write('ي');
      case 0x0629: // ة
        out.write('ه');
      default:
        if (rune >= 0x0621 && rune <= 0x064A) {
          out.writeCharCode(rune);
        } else if (_isWhitespace(rune)) {
          out.write(' ');
        }
    }
  }
  return out.toString().replaceAll(_spaces, ' ').trim();
}

final RegExp _spaces = RegExp(r'\s+');

/// Mirrors Python's `str.isspace()` for the characters a query can
/// plausibly hold.
bool _isWhitespace(int rune) =>
    rune == 0x20 ||
    (rune >= 0x09 && rune <= 0x0D) ||
    rune == 0x85 ||
    rune == 0xA0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000;

/// The page number a search asks for, or null when the query is not one.
///
/// Reads Western (123) and Arabic-Indic (١٢٣) digits, whole-query only: a
/// number buried in words is a word search, not a page request.
int? pageNumberQuery(String input) {
  final String trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final StringBuffer digits = StringBuffer();
  for (final int rune in trimmed.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      digits.writeCharCode(rune);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      // Arabic-Indic ٠..٩
      digits.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      // Extended Arabic-Indic ۰..۹
      digits.writeCharCode(0x30 + rune - 0x06F0);
    } else {
      return null;
    }
  }
  return int.tryParse(digits.toString());
}
