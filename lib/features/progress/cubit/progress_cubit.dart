import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import 'progress_state.dart';

class ProgressCubit extends Cubit<ProgressScreenState> {
  ProgressCubit({
    required QuranRepository quranRepository,
    required ProgressRepository progressRepository,
  }) : _quran = quranRepository,
       _progress = progressRepository,
       super(const ProgressScreenState());

  final QuranRepository _quran;
  final ProgressRepository _progress;

  Future<void> load(int surahNumber) async {
    emit(state.copyWith(status: LoadStatus.loading));

    final surahResult = await _quran.getSurah(surahNumber);
    await surahResult.fold(
      (Failure f) async => emit(
        state.copyWith(status: LoadStatus.failure, errorMessage: f.message),
      ),
      (Surah surah) async {
        final records = await _progress.getSurah(surah.number, surah.ayahCount);
        records.fold(
          (Failure f) => emit(
            state.copyWith(status: LoadStatus.failure, errorMessage: f.message),
          ),
          (List<MemorizationProgress> list) => emit(
            ProgressScreenState(
              status: LoadStatus.ready,
              surah: surah,
              records: list,
            ),
          ),
        );
      },
    );
  }

  /// Marks an ayah memorized, or takes the mark back off.
  Future<void> toggleMemorized(int ayahNumber) async {
    final Surah? surah = state.surah;
    if (surah == null) return;

    final MemorizationProgress current = state.records.firstWhere(
      (MemorizationProgress p) => p.ayahNumber == ayahNumber,
    );

    // Un-marking returns the ayah to inProgress when it has been drilled
    // before, so the history is not thrown away.
    final MemorizationStatus next =
        current.status == MemorizationStatus.memorized
        ? (current.cumulativeRepeats > 0
              ? MemorizationStatus.inProgress
              : MemorizationStatus.notStarted)
        : MemorizationStatus.memorized;

    await _progress.setStatus(surah.number, ayahNumber, next);
    await load(surah.number);
  }
}
