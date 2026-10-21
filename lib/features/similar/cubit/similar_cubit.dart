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

/// One ayah as the comparison shows it: its words from `quran.db`, and which
/// of them belong to a phrase it shares.
class ComparedAyah extends Equatable {
  const ComparedAyah({
    required this.ref,
    required this.surah,
    required this.words,
    required this.shared,
  });

  final AyahRef ref;
  final Surah surah;

  /// Every word of the ayah, its marker last, in order.
  final List<Word> words;

  /// The phrases shared, as they fall in this ayah.
  final List<PhraseOccurrence> shared;

  bool isShared(Word w) =>
      !w.isMarker && shared.any((PhraseOccurrence o) => o.covers(w.position));

  @override
  List<Object?> get props => <Object?>[ref, surah, words, shared];
}

class SimilarState extends Equatable {
  const SimilarState({
    this.status = LoadStatus.initial,
    this.target,
    this.similar = const <ComparedAyah>[],
    this.errorMessage,
  });

  final LoadStatus status;
  final ComparedAyah? target;

  /// The most alike first.
  final List<ComparedAyah> similar;
  final String? errorMessage;

  @override
  List<Object?> get props => <Object?>[status, target, similar, errorMessage];
}

/// An ayah beside the ayahs it is easily confused with.
class SimilarCubit extends Cubit<SimilarState> {
  SimilarCubit({
    required MutashabihatRepository mutashabihatRepository,
    required QuranRepository quranRepository,
    required QuranPagesRepository pagesRepository,
  }) : _index = mutashabihatRepository,
       _quran = quranRepository,
       _pages = pagesRepository,
       super(const SimilarState());

  final MutashabihatRepository _index;
  final QuranRepository _quran;
  final QuranPagesRepository _pages;

  /// More than this and the page is a concordance, not a comparison. The
  /// most alike come first, so it is the least alike that are left out.
  static const int limit = 30;

  Future<void> load(AyahRef ref) async {
    emit(const SimilarState(status: LoadStatus.loading));
    final MutashabihatIndex index = await _index.index();
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final Map<int, Surah> byNumber = <int, Surah>{
      for (final Surah s in surahs.getOrElse(() => const <Surah>[]))
        s.number: s,
    };

    Future<ComparedAyah?> compared(
      AyahRef r,
      List<PhraseOccurrence> shared,
    ) async {
      final Surah? surah = byNumber[r.surah];
      if (surah == null) return null;
      final List<Word> words = (await _pages.wordsForAyah(
        r.surah,
        r.ayah,
      )).getOrElse(() => const <Word>[]);
      // An ayah whose words cannot be read is not shown, never shown short.
      if (words.isEmpty) return null;
      return ComparedAyah(ref: r, surah: surah, words: words, shared: shared);
    }

    final ComparedAyah? target = await compared(ref, index.phrasesIn(ref));
    if (isClosed) return;
    if (target == null) {
      emit(
        SimilarState(
          status: LoadStatus.failure,
          errorMessage: surahs.fold((Failure f) => f.message, (_) => null),
        ),
      );
      return;
    }

    final List<ComparedAyah> similar = <ComparedAyah>[];
    for (final SimilarAyah s in index.similarTo(ref).take(limit)) {
      final ComparedAyah? c = await compared(s.ref, s.there);
      if (c != null) similar.add(c);
    }
    if (isClosed) return;
    emit(
      SimilarState(status: LoadStatus.ready, target: target, similar: similar),
    );
  }
}
