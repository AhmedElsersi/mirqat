import 'dart:async';

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
///
/// Each row carries a memorization count, and this screen does not own that
/// number: the progress screen and the player both write it while the home
/// list sits mounted underneath them. `pushNamed` leaves this widget alive, so
/// nothing rebuilds it on the way back and a freshly marked ayah used to go
/// unnoticed until the next cold start. So it subscribes to the progress
/// store's own change stream instead of reloading at a navigation boundary —
/// that way it does not matter *which* screen did the writing.
class SurahListCubit extends Cubit<SurahListState> {
  SurahListCubit({
    required QuranRepository quranRepository,
    required ProgressRepository progressRepository,
  }) : _quran = quranRepository,
       _progress = progressRepository,
       super(const SurahListState()) {
    _watchProgress();
  }

  /// A session's worth of progress lands as one write per ayah in a tight loop
  /// (`PlayerCubit._recordProgress`), so a full surah is a burst of events for
  /// one user-visible change. Coalesce them: a reload is a Hive read per ayah
  /// per surah, and running it seven times in a row for one session would be
  /// seven times the work for the same answer.
  static const Duration _coalesceWindow = Duration(milliseconds: 250);

  final QuranRepository _quran;
  final ProgressRepository _progress;

  StreamSubscription<void>? _changes;
  Timer? _coalesce;

  void _watchProgress() {
    _changes = _progress.changes.listen((void _) {
      _coalesce?.cancel();
      _coalesce = Timer(_coalesceWindow, () {
        if (!isClosed) refresh();
      });
    });
  }

  /// First load: shows a spinner, because there is nothing to show yet.
  Future<void> load() => _load(showLoading: true);

  /// Re-read after something changed elsewhere.
  ///
  /// Deliberately does not flip to [LoadStatus.loading]: the rows are already
  /// on screen and correct apart from one count, so flashing a spinner over
  /// them would be a worse lie than the stale number it replaces.
  Future<void> refresh() => _load(showLoading: false);

  Future<void> _load({required bool showLoading}) async {
    if (showLoading) emit(state.copyWith(status: LoadStatus.loading));

    final result = await _quran.getSurahs();
    if (isClosed) return;

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

        // The awaits above mean this can land after the screen is gone.
        if (isClosed) return;
        emit(SurahListState(status: LoadStatus.ready, items: items));
      },
    );
  }

  @override
  Future<void> close() {
    _coalesce?.cancel();
    _changes?.cancel();
    return super.close();
  }
}
