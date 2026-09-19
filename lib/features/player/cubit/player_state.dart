import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../domain/entities/playback_unit.dart';

/// Why a session could not be played.
///
/// The listener is shown a sentence chosen from this, never the exception's
/// own text: `PlayerException`'s words are English, internal, and say nothing
/// anyone can act on — "Source error (0)" is not an instruction. The raw
/// detail stays in [PlayerScreenState.errorMessage] for the log.
enum PlayerFailure {
  /// The surah is not on the device and the CDN could not be reached — the
  /// ordinary offline case. Recoverable by connecting, or by downloading the
  /// surah while there is a connection.
  audioUnreachable,

  /// The catalog and the files disagree: a queued preamble with no clip, a
  /// bundled surah with no timings. Not the listener's doing.
  configuration,

  unknown,
}

/// Named to avoid colliding with `just_audio`'s own PlayerState.
class PlayerScreenState extends Equatable {
  const PlayerScreenState({
    this.status = LoadStatus.initial,
    this.currentUnit,
    this.playing = false,
    this.keepAwake = false,
    this.finished = false,
    this.errorMessage,
    this.failure,
  });

  final LoadStatus status;

  /// The ayah being recited. Null before the first unit starts.
  final PlaybackUnit? currentUnit;

  final bool playing;
  final bool keepAwake;
  final bool finished;

  /// The developer-facing detail, for the log — never rendered.
  final String? errorMessage;

  /// Set whenever [status] is a failure; what the listener is told.
  final PlayerFailure? failure;

  int get stepIndex => currentUnit?.stepIndex ?? 0;

  PlayerScreenState copyWith({
    LoadStatus? status,
    PlaybackUnit? currentUnit,
    bool? playing,
    bool? keepAwake,
    bool? finished,
    String? errorMessage,
    PlayerFailure? failure,
  }) => PlayerScreenState(
    status: status ?? this.status,
    currentUnit: currentUnit ?? this.currentUnit,
    playing: playing ?? this.playing,
    keepAwake: keepAwake ?? this.keepAwake,
    finished: finished ?? this.finished,
    errorMessage: errorMessage ?? this.errorMessage,
    failure: failure ?? this.failure,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    currentUnit,
    playing,
    keepAwake,
    finished,
    errorMessage,
    failure,
  ];
}
