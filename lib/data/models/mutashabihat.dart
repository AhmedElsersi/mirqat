import 'package:equatable/equatable.dart';

import '../../domain/entities/ayah_ref.dart';

/// One place a shared phrase occurs: an ayah, and the words of it the phrase
/// covers, 1-based and inclusive, counting recited words only.
class PhraseOccurrence extends Equatable {
  const PhraseOccurrence({
    required this.phraseId,
    required this.ref,
    required this.fromWord,
    required this.toWord,
  });

  final int phraseId;
  final AyahRef ref;
  final int fromWord;
  final int toWord;

  int get length => toWord - fromWord + 1;

  bool covers(int position) => position >= fromWord && position <= toWord;

  @override
  List<Object?> get props => <Object?>[phraseId, ref, fromWord, toWord];
}

/// An ayah that shares at least one phrase with another, and where.
class SimilarAyah extends Equatable {
  const SimilarAyah({
    required this.ref,
    required this.here,
    required this.there,
  });

  /// The similar ayah.
  final AyahRef ref;

  /// The shared phrases as they fall in the ayah being compared from.
  final List<PhraseOccurrence> here;

  /// The same phrases as they fall in [ref].
  final List<PhraseOccurrence> there;

  /// The longest phrase the two share, in words — how alike they are.
  int get longest =>
      there.fold(0, (int m, PhraseOccurrence o) => o.length > m ? o.length : m);

  @override
  List<Object?> get props => <Object?>[ref, here, there];
}

/// Every shared phrase, indexed by the ayahs it occurs in.
///
/// References only — an ayah and a word range — never text: the words are
/// always drawn from `quran.db`. Read forgivingly: a row that cannot be read
/// is skipped, and a file of another schema reads as nothing at all, so a
/// bad import hides the feature rather than showing wrong pairs.
class MutashabihatIndex {
  MutashabihatIndex._(this._byAyah, this._byPhrase);

  static final MutashabihatIndex empty = MutashabihatIndex._(
    const <AyahRef, List<PhraseOccurrence>>{},
    const <int, List<PhraseOccurrence>>{},
  );

  static const int schemaVersion = 1;

  final Map<AyahRef, List<PhraseOccurrence>> _byAyah;
  final Map<int, List<PhraseOccurrence>> _byPhrase;

  bool get isEmpty => _byPhrase.isEmpty;

  factory MutashabihatIndex.fromJson(Object? json) {
    if (json is! Map || json['schemaVersion'] != schemaVersion) return empty;
    final Object? phrases = json['phrases'];
    if (phrases is! List) return empty;

    final Map<AyahRef, List<PhraseOccurrence>> byAyah =
        <AyahRef, List<PhraseOccurrence>>{};
    final Map<int, List<PhraseOccurrence>> byPhrase =
        <int, List<PhraseOccurrence>>{};
    for (final Object? phrase in phrases) {
      if (phrase is! Map) continue;
      final Object? id = phrase['id'];
      final Object? rows = phrase['ayahs'];
      if (id is! int || rows is! List) continue;
      final List<PhraseOccurrence> occurrences = <PhraseOccurrence>[
        for (final Object? row in rows) ?_occurrence(id, row),
      ];
      // A phrase in one ayah alone is shared with nothing.
      if (occurrences.map((PhraseOccurrence o) => o.ref).toSet().length < 2) {
        continue;
      }
      byPhrase[id] = occurrences;
      for (final PhraseOccurrence o in occurrences) {
        (byAyah[o.ref] ??= <PhraseOccurrence>[]).add(o);
      }
    }
    return MutashabihatIndex._(byAyah, byPhrase);
  }

  static PhraseOccurrence? _occurrence(int id, Object? row) {
    if (row is! List || row.length != 4) return null;
    if (!row.every((Object? x) => x is int && x >= 1)) return null;
    final List<int> r = row.cast<int>();
    if (r[2] > r[3]) return null;
    return PhraseOccurrence(
      phraseId: id,
      ref: AyahRef(r[0], r[1]),
      fromWord: r[2],
      toWord: r[3],
    );
  }

  bool hasSimilar(AyahRef ref) => _byAyah.containsKey(ref);

  /// Every phrase, in the order the mushaf first reaches it — by its
  /// earliest ayah, then by where in that ayah it starts.
  List<int> get phraseIds {
    final Map<int, PhraseOccurrence> first = <int, PhraseOccurrence>{
      for (final int id in _byPhrase.keys) id: occurrencesOf(id).first,
    };
    final List<int> ids = _byPhrase.keys.toList();
    ids.sort((int a, int b) {
      final PhraseOccurrence x = first[a]!;
      final PhraseOccurrence y = first[b]!;
      final int byRef = x.ref.compareTo(y.ref);
      if (byRef != 0) return byRef;
      final int byWord = x.fromWord - y.fromWord;
      return byWord != 0 ? byWord : a - b;
    });
    return ids;
  }

  /// Where the phrase [id] occurs, in mushaf order; empty for a phrase the
  /// index does not hold.
  List<PhraseOccurrence> occurrencesOf(int id) {
    final List<PhraseOccurrence> out = List<PhraseOccurrence>.of(
      _byPhrase[id] ?? const <PhraseOccurrence>[],
    );
    out.sort((PhraseOccurrence a, PhraseOccurrence b) {
      final int byRef = a.ref.compareTo(b.ref);
      return byRef != 0 ? byRef : a.fromWord - b.fromWord;
    });
    return out;
  }

  /// The phrases of [ref] that are shared with some other ayah.
  List<PhraseOccurrence> phrasesIn(AyahRef ref) =>
      _byAyah[ref] ?? const <PhraseOccurrence>[];

  /// Every ayah sharing a phrase with [ref]: the most alike first — by the
  /// longest phrase shared, then by how many — then in mushaf order.
  List<SimilarAyah> similarTo(AyahRef ref) {
    final Map<AyahRef, List<PhraseOccurrence>> here =
        <AyahRef, List<PhraseOccurrence>>{};
    final Map<AyahRef, List<PhraseOccurrence>> there =
        <AyahRef, List<PhraseOccurrence>>{};
    for (final PhraseOccurrence mine in phrasesIn(ref)) {
      for (final PhraseOccurrence other
          in _byPhrase[mine.phraseId] ?? const <PhraseOccurrence>[]) {
        if (other.ref == ref) continue;
        final List<PhraseOccurrence> h = here[other.ref] ??=
            <PhraseOccurrence>[];
        if (!h.contains(mine)) h.add(mine);
        final List<PhraseOccurrence> t = there[other.ref] ??=
            <PhraseOccurrence>[];
        if (!t.contains(other)) t.add(other);
      }
    }
    final List<SimilarAyah> out = <SimilarAyah>[
      for (final AyahRef r in there.keys)
        SimilarAyah(ref: r, here: here[r]!, there: there[r]!),
    ];
    out.sort((SimilarAyah a, SimilarAyah b) {
      final int byLength = b.longest - a.longest;
      if (byLength != 0) return byLength;
      final int byCount = b.there.length - a.there.length;
      if (byCount != 0) return byCount;
      return a.ref.compareTo(b.ref);
    });
    return out;
  }
}
