import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/audio_pack.dart';
import '../../../data/models/reciter.dart';

/// One reciter, as the whole-mushaf screen sees them: what they offer, what
/// of it is already here, and what a run of theirs is doing.
class ReciterOffline extends Equatable {
  const ReciterOffline({
    required this.reciter,
    required this.pending,
    required this.run,
    this.current,
  });

  final Reciter reciter;

  /// What a whole-mushaf download would still cost.
  final PendingDownloads pending;

  /// The whole-mushaf run for this reciter, idle when there is none.
  final BulkDownload run;

  /// The surah being fetched right now, as its own download reports it.
  /// Null unless a run of this reciter's is on one.
  final PackDownload? current;

  bool get isRunning => run.isRunning;

  /// Nothing left to fetch: every surah this reciter offers plays from the
  /// device.
  bool get isComplete => pending.isComplete;

  ReciterOffline copyWith({
    PendingDownloads? pending,
    BulkDownload? run,
    PackDownload? current,
    bool clearCurrent = false,
  }) => ReciterOffline(
    reciter: reciter,
    pending: pending ?? this.pending,
    run: run ?? this.run,
    current: clearCurrent ? null : (current ?? this.current),
  );

  @override
  List<Object?> get props => <Object?>[reciter, pending, run, current];
}

class MushafDownloadState extends Equatable {
  const MushafDownloadState({
    this.status = LoadStatus.initial,
    this.reciters = const <ReciterOffline>[],
    this.errorMessage,
  });

  final LoadStatus status;

  /// Every reciter whose recitation can be fetched, in catalog order.
  final List<ReciterOffline> reciters;
  final String? errorMessage;

  /// Whether any reciter's run is going. One at a time: the others' buttons
  /// stand down while it is, because two runs would split one connection.
  bool get anyRunning => reciters.any((ReciterOffline r) => r.isRunning);

  MushafDownloadState copyWith({
    LoadStatus? status,
    List<ReciterOffline>? reciters,
    String? errorMessage,
  }) => MushafDownloadState(
    status: status ?? this.status,
    reciters: reciters ?? this.reciters,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[status, reciters, errorMessage];
}
