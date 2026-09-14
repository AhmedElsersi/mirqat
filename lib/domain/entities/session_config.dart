import 'package:equatable/equatable.dart';

/// How consecutive ayahs get joined together as the session progresses.
enum ConnectMode {
  /// After learning ayah i, replay the whole block from the start of the range
  /// up to i. This is the talqeen pattern: 1, 2, 1-2, 3, 1-3, ...
  cumulative,

  /// Recite the range straight through, first ayah to last, and repeat that
  /// whole pass `repeatCount` times: for 1..3 at 3 repeats, the session is
  /// 1, 2, 3, 1, 2, 3, 1, 2, 3 — one step, nine recitations.
  ///
  /// Unlike the other two this is not a variation on the learn-then-join
  /// loop. There are no per-ayah drill steps at all, so the plan builder
  /// treats it as its own shape rather than a branch inside that loop.
  continuous,

  /// Learn steps only, with no joining.
  none;

  /// Stored values that the enum no longer has a case for, mapped to the
  /// surviving mode that behaves most like them.
  ///
  /// `pairwise` joined each ayah to its immediate predecessor only. Of what is
  /// left, [cumulative] is the nearest behaviour — it also joins after every
  /// ayah, just over the whole range so far — so a device that had pairwise
  /// selected keeps a joining session instead of silently losing the joins.
  static const Map<String, ConnectMode> retiredStorageValues =
      <String, ConnectMode>{'pairwise': ConnectMode.cumulative};

  /// Decodes a persisted `defaultConnectMode` string.
  ///
  /// Deliberately returns a [StoredConnectMode] rather than a bare mode: a
  /// value that had to be remapped or could not be read at all is something
  /// the caller has to *act* on — rewrite the box, say so in the log — not
  /// something to swallow behind a default.
  ///
  /// [absentFallback] is what "nothing stored" and "stored value unreadable"
  /// both mean. The product default for a fresh install lives with the rest of
  /// the settings defaults rather than here, so the engine holds no opinion
  /// about which mode a new reader should start on.
  static StoredConnectMode decodeStored(
    Object? raw, {
    ConnectMode absentFallback = ConnectMode.cumulative,
  }) {
    if (raw == null) {
      return StoredConnectMode._(
        mode: absentFallback,
        raw: null,
        status: StoredConnectModeStatus.absent,
      );
    }
    if (raw is String) {
      for (final ConnectMode mode in ConnectMode.values) {
        if (mode.name == raw) {
          return StoredConnectMode._(
            mode: mode,
            raw: raw,
            status: StoredConnectModeStatus.current,
          );
        }
      }
      final ConnectMode? retired = retiredStorageValues[raw];
      if (retired != null) {
        return StoredConnectMode._(
          mode: retired,
          raw: raw,
          status: StoredConnectModeStatus.retired,
        );
      }
    }
    return StoredConnectMode._(
      mode: absentFallback,
      raw: raw is String ? raw : '$raw',
      status: StoredConnectModeStatus.unreadable,
    );
  }

  /// Whether a closing pass over the whole range adds anything, for a mode the
  /// user has expressed no preference about.
  ///
  /// False for [cumulative] and [continuous] — both already end on a pass that
  /// spans the range, so a "final full pass" would just repeat it. True only
  /// for [none], which never joins anything and so never covers the range in
  /// one go. The user can still override it either way; this is only the
  /// default (see [SessionConfig.finalFullPass]).
  /// Kept in step with [SessionConfig]'s const initialiser by test.
  bool get defaultFinalFullPass => this == ConnectMode.none;
}

/// How a persisted connect-mode value was read.
enum StoredConnectModeStatus {
  /// Nothing was stored — a fresh install.
  absent,

  /// A value the enum still has a case for.
  current,

  /// A value from an older build, remapped via
  /// [ConnectMode.retiredStorageValues].
  retired,

  /// Not a value this app has ever written. Corrupted, hand-edited, or from a
  /// future build.
  unreadable,
}

/// The outcome of decoding a persisted connect mode.
class StoredConnectMode {
  const StoredConnectMode._({
    required this.mode,
    required this.raw,
    required this.status,
  });

  final ConnectMode mode;

  /// What was actually on disk, for the log line. Null when nothing was.
  final String? raw;

  final StoredConnectModeStatus status;

  /// Whether the box holds something other than what [mode] would serialise
  /// to, and so should be rewritten.
  bool get needsRewrite =>
      status == StoredConnectModeStatus.retired ||
      status == StoredConnectModeStatus.unreadable;
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
  }) : // Spelled out rather than delegating to
       // ConnectMode.defaultFinalFullPass because this constructor is
       // `const` and a const initialiser cannot call a getter. The two
       // must agree; `session_config_test` asserts they do for every
       // value of the enum, so adding a mode cannot desynchronise them.
       finalFullPass = finalFullPass ?? (connectMode == ConnectMode.none);

  static const int defaultRepeatCount = 3;
  static const int minRepeatCount = 1;

  /// Effectively open-ended — the count is typed as well as stepped — but
  /// still bounded, so a slip of the thumb cannot build a plan with millions
  /// of recitations in it. Three digits is also the width of the input field.
  static const int maxRepeatCount = 999;

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
  ///
  /// Defaults per mode, via [ConnectMode.defaultFinalFullPass]: false for
  /// [ConnectMode.cumulative] and [ConnectMode.continuous], whose last step
  /// already spans the range, and true for [ConnectMode.none], which never
  /// joins. Settable on any mode — on [ConnectMode.continuous] it simply adds
  /// one more identical pass.
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
