import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../domain/entities/ayah_ref.dart';

/// One ayah the reader stumbles at, with its surah's names to show it by.
class WeakSpot extends Equatable {
  const WeakSpot({required this.record, required this.surah, this.page});

  final MemorizationProgress record;
  final Surah surah;

  /// The page the ayah is printed on, in the reader's own layout; null when
  /// it could not be looked up, and then simply not said.
  final int? page;

  AyahRef get ref => AyahRef(record.surahNumber, record.ayahNumber);

  @override
  List<Object?> get props => <Object?>[record, surah, page];
}

class WeakSpotsState extends Equatable {
  const WeakSpotsState({
    this.status = LoadStatus.initial,
    this.spots = const <WeakSpot>[],
    this.errorMessage,
  });

  final LoadStatus status;

  /// The most recently marked first.
  final List<WeakSpot> spots;
  final String? errorMessage;

  @override
  List<Object?> get props => <Object?>[status, spots, errorMessage];
}

/// Every ayah the reader has said they stumble at.
class WeakSpotsCubit extends Cubit<WeakSpotsState> {
  WeakSpotsCubit({
    required QuranRepository quranRepository,
    required ProgressRepository progressRepository,
    QuranPagesRepository? pagesRepository,
  }) : _quran = quranRepository,
       _progress = progressRepository,
       _pages = pagesRepository,
       super(const WeakSpotsState());

  final QuranRepository _quran;
  final ProgressRepository _progress;
  final QuranPagesRepository? _pages;

  Future<void> load() async {
    if (state.status == LoadStatus.initial) {
      emit(const WeakSpotsState(status: LoadStatus.loading));
    }
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final Either<Failure, List<MemorizationProgress>> records = await _progress
        .stumbled();
    if (isClosed) return;

    final Failure? failure =
        surahs.fold((Failure f) => f, (_) => null) ??
        records.fold((Failure f) => f, (_) => null);
    if (failure != null) {
      emit(
        WeakSpotsState(
          status: LoadStatus.failure,
          errorMessage: failure.message,
        ),
      );
      return;
    }
    final Map<int, Surah> byNumber = <int, Surah>{
      for (final Surah s in surahs.getOrElse(() => const <Surah>[]))
        s.number: s,
    };
    final List<WeakSpot> spots = <WeakSpot>[];
    for (final MemorizationProgress r in records.getOrElse(
      () => const <MemorizationProgress>[],
    )) {
      // A record whose ayah the catalog does not hold is not shown: there
      // would be nothing to open.
      final Surah? s = byNumber[r.surahNumber];
      if (s == null || r.ayahNumber < 1 || r.ayahNumber > s.ayahCount) {
        continue;
      }
      final int? page = _pages == null
          ? null
          : (await _pages.pageForAyah(
              r.surahNumber,
              r.ayahNumber,
            )).fold((_) => null, (int p) => p);
      spots.add(WeakSpot(record: r, surah: s, page: page));
    }
    if (isClosed) return;
    emit(WeakSpotsState(status: LoadStatus.ready, spots: spots));
  }

  /// Takes the mark off one ayah.
  Future<void> clear(WeakSpot spot) async {
    await _progress.clearStumble(spot.ref.surah, spot.ref.ayah);
    await load();
  }
}
