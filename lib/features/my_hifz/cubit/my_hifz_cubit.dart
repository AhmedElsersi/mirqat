import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/juz_info.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/mutashabihat_repository.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';

class MyHifzState extends Equatable {
  const MyHifzState({
    this.status = LoadStatus.initial,
    this.memorized = 0,
    this.juzShares = const <double>[],
    this.weakSpots = 0,
    this.phrases = 0,
  });

  final LoadStatus status;

  /// Ayahs marked memorized, across the mushaf.
  final int memorized;

  /// For each juz in order, the share of its ayahs marked memorized, 0..1.
  final List<double> juzShares;

  /// Ayahs marked as places the reader stumbles.
  final int weakSpots;

  /// Shared phrases in the mutashabihat index.
  final int phrases;

  @override
  List<Object?> get props => <Object?>[
    status,
    memorized,
    juzShares,
    weakSpots,
    phrases,
  ];
}

/// "My hifz": what has been memorized across the mushaf, and how many places
/// wait to be strengthened. Plain counts and a map, never a score — and read
/// again whenever the progress store changes, so a session's marks are here
/// on the way back.
class MyHifzCubit extends Cubit<MyHifzState> {
  MyHifzCubit({
    required ProgressRepository progressRepository,
    required QuranRepository quranRepository,
    required QuranPagesRepository pagesRepository,
    required MutashabihatRepository mutashabihatRepository,
  }) : _progress = progressRepository,
       _quran = quranRepository,
       _pages = pagesRepository,
       _mutashabihat = mutashabihatRepository,
       super(const MyHifzState());

  final ProgressRepository _progress;
  final QuranRepository _quran;
  final QuranPagesRepository _pages;
  final MutashabihatRepository _mutashabihat;
  StreamSubscription<void>? _changes;

  Future<void> load() async {
    _changes ??= _progress.changes.listen((_) => load());
    // Beside the rest, not ahead of it: the index is the largest file the
    // app reads, and nothing else here waits on it.
    if (state.phrases == 0) unawaited(_countPhrases());
    if (state.status == LoadStatus.initial) {
      emit(const MyHifzState(status: LoadStatus.loading));
    }
    final List<Surah> surahs = (await _quran.getSurahs()).getOrElse(
      () => const <Surah>[],
    );
    final List<JuzInfo> ajzaa = (await _pages.juzList()).getOrElse(
      () => const <JuzInfo>[],
    );
    final List<MemorizationProgress> all = (await _progress.all()).getOrElse(
      () => const <MemorizationProgress>[],
    );
    final Either<Failure, List<MemorizationProgress>> stumbled = await _progress
        .stumbled();
    if (isClosed) return;

    // Every ayah by its place in reading order, so a juz is a run of them.
    final Map<int, int> before = <int, int>{};
    int total = 0;
    for (final Surah s in surahs) {
      before[s.number] = total;
      total += s.ayahCount;
    }
    int indexOf(int surah, int ayah) => (before[surah] ?? 0) + ayah - 1;
    final List<int> starts = <int>[
      for (final JuzInfo j in ajzaa) indexOf(j.surahNumber, j.ayahNumber),
    ];

    final List<int> counts = List<int>.filled(starts.length, 0);
    int memorized = 0;
    for (final MemorizationProgress p in all) {
      if (p.status != MemorizationStatus.memorized) continue;
      memorized++;
      final int at = indexOf(p.surahNumber, p.ayahNumber);
      int juz = starts.length - 1;
      while (juz > 0 && starts[juz] > at) {
        juz--;
      }
      if (juz >= 0) counts[juz]++;
    }
    final List<double> shares = <double>[
      for (int j = 0; j < starts.length; j++)
        () {
          final int end = j + 1 < starts.length ? starts[j + 1] : total;
          final int size = end - starts[j];
          return size <= 0 ? 0.0 : (counts[j] / size).clamp(0.0, 1.0);
        }(),
    ];

    emit(
      MyHifzState(
        status: LoadStatus.ready,
        memorized: memorized,
        juzShares: shares,
        weakSpots: stumbled
            .getOrElse(() => const <MemorizationProgress>[])
            .length,
        phrases: state.phrases,
      ),
    );
  }

  Future<void> _countPhrases() async {
    try {
      final int phrases = (await _mutashabihat.index()).phraseIds.length;
      if (!isClosed) {
        emit(
          MyHifzState(
            status: state.status,
            memorized: state.memorized,
            juzShares: state.juzShares,
            weakSpots: state.weakSpots,
            phrases: phrases,
          ),
        );
      }
    } on Object {
      // No index is no phrases, not a failure of the page.
    }
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
