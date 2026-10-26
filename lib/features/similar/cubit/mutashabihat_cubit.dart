import 'package:dartz/dartz.dart' hide State;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/mutashabihat.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../../data/repositories/mutashabihat_repository.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../domain/entities/ayah_ref.dart';

/// One shared phrase as the list shows it: where it occurs, and in which
/// surahs.
class PhraseEntry extends Equatable {
  const PhraseEntry({
    required this.id,
    required this.occurrences,
    required this.surahs,
  });

  final int id;

  /// In mushaf order; never empty.
  final List<PhraseOccurrence> occurrences;

  /// Every surah it occurs in, in mushaf order.
  final List<Surah> surahs;

  PhraseOccurrence get first => occurrences.first;

  int get ayahCount =>
      occurrences.map((PhraseOccurrence o) => o.ref).toSet().length;

  bool occursIn(int surah) => surahs.any((Surah s) => s.number == surah);

  @override
  List<Object?> get props => <Object?>[id, occurrences, surahs];
}

class MutashabihatState extends Equatable {
  const MutashabihatState({
    this.status = LoadStatus.initial,
    this.entries = const <PhraseEntry>[],
    this.surahFilter,
    this.errorMessage,
  });

  final LoadStatus status;

  /// Every phrase, in the order the mushaf first reaches it.
  final List<PhraseEntry> entries;

  /// Only the phrases found in this surah, when set.
  final int? surahFilter;
  final String? errorMessage;

  List<PhraseEntry> get shown {
    final int? only = surahFilter;
    if (only == null) return entries;
    return <PhraseEntry>[
      for (final PhraseEntry e in entries)
        if (e.occursIn(only)) e,
    ];
  }

  /// The surahs any phrase occurs in, in mushaf order: what the filter offers.
  List<Surah> get surahs {
    final Map<int, Surah> seen = <int, Surah>{
      for (final PhraseEntry e in entries)
        for (final Surah s in e.surahs) s.number: s,
    };
    final List<int> numbers = seen.keys.toList()..sort();
    return <Surah>[for (final int n in numbers) seen[n]!];
  }

  MutashabihatState copyWith({
    LoadStatus? status,
    List<PhraseEntry>? entries,
    int? surahFilter,
    bool clearSurahFilter = false,
    String? errorMessage,
  }) => MutashabihatState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    surahFilter: clearSurahFilter ? null : surahFilter ?? this.surahFilter,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    entries,
    surahFilter,
    errorMessage,
  ];
}

/// Every phrase the mushaf repeats across its ayahs — the mutashabihat —
/// as a list to browse, and to narrow to one surah.
class MutashabihatCubit extends Cubit<MutashabihatState> {
  MutashabihatCubit({
    required MutashabihatRepository mutashabihatRepository,
    required QuranRepository quranRepository,
    required QuranPagesRepository pagesRepository,
  }) : _index = mutashabihatRepository,
       _quran = quranRepository,
       _pages = pagesRepository,
       super(const MutashabihatState());

  final MutashabihatRepository _index;
  final QuranRepository _quran;
  final QuranPagesRepository _pages;

  /// A phrase's words, read once each: a long list scrolled back and forth
  /// asks for the same card many times.
  final Map<int, Future<List<Word>>> _words = <int, Future<List<Word>>>{};

  Future<void> load() async {
    emit(const MutashabihatState(status: LoadStatus.loading));
    final MutashabihatIndex index = await _index.index();
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    if (isClosed) return;
    final Map<int, Surah> byNumber = <int, Surah>{
      for (final Surah s in surahs.getOrElse(() => const <Surah>[]))
        s.number: s,
    };
    if (byNumber.isEmpty) {
      emit(
        MutashabihatState(
          status: LoadStatus.failure,
          errorMessage: surahs.fold((Failure f) => f.message, (_) => null),
        ),
      );
      return;
    }

    final List<PhraseEntry> entries = <PhraseEntry>[];
    for (final int id in index.phraseIds) {
      final List<PhraseOccurrence> occurrences = index.occurrencesOf(id);
      final List<Surah> inSurahs = <Surah>[
        for (final int n
            in occurrences.map((PhraseOccurrence o) => o.ref.surah).toSet())
          ?byNumber[n],
      ];
      // A phrase pointing at a surah the catalog does not have is left out
      // whole, never shown with a gap.
      if (inSurahs.length !=
          occurrences.map((PhraseOccurrence o) => o.ref.surah).toSet().length) {
        continue;
      }
      entries.add(
        PhraseEntry(id: id, occurrences: occurrences, surahs: inSurahs),
      );
    }
    emit(MutashabihatState(status: LoadStatus.ready, entries: entries));
  }

  void filterBySurah(int? surah) => emit(
    surah == null
        ? state.copyWith(clearSurahFilter: true)
        : state.copyWith(surahFilter: surah),
  );

  /// The words of [entry] where the mushaf first reaches it, from
  /// `quran.db`, untouched; empty if they cannot be read.
  Future<List<Word>> wordsOf(PhraseEntry entry) =>
      _words[entry.id] ??= phraseWords(_pages, entry.first);

  /// The words [occurrence] covers, ayah-number markers left out.
  static Future<List<Word>> phraseWords(
    QuranPagesRepository pages,
    PhraseOccurrence occurrence,
  ) async {
    final AyahRef at = occurrence.ref;
    final List<Word> words = (await pages.wordsForAyah(
      at.surah,
      at.ayah,
    )).getOrElse(() => const <Word>[]);
    final List<Word> covered = <Word>[
      for (final Word w in words)
        if (!w.isMarker && occurrence.covers(w.position)) w,
    ];
    // All of it or nothing: a phrase shown short is a different phrase.
    return covered.length == occurrence.length ? covered : const <Word>[];
  }
}
