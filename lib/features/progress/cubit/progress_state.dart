import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/memorization_progress.dart';
import '../../../data/models/surah.dart';

class ProgressScreenState extends Equatable {
  const ProgressScreenState({
    this.status = LoadStatus.initial,
    this.surah,
    this.records = const <MemorizationProgress>[],
    this.errorMessage,
  });

  final LoadStatus status;
  final Surah? surah;
  final List<MemorizationProgress> records;
  final String? errorMessage;

  int get memorizedCount => records
      .where(
        (MemorizationProgress p) => p.status == MemorizationStatus.memorized,
      )
      .length;

  ProgressScreenState copyWith({
    LoadStatus? status,
    Surah? surah,
    List<MemorizationProgress>? records,
    String? errorMessage,
  }) => ProgressScreenState(
    status: status ?? this.status,
    surah: surah ?? this.surah,
    records: records ?? this.records,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[status, surah, records, errorMessage];
}
