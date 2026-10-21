import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/state/load_status.dart';
import '../../../data/repositories/practice_repository.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../domain/entities/practice_stats.dart';

class StatsState extends Equatable {
  const StatsState({this.status = LoadStatus.initial, this.stats});

  final LoadStatus status;
  final PracticeStats? stats;

  @override
  List<Object?> get props => <Object?>[status, stats];
}

/// The reader's practice, in plain numbers.
class StatsCubit extends Cubit<StatsState> {
  StatsCubit({
    required PracticeRepository practiceRepository,
    required ProgressRepository progressRepository,
  }) : _practice = practiceRepository,
       _progress = progressRepository,
       super(const StatsState());

  final PracticeRepository _practice;
  final ProgressRepository _progress;

  /// Storage that cannot be read shows as nothing practised, never as an
  /// error: these are statistics, and there is nothing to retry.
  Future<void> load() async {
    emit(const StatsState(status: LoadStatus.loading));
    final Map<DateTime, PracticeDay> days = (await _practice.all()).getOrElse(
      () => const <DateTime, PracticeDay>{},
    );
    final int memorized = (await _progress.memorizedCount()).getOrElse(() => 0);
    if (isClosed) return;
    emit(
      StatsState(
        status: LoadStatus.ready,
        stats: PracticeStats.from(days: days, memorizedAyahs: memorized),
      ),
    );
  }
}
