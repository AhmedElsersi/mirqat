import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/surah.dart';

/// One row of the home list: a surah plus how much of it is memorized.
class SurahListItem extends Equatable {
  const SurahListItem({
    required this.surah,
    required this.memorizedCount,
    required this.inProgressCount,
  });

  final Surah surah;
  final int memorizedCount;
  final int inProgressCount;

  bool get isUntouched => memorizedCount == 0 && inProgressCount == 0;

  double get memorizedFraction =>
      surah.ayahCount == 0 ? 0 : memorizedCount / surah.ayahCount;

  @override
  List<Object?> get props => <Object?>[surah, memorizedCount, inProgressCount];
}

class SurahListState extends Equatable {
  const SurahListState({
    this.status = LoadStatus.initial,
    this.items = const <SurahListItem>[],
    this.errorMessage,
  });

  final LoadStatus status;
  final List<SurahListItem> items;
  final String? errorMessage;

  SurahListState copyWith({
    LoadStatus? status,
    List<SurahListItem>? items,
    String? errorMessage,
  }) => SurahListState(
    status: status ?? this.status,
    items: items ?? this.items,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[status, items, errorMessage];
}
