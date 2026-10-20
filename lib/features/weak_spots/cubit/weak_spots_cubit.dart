import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../domain/entities/ayah_ref.dart';

/// One ayah the reader stumbles at, with its surah's names to show it by.
class WeakSpot extends Equatable {
  const WeakSpot({required this.record, required this.surah});

  final MemorizationProgress record;
  final Surah surah;

  AyahRef get ref => AyahRef(record.surahNumber, record.ayahNumber);

  @override
  List<Object?> get props => <Object?>[record, surah];
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
  }) : _quran = quranRepository,
       _progress = progressRepository,
       super(const WeakSpotsState());

  final QuranRepository _quran;
  final ProgressRepository _progress;

  Future<void> load() async {
    if (state.status == LoadStatus.initial) {
      emit(const WeakSpotsState(status: LoadStatus.loading));
    }
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final Either<Failure, List<MemorizationProgress>> records = await _progress
        .stumbled();
    if (isClosed) return;

    surahs.fold(
      (Failure f) => emit(
        WeakSpotsState(status: LoadStatus.failure, errorMessage: f.message),
      ),
      (List<Surah> catalog) => records.fold(
        (Failure f) => emit(
          WeakSpotsState(status: LoadStatus.failure, errorMessage: f.message),
        ),
        (List<MemorizationProgress> list) {
          final Map<int, Surah> byNumber = <int, Surah>{
            for (final Surah s in catalog) s.number: s,
          };
          emit(
            WeakSpotsState(
              status: LoadStatus.ready,
              // A record whose ayah the catalog does not hold is not shown:
              // there would be nothing to open.
              spots: <WeakSpot>[
                for (final MemorizationProgress r in list)
                  if (byNumber[r.surahNumber] case final Surah s
                      when r.ayahNumber >= 1 && r.ayahNumber <= s.ayahCount)
                    WeakSpot(record: r, surah: s),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Takes the mark off one ayah.
  Future<void> clear(WeakSpot spot) async {
    await _progress.clearStumble(spot.ref.surah, spot.ref.ayah);
    await load();
  }
}
