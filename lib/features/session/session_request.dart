import 'package:equatable/equatable.dart';

import '../../domain/entities/ayah_ref.dart';
import '../../domain/entities/session_config.dart';

/// Overrides laid over the reader's own defaults for one session — how a
/// review is lighter than learning something new. A null field keeps the
/// default.
class SessionPreset extends Equatable {
  const SessionPreset({
    this.repeatCount,
    this.connectMode,
    this.recallRounds,
    this.chainRecall,
  });

  /// A recent portion gone over again: twice, with one recall round.
  static const SessionPreset recent = SessionPreset(
    repeatCount: 2,
    recallRounds: 1,
  );

  /// An old portion kept: recited straight through once, then its links
  /// tested.
  static const SessionPreset old = SessionPreset(
    repeatCount: 1,
    connectMode: ConnectMode.continuous,
    chainRecall: true,
  );

  /// A passage that will not settle: drilled hard, asked back twice, its
  /// links tested.
  static const SessionPreset deep = SessionPreset(
    repeatCount: 7,
    connectMode: ConnectMode.cumulative,
    recallRounds: 2,
    chainRecall: true,
  );

  /// Listening on a loop: the range straight through, nothing asked back,
  /// as many times as the repeat count says — for the commute, or the first
  /// familiarizing passes talqeen begins with. The count is left as it is,
  /// so the stepper beside it is how many times.
  static const SessionPreset listenLoop = SessionPreset(
    connectMode: ConnectMode.continuous,
    recallRounds: 0,
    chainRecall: false,
  );

  /// Listening, not drilling: straight through once, nothing asked back.
  static const SessionPreset listen = SessionPreset(
    repeatCount: 1,
    connectMode: ConnectMode.continuous,
    recallRounds: 0,
    chainRecall: false,
  );

  final int? repeatCount;
  final ConnectMode? connectMode;
  final int? recallRounds;
  final bool? chainRecall;

  /// [config] with this preset's fields laid over it. A mode change lets the
  /// closing pass follow the new mode's own default, as a change in the sheet
  /// does.
  SessionConfig applyTo(SessionConfig config) {
    final SessionConfig base = connectMode == null
        ? config
        : SessionConfig(
            surahNumber: config.surahNumber,
            startAyah: config.startAyah,
            endSurahNumber: config.endSurahNumber,
            endAyah: config.endAyah,
            repeatCount: config.repeatCount,
            connectMode: connectMode!,
            intraBlockPauseMs: config.intraBlockPauseMs,
            betweenRepeatPauseMs: config.betweenRepeatPauseMs,
            betweenStepsPauseMs: config.betweenStepsPauseMs,
            playbackSpeed: config.playbackSpeed,
            playIstiadhah: config.playIstiadhah,
            recallRounds: config.recallRounds,
            chainRecall: config.chainRecall,
          );
    return base.copyWith(
      repeatCount: repeatCount?.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
      recallRounds: recallRounds?.clamp(
        SessionConfig.minRecallRounds,
        SessionConfig.maxRecallRounds,
      ),
      chainRecall: chainRecall,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    repeatCount,
    connectMode,
    recallRounds,
    chainRecall,
  ];
}

/// A session to set up as the reading view opens: a range, how to tune it,
/// and whether to start at once.
class SessionRequest extends Equatable {
  const SessionRequest({
    required this.from,
    required this.to,
    this.preset = const SessionPreset(),
    this.presetKey,
    this.autostart = false,
  });

  final AyahRef from;
  final AyahRef to;
  final SessionPreset preset;

  /// The sheet's chip that [preset] is, to show as chosen. Null: none.
  final String? presetKey;
  final bool autostart;

  @override
  List<Object?> get props => <Object?>[
    from,
    to,
    preset,
    presetKey,
    autostart,
  ];
}
