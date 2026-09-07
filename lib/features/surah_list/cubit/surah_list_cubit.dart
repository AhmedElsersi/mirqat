import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import 'surah_list_state.dart';

/// Lists whatever is in the catalog — no placeholders for surahs that are not
/// (CLAUDE.md / Part B, Phase 4).
class SurahListCubit extends Cubit<SurahListState> {
  SurahListCubit({
    required QuranRepository quranRepository,
    required ProgressRepository progressRepository,
  }) : _quran = quranRepository,
       _progress = progressRepository,
       super(const SurahListState());

  final QuranRepository _quran;
  final ProgressRepository _progress;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    final result = await _quran.getSurahs();

    await result.fold(
      (Failure failure) async => emit(
        state.copyWith(
          status: LoadStatus.failure,
          errorMessage: failure.message,
        ),
      ),
      (List<Surah> surahs) async {
        final List<SurahListItem> items = <SurahListItem>[];

        for (final Surah surah in surahs) {
          final progress = await _progress.getSurah(
            surah.number,
            surah.ayahCount,
          );

          items.add(
            progress.fold(
              // A progress read that fails should not hide the surah; the row
              // just shows no progress.
              (_) => SurahListItem(
                surah: surah,
                memorizedCount: 0,
                inProgressCount: 0,
              ),
              (List<MemorizationProgress> records) => SurahListItem(
                surah: surah,
                memorizedCount: records
                    .where(
                      (MemorizationProgress p) =>
                          p.status == MemorizationStatus.memorized,
                    )
                    .length,
                inProgressCount: records
                    .where(
                      (MemorizationProgress p) =>
                          p.status == MemorizationStatus.inProgress,
                    )
                    .length,
              ),
            ),
          );
        }

        emit(SurahListState(status: LoadStatus.ready, items: items));
      },
    );
  }
}
