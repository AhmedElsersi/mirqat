import '../../core/error/exceptions.dart';
import '../models/ayah.dart';
import '../models/surah.dart';

/// Shared by every `QuranLocalDataSource` implementation, JSON- or
/// database-backed alike: the numbers must be a contiguous 1..`ayahCount`
/// run — no duplicates, no gaps, nothing beyond the end, in ascending order
/// — the count must equal the catalog's, and the text must be Arabic-only.
/// Never repaired silently (CLAUDE.md A.2 rule 1).
///
/// Checks run in the order that yields the most useful message: a source
/// holding six ayahs where the catalog declares seven is more helpfully
/// reported as "missing ayah 7" than as a bare count mismatch.
void validateAyahSequence(
  List<Ayah> ayahs, {
  required Surah surah,
  required String path,
}) {
  final Set<int> seen = <int>{};
  for (final Ayah ayah in ayahs) {
    if (!seen.add(ayah.number)) {
      throw CatalogValidationException(
        path,
        'Surah ${surah.number} lists ayah ${ayah.number} more than once.',
      );
    }
  }

  for (final Ayah ayah in ayahs) {
    if (ayah.number > surah.ayahCount) {
      throw CatalogValidationException(
        path,
        'Surah ${surah.number} has ayah ${ayah.number}, beyond the '
        'ayahCount of ${surah.ayahCount} the catalog declares.',
      );
    }
  }

  for (int expected = 1; expected <= surah.ayahCount; expected++) {
    if (!seen.contains(expected)) {
      throw CatalogValidationException(
        path,
        'Surah ${surah.number} (${surah.nameEn}) is missing ayah $expected — '
        'the numbers must be a contiguous 1..${surah.ayahCount} sequence. '
        'Supply the missing text; it is never generated.',
      );
    }
  }

  // Implied by the three checks above, and kept as a net in case one of them
  // is ever loosened.
  if (ayahs.length != surah.ayahCount) {
    throw CatalogValidationException(
      path,
      'Surah ${surah.number} (${surah.nameEn}) declares ayahCount '
      '${surah.ayahCount} in the catalog, but the ayah source holds '
      '${ayahs.length}.',
    );
  }

  for (int i = 0; i < ayahs.length; i++) {
    if (ayahs[i].number != i + 1) {
      throw CatalogValidationException(
        path,
        'Surah ${surah.number} lists its ayahs out of order: position '
        '${i + 1} holds ayah ${ayahs[i].number}.',
      );
    }
  }

  for (final Ayah ayah in ayahs) {
    _assertArabicOnly(ayah, path);
  }
}

/// Rejects text carrying a character from outside the Arabic blocks — a sign
/// the source was decoded or exported wrongly. A check, never a repair: the
/// text itself is not touched.
void _assertArabicOnly(Ayah ayah, String path) {
  for (final int cp in ayah.text.runes) {
    if (_isArabicRange(cp) || _isAllowedNonArabic(cp)) continue;
    throw CatalogValidationException(
      path,
      'Ayah ${ayah.surahNumber}:${ayah.number} contains U+'
      '${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}, which is '
      'outside the Arabic blocks — check the source encoding.',
    );
  }
}

bool _isArabicRange(int cp) =>
    (cp >= 0x0600 && cp <= 0x06FF) ||
    (cp >= 0x0750 && cp <= 0x077F) ||
    (cp >= 0x0870 && cp <= 0x089F) ||
    (cp >= 0x08A0 && cp <= 0x08FF) ||
    (cp >= 0xFB50 && cp <= 0xFDFF) ||
    (cp >= 0xFE70 && cp <= 0xFEFF);

/// Space, and the zero-width joiners that Arabic typography sometimes uses.
bool _isAllowedNonArabic(int cp) =>
    cp == 0x0020 || cp == 0x200C || cp == 0x200D;
