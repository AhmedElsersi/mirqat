import 'package:equatable/equatable.dart';

/// Where a juz begins: read out of `quran.db`, never written down here
/// (CLAUDE.md A.2 rule 2).
class JuzInfo extends Equatable {
  const JuzInfo({
    required this.number,
    required this.surahNumber,
    required this.ayahNumber,
    required this.page,
  });

  final int number;
  final int surahNumber;
  final int ayahNumber;
  final int page;

  @override
  List<Object?> get props => <Object?>[number, surahNumber, ayahNumber, page];
}

/// The juz a surah begins in and the one it ends in, from the juz starts
/// [juzs] (any order). Null for an empty list.
({int first, int last})? juzSpan(List<JuzInfo> juzs, int surah, int ayahCount) {
  if (juzs.isEmpty) return null;
  final List<JuzInfo> starts = List<JuzInfo>.of(juzs)
    ..sort((JuzInfo a, JuzInfo b) => a.number - b.number);
  int juzOf(int ayah) {
    int found = starts.first.number;
    for (final JuzInfo j in starts) {
      final bool begun =
          j.surahNumber < surah ||
          (j.surahNumber == surah && j.ayahNumber <= ayah);
      if (!begun) break;
      found = j.number;
    }
    return found;
  }

  return (first: juzOf(1), last: juzOf(ayahCount));
}
