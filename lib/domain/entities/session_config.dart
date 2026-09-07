import 'package:equatable/equatable.dart';

/// How consecutive ayahs get joined together as the session progresses.
enum ConnectMode {
  /// After learning ayah i, replay the whole block from the start of the range
  /// up to i. This is the talqeen pattern: 1, 2, 1-2, 3, 1-3, ...
  cumulative,

  /// After learning ayah i, replay only the previous ayah joined to it:
  /// 1, 2, 1-2, 3, 2-3, ...
  pairwise,

  /// Learn steps only, with no joining.
  none,
}

/// Everything the [RepetitionPlanBuilder] needs to lay out a session.
///
/// Pure data with no Flutter dependency, so the engine stays unit-testable.
class SessionConfig extends Equatable {
  const SessionConfig({
    required this.surahNumber,
    required this.startAyah,
    required this.endAyah,
    this.repeatCount = defaultRepeatCount,
    this.connectMode = ConnectMode.cumulative,
    bool? finalFullPass,
    this.intraBlockPauseMs = defaultIntraBlockPauseMs,
    this.betweenRepeatPauseMs = defaultBetweenRepeatPauseMs,
    this.betweenStepsPauseMs = defaultBetweenStepsPauseMs,
    this.playbackSpeed = defaultPlaybackSpeed,
    this.playIstiadhah = false,
  }) : finalFullPass =
           finalFullPass ?? (connectMode != ConnectMode.cumulative);

  static const int defaultRepeatCount = 3;
  static const int minRepeatCount = 1;
  static const int maxRepeatCount = 20;

  static const int defaultIntraBlockPauseMs = 300;
  static const int defaultBetweenRepeatPauseMs = 800;
  static const int defaultBetweenStepsPauseMs = 1500;

  static const double defaultPlaybackSpeed = 1.0;
  static const double minPlaybackSpeed = 0.5;
  static const double maxPlaybackSpeed = 1.5;

  final int surahNumber;
  final int startAyah;
  final int endAyah;

  /// How many times each step is repeated.
  final int repeatCount;

  final ConnectMode connectMode;

  /// Whether to close the session with one more pass over the whole range.
  /// Defaults to false for [ConnectMode.cumulative] — whose last connect step
  /// already spans the range — and true for the other two modes.
  final bool finalFullPass;

  /// Gap between ayahs inside one repetition of a block.
  final int intraBlockPauseMs;

  /// Gap between repetitions of the same step.
  final int betweenRepeatPauseMs;

  /// Gap between steps.
  final int betweenStepsPauseMs;

  final double playbackSpeed;

  /// Whether to play the reciter's isti'adhah before the session starts. It is
  /// a preamble, never an ayah, so it never enters the playback queue as a
  /// [PlaybackUnit] and never counts toward a repetition.
  final bool playIstiadhah;

  /// Number of ayahs in the range.
  int get ayahSpan => endAyah - startAyah + 1;

  SessionConfig copyWith({
    int? surahNumber,
    int? startAyah,
    int? endAyah,
    int? repeatCount,
    ConnectMode? connectMode,
    bool? finalFullPass,
    int? intraBlockPauseMs,
    int? betweenRepeatPauseMs,
    int? betweenStepsPauseMs,
    double? playbackSpeed,
    bool? playIstiadhah,
  }) => SessionConfig(
    surahNumber: surahNumber ?? this.surahNumber,
    startAyah: startAyah ?? this.startAyah,
    endAyah: endAyah ?? this.endAyah,
    repeatCount: repeatCount ?? this.repeatCount,
    connectMode: connectMode ?? this.connectMode,
    finalFullPass: finalFullPass ?? this.finalFullPass,
    intraBlockPauseMs: intraBlockPauseMs ?? this.intraBlockPauseMs,
    betweenRepeatPauseMs: betweenRepeatPauseMs ?? this.betweenRepeatPauseMs,
    betweenStepsPauseMs: betweenStepsPauseMs ?? this.betweenStepsPauseMs,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    playIstiadhah: playIstiadhah ?? this.playIstiadhah,
  );

  @override
  List<Object?> get props => <Object?>[
    surahNumber,
    startAyah,
    endAyah,
    repeatCount,
    connectMode,
    finalFullPass,
    intraBlockPauseMs,
    betweenRepeatPauseMs,
    betweenStepsPauseMs,
    playbackSpeed,
    playIstiadhah,
  ];
}
