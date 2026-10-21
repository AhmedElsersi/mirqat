import 'package:equatable/equatable.dart';

import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../domain/entities/plan_step.dart';
import '../../../domain/entities/session_config.dart';
import '../../../domain/entities/session_plan.dart';

/// Why a memorization session cannot start on the chosen range. Decided as
/// the range changes, so the reading view says so up front instead of the
/// player failing later.
enum SessionBlock {
  /// No reciter has audio for every surah of the range. It can still be read.
  noAudio,

  /// The chosen reciter lacks part of the range, but
  /// [SessionState.availableReciters] have all of it — offered as a switch.
  reciterLacksSurah,
}

/// Why a session could not be played.
///
/// The listener is shown a sentence chosen from this, never the exception's
/// own text: `PlayerException`'s words are English, internal, and say nothing
/// anyone can act on — "Source error (0)" is not an instruction. The raw
/// detail stays in [SessionState.errorDetail] for the log.
enum SessionFailure {
  /// The range is not on the device and the CDN could not be reached — the
  /// ordinary offline case. Recoverable by connecting, or by downloading the
  /// surah while there is a connection.
  audioUnreachable,

  /// The catalog and the files disagree: a queued preamble with no clip, a
  /// bundled surah with no timings. Not the listener's doing.
  configuration,

  unknown,
}

/// Where the session itself has got to — apart from what is being set up
/// for the next one.
enum SessionPhase {
  /// Nothing loaded. The bar offers to start.
  idle,

  /// Audio is being resolved and queued.
  loading,

  /// A session is loaded: playing, paused, or played out.
  active,

  failed,
}

class SessionState extends Equatable {
  const SessionState({
    this.ready = false,
    this.surahs = const <Surah>[],
    this.reciters = const <Reciter>[],
    this.chosenReciter,
    this.config,
    this.rangeChosen = false,
    this.plan,
    this.configError,
    this.estimatedDuration,
    this.defaults = const AppSettings(),
    this.defaultsSavedAt,
    this.phase = SessionPhase.idle,
    this.activePlan,
    this.activeReciter,
    this.currentUnit,
    this.recalling = false,
    this.playing = false,
    this.finished = false,
    this.failure,
    this.errorDetail,
    this.keepAwake = false,
    this.stumbled = const <AyahRef>{},
    this.gradeOffer,
    this.sleepAt,
    this.sleepAtEndOfStep = false,
  });

  /// Whether the catalog, the reciters and the settings have been read.
  final bool ready;

  /// The whole catalog, in order: what the range pickers offer and where the
  /// engine's ayah counts come from.
  final List<Surah> surahs;
  final List<Reciter> reciters;

  /// The reciter picked — in Settings, or for this reading in the sheet. May
  /// lack the range; [reciter] is who would actually recite.
  final Reciter? chosenReciter;

  /// What the next session would be. Edits land here, and are discarded when
  /// the screen closes unless saved as defaults.
  final SessionConfig? config;

  /// Whether the reader chose the range, or it is only what the page on show
  /// suggests. A suggestion follows the pages as they turn; a choice stays
  /// put, and is tinted on the page.
  final bool rangeChosen;

  /// Rebuilt on every change to [config], so the summary and the play button
  /// are always talking about the same plan.
  final SessionPlan? plan;
  final String? configError;

  /// Measured, never guessed: null unless every clip of the range is on the
  /// device to be measured.
  final Duration? estimatedDuration;

  final AppSettings defaults;

  /// Bumped when the current values are written back as defaults, so the
  /// screen can confirm it once.
  final DateTime? defaultsSavedAt;

  final SessionPhase phase;

  /// The plan that is loaded in the player. Not [plan]: the reader may be
  /// half-way through changing the settings of a session that is running.
  final SessionPlan? activePlan;
  final Reciter? activeReciter;

  /// The ayah being recited. Null before the first unit starts.
  final PlaybackUnit? currentUnit;

  /// True while the session is inside a recall gap: [currentUnit]'s ayah is
  /// being asked back from memory, and the page veils its words until the
  /// answering play begins.
  final bool recalling;

  final bool playing;
  final bool finished;

  final SessionFailure? failure;

  /// The developer-facing detail, for the log — never rendered.
  final String? errorDetail;

  final bool keepAwake;

  /// Every ayah the reader has marked as one they stumble at. Drawn on the
  /// page, and drilled more often by any plan that covers it.
  final Set<AyahRef> stumbled;

  /// A range just recited through, waiting to be told how it went — the
  /// self-grade that sets when it is next reviewed. Null once answered or
  /// waved away, and whenever there is nothing to grade.
  final ({AyahRef from, AyahRef to})? gradeOffer;

  /// When the sleep timer pauses the session. Null while none is set.
  final DateTime? sleepAt;

  /// Whether the session pauses once the step it is on has been played out.
  final bool sleepAtEndOfStep;

  bool get sleepTimerSet => sleepAt != null || sleepAtEndOfStep;

  bool get isActive => phase == SessionPhase.active;

  Map<int, int> get ayahCounts => <int, int>{
    for (final Surah s in surahs) s.number: s.ayahCount,
  };

  Surah? surah(int number) =>
      surahs.where((Surah s) => s.number == number).firstOrNull;

  /// The surahs [config]'s range passes through.
  List<Surah> get rangeSurahs {
    final SessionConfig? c = config;
    if (c == null) return const <Surah>[];
    return <Surah>[
      for (final Surah s in surahs)
        if (s.number >= c.surahNumber && s.number <= c.endSurahNumber) s,
    ];
  }

  /// Every reciter with audio for the whole range, in catalog order.
  List<Reciter> get availableReciters => <Reciter>[
    for (final Reciter r in reciters)
      if (rangeSurahs.isNotEmpty &&
          rangeSurahs.every((Surah s) => r.hasSurah(s.number)))
        r,
  ];

