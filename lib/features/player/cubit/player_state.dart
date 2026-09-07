import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../domain/entities/playback_unit.dart';

/// Named to avoid colliding with `just_audio`'s own PlayerState.
class PlayerScreenState extends Equatable {
  const PlayerScreenState({
    this.status = LoadStatus.initial,
    this.currentUnit,
    this.playing = false,
    this.keepAwake = false,
    this.finished = false,
    this.errorMessage,
  });

  final LoadStatus status;

  /// The ayah being recited. Null before the first unit starts.
  final PlaybackUnit? currentUnit;

  final bool playing;
  final bool keepAwake;
  final bool finished;
  final String? errorMessage;

  int get stepIndex => currentUnit?.stepIndex ?? 0;

  PlayerScreenState copyWith({
    LoadStatus? status,
    PlaybackUnit? currentUnit,
    bool? playing,
    bool? keepAwake,
    bool? finished,
    String? errorMessage,
  }) => PlayerScreenState(
    status: status ?? this.status,
    currentUnit: currentUnit ?? this.currentUnit,
    playing: playing ?? this.playing,
    keepAwake: keepAwake ?? this.keepAwake,
    finished: finished ?? this.finished,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    currentUnit,
    playing,
    keepAwake,
    finished,
    errorMessage,
  ];
}
