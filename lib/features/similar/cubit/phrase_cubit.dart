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
import 'mutashabihat_cubit.dart';
import 'similar_cubit.dart';

/// The ayahs of one surah that hold the phrase.
class PhraseGroup extends Equatable {
  const PhraseGroup({required this.surah, required this.ayahs});

  final Surah surah;

  /// In mushaf order.
  final List<ComparedAyah> ayahs;

  @override
  List<Object?> get props => <Object?>[surah, ayahs];
}

class PhraseState extends Equatable {
  const PhraseState({
    this.status = LoadStatus.initial,
    this.words = const <Word>[],
    this.groups = const <PhraseGroup>[],
    this.errorMessage,
  });

  final LoadStatus status;

  /// The phrase where the mushaf first reaches it.
  final List<Word> words;

  /// Every surah it occurs in, in mushaf order.
  final List<PhraseGroup> groups;
  final String? errorMessage;

  int get ayahCount =>
      groups.fold(0, (int n, PhraseGroup g) => n + g.ayahs.length);

  @override
  List<Object?> get props => <Object?>[status, words, groups, errorMessage];
}

/// One shared phrase, and every ayah it occurs in, surah by surah, with its
/// words marked in each.
class PhraseCubit extends Cubit<PhraseState> {
  PhraseCubit({
    required MutashabihatRepository mutashabihatRepository,
    required QuranRepository quranRepository,
    required QuranPagesRepository pagesRepository,
  }) : _index = mutashabihatRepository,
       _quran = quranRepository,
       _pages = pagesRepository,
       super(const PhraseState());

  final MutashabihatRepository _index;
  final QuranRepository _quran;
  final QuranPagesRepository _pages;

  Future<void> load(int phraseId) async {
    emit(const PhraseState(status: LoadStatus.loading));
    final MutashabihatIndex index = await _index.index();
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final Map<int, Surah> byNumber = <int, Surah>{
      for (final Surah s in surahs.getOrElse(() => const <Surah>[]))
        s.number: s,
    };

    // An ayah may hold the phrase more than once; it is one card, with
    // every occurrence marked.
    final Map<AyahRef, List<PhraseOccurrence>> byAyah =
        <AyahRef, List<PhraseOccurrence>>{};
    for (final PhraseOccurrence o in index.occurrencesOf(phraseId)) {
      (byAyah[o.ref] ??= <PhraseOccurrence>[]).add(o);
    }

    final List<PhraseGroup> groups = <PhraseGroup>[];
    for (final MapEntry<AyahRef, List<PhraseOccurrence>> e in byAyah.entries) {
      final ComparedAyah? ayah = await ComparedAyah.load(
        _pages,
        byNumber,
        e.key,
        e.value,
      );
      if (ayah == null) continue;
      if (groups.isNotEmpty && groups.last.surah.number == ayah.surah.number) {
        groups.last.ayahs.add(ayah);
      } else {
        groups.add(PhraseGroup(surah: ayah.surah, ayahs: <ComparedAyah>[ayah]));
      }
    }
    final List<Word> words = byAyah.isEmpty
        ? const <Word>[]
        : await MutashabihatCubit.phraseWords(
            _pages,
            byAyah.values.first.first,
          );
    if (isClosed) return;

    // Fewer than two ayahs is not a comparison: the phrase is unknown, or
    // its ayahs could not be read.
    final int ayahs = groups.fold(
      0,
      (int n, PhraseGroup g) => n + g.ayahs.length,
    );
    if (ayahs < 2) {
      emit(
        PhraseState(
          status: LoadStatus.failure,
          errorMessage: surahs.fold((Failure f) => f.message, (_) => null),
        ),
      );
      return;
    }
    emit(PhraseState(status: LoadStatus.ready, words: words, groups: groups));
  }
}