  SessionBlock? get block {
    if (config == null) return null;
    final List<Reciter> available = availableReciters;
    if (available.isEmpty) return SessionBlock.noAudio;
    final Reciter? chosen = chosenReciter;
    if (chosen != null && !available.contains(chosen)) {
      return SessionBlock.reciterLacksSurah;
    }
    return null;
  }

  /// Who would recite: the chosen reciter, or the first who has the range
  /// when none is chosen. Null while a session is blocked.
  Reciter? get reciter =>
      block != null ? null : (chosenReciter ?? availableReciters.firstOrNull);

  bool get canStart =>
      ready &&
      reciter != null &&
      plan != null &&
      configError == null &&
      phase != SessionPhase.loading;

  /// The range to tint on the page: the one the reader chose, while nothing
  /// is playing. A range the page merely suggests is not tinted — marking most
  /// of a surah says nothing — and once a session is running the ayah being
  /// recited is the one mark the page needs; the bar says the rest.
  ({AyahRef from, AyahRef to})? get markedRange {
    final SessionConfig? c = config;
    if (c == null || !rangeChosen || isActive) return null;
    return (from: c.start, to: c.end);
  }

  PlanStep? get currentStep {
    final SessionPlan? p = activePlan;
    if (p == null || p.steps.isEmpty) return null;
    return p.steps[currentUnit?.stepIndex ?? 0];
  }

  /// Whether the settings now differ from the running session in a way that
  /// cannot simply be applied under it: another reciter, another range, other
  /// repeats, another way of joining. Speed and pauses never count — they are
  /// applied as they change.
  bool get hasPendingChange {
    final SessionPlan? active = activePlan;
    final SessionConfig? draft = config;
    if (!isActive || active == null || draft == null) return false;
    return _shapeOf(draft) != _shapeOf(active.config) ||
        (reciter != null && reciter != activeReciter);
  }

  /// A record, not a list: two lists are only ever equal to themselves.
  static (AyahRef, AyahRef, int, ConnectMode, bool, int, bool) _shapeOf(
    SessionConfig c,
  ) => (
    c.start,
    c.end,
    c.repeatCount,
    c.connectMode,
    c.finalFullPass,
    c.recallRounds,
    c.chainRecall,
  );

  SessionState copyWith({
    bool? ready,
    List<Surah>? surahs,
    List<Reciter>? reciters,
    Reciter? chosenReciter,
    SessionConfig? config,
    bool? rangeChosen,
    SessionPlan? plan,
    bool clearPlan = false,
    String? configError,
    bool clearConfigError = false,
    Duration? estimatedDuration,
    bool clearEstimate = false,
    AppSettings? defaults,
    DateTime? defaultsSavedAt,
    SessionPhase? phase,
    SessionPlan? activePlan,
    Reciter? activeReciter,
    PlaybackUnit? currentUnit,
    bool? recalling,
    bool clearSession = false,
    bool? playing,
    bool? finished,
    SessionFailure? failure,
    bool clearFailure = false,
    String? errorDetail,
    bool? keepAwake,
    Set<AyahRef>? stumbled,
    ({AyahRef from, AyahRef to})? gradeOffer,
    bool clearGradeOffer = false,
    DateTime? sleepAt,
    bool? sleepAtEndOfStep,
    bool clearSleep = false,
  }) => SessionState(
    ready: ready ?? this.ready,
    surahs: surahs ?? this.surahs,
    reciters: reciters ?? this.reciters,
    chosenReciter: chosenReciter ?? this.chosenReciter,
    config: config ?? this.config,
    rangeChosen: rangeChosen ?? this.rangeChosen,
    plan: clearPlan ? null : (plan ?? this.plan),
    configError: clearConfigError ? null : (configError ?? this.configError),
    estimatedDuration: clearEstimate
        ? null
        : (estimatedDuration ?? this.estimatedDuration),
    defaults: defaults ?? this.defaults,
    defaultsSavedAt: defaultsSavedAt ?? this.defaultsSavedAt,
    phase: phase ?? this.phase,
    activePlan: clearSession ? null : (activePlan ?? this.activePlan),
    activeReciter: clearSession ? null : (activeReciter ?? this.activeReciter),
    currentUnit: clearSession ? null : (currentUnit ?? this.currentUnit),
    recalling: clearSession ? false : (recalling ?? this.recalling),
    playing: clearSession ? false : (playing ?? this.playing),
    finished: clearSession ? false : (finished ?? this.finished),
    failure: clearFailure || clearSession ? null : (failure ?? this.failure),
    errorDetail: clearFailure || clearSession
        ? null
        : (errorDetail ?? this.errorDetail),
    keepAwake: keepAwake ?? this.keepAwake,
    stumbled: stumbled ?? this.stumbled,
    gradeOffer: clearGradeOffer ? null : (gradeOffer ?? this.gradeOffer),
    sleepAt: clearSleep ? null : (sleepAt ?? this.sleepAt),
    sleepAtEndOfStep: clearSleep
        ? false
        : (sleepAtEndOfStep ?? this.sleepAtEndOfStep),
  );

  @override
  List<Object?> get props => <Object?>[
    ready,
    surahs,
    reciters,
    chosenReciter,
    config,
    rangeChosen,
    plan,
    configError,
    estimatedDuration,
    defaults,
    defaultsSavedAt,
    phase,
    activePlan,
    activeReciter,
    currentUnit,
    recalling,
    playing,
    finished,
    failure,
    errorDetail,
    keepAwake,
    stumbled,
    gradeOffer,
    sleepAt,
    sleepAtEndOfStep,
  ];
}
