import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../../core/error/exceptions.dart';
import '../../../core/error/failures.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/engine/repetition_plan_builder.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../domain/entities/session_config.dart';
import '../../../domain/entities/session_plan.dart';
import '../../../services/audio/ayah_duration_service.dart';
import '../../../services/audio/memorization_player_service.dart';
import '../../../services/audio/reciter_catalog.dart';
import '../../../services/keep_awake_service.dart';
import 'session_state.dart';

/// The memorization session of one reading screen: what it would be, and —
/// once started — where it has got to.
///
/// This is the old reader's session setup and the old player screen in one
/// place, because they are one thing to the person using them: the text is
/// on screen, the session is set up beside it, and it plays over that same
/// text. There is no second screen to go to.
///
/// It knows nothing of pages. The reading screen tells it which ayahs the
/// page suggests ([suggestRange]) and listens for the ayah being recited.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required QuranRepository quranRepository,
    required SettingsRepository settingsRepository,
    required ReciterCatalog reciterCatalog,
    required AyahDurationService durationService,
    required RepetitionPlanBuilder planBuilder,
    required MemorizationPlayerService playerService,
    required ProgressRepository progressRepository,
    required KeepAwakeService keepAwakeService,
    this.pauseSettleTime = const Duration(milliseconds: 600),
  }) : _quran = quranRepository,
       _settings = settingsRepository,
       _reciters = reciterCatalog,
       _durations = durationService,
       _builder = planBuilder,
       _player = playerService,
       _progress = progressRepository,
       _keepAwake = keepAwakeService,
       super(const SessionState());

  final QuranRepository _quran;
  final SettingsRepository _settings;
  final ReciterCatalog _reciters;
  final AyahDurationService _durations;
  final RepetitionPlanBuilder _builder;
  final MemorizationPlayerService _player;
  final ProgressRepository _progress;
  final KeepAwakeService _keepAwake;

  /// How long a pause slider has to rest before a running session is
  /// re-queued with the new gaps. Re-queuing restarts the ayah being heard,
  /// which is fine once and maddening thirty times a second.
  final Duration pauseSettleTime;

  StreamSubscription<PlaybackUnit>? _unitSub;
  StreamSubscription<ja.PlayerState>? _stateSub;
  Timer? _pauseTimer;
  int _estimateToken = 0;

  /// How many times each ayah has actually been recited this session. Written
  /// to storage when the session ends or is stopped, so a session abandoned
  /// halfway still counts what it played.
  final Map<AyahRef, int> _played = <AyahRef, int>{};

  Future<void> load() async {
    final List<Surah> surahs = (await _quran.getSurahs()).getOrElse(
      () => const <Surah>[],
    );
    final List<Reciter> reciters = (await _reciters.reciters()).getOrElse(
      () => const <Reciter>[],
    );
    final AppSettings settings = (await _settings.read()).getOrElse(
      () => const AppSettings(),
    );
    if (isClosed) return;

    emit(
      state.copyWith(
        ready: surahs.isNotEmpty,
        surahs: surahs,
        reciters: reciters,
        chosenReciter: reciters
            .where((Reciter r) => r.id == settings.reciterId)
            .firstOrNull,
        defaults: settings,
      ),
    );
  }

  // --- the range -----------------------------------------------------------

  /// What the page on show suggests a session would cover. Ignored once the
  /// reader has chosen a range of their own, and while a session is running:
  /// turning a page must not quietly change what "play" means.
  void suggestRange(AyahRef from, AyahRef to) {
    if (!state.ready || state.rangeChosen || state.isActive) return;

    // "Last used", in Settings: a reader who is working through a surah a few
    // ayahs at a time gets their range back when they open it again, as a
    // choice — tinted, and theirs to clear. Offered once per surah, or
    // clearing it would only bring it straight back.
    final AyahRange? remembered = _rememberedFor(from, to);
    if (remembered != null && _offered.add(from.surah)) {
      chooseRange(
        AyahRef(from.surah, remembered.startAyah),
        AyahRef(from.surah, remembered.endAyah),
      );
      return;
    }

    final SessionConfig? c = state.config;
    if (c != null && c.start == from && c.end == to) return;
    _apply(_withRange(from, to), rangeChosen: false);
  }

  final Set<int> _offered = <int>{};

  /// The range last used in a surah, when the page suggests that surah whole
  /// and the reader has asked for ranges to be remembered. A remembered range
  /// only applies while it still fits the surah — a catalog correction must
  /// never hand back an out-of-bounds selection.
  AyahRange? _rememberedFor(AyahRef from, AyahRef to) {
    if (state.defaults.defaultRangeBehaviour != RangeBehaviour.lastUsed) {
      return null;
    }
    final Surah? surah = state.surah(from.surah);
    final bool wholeSurah =
        surah != null &&
        from.ayah == 1 &&
        to == AyahRef(surah.number, surah.ayahCount);
    if (!wholeSurah) return null;
    final AyahRange? r = state.defaults.rememberedRangeFor(surah.number);
    final bool fits =
        r != null &&
        r.startAyah >= 1 &&
        r.endAyah <= surah.ayahCount &&
        r.startAyah <= r.endAyah;
    return fits ? r : null;
  }

  /// Writes down the range a session is started with, for next time. Inside
  /// one surah only: the setting is per surah, and a range across two has no
  /// one surah to be remembered under. A failed write costs a remembered
  /// range, which is not worth holding a session up over.
  Future<void> _rememberRange(SessionConfig config) async {
    if (state.defaults.defaultRangeBehaviour != RangeBehaviour.lastUsed ||
        config.spansSurahs) {
      return;
    }
    final AppSettings next = state.defaults.rememberRange(
      config.surahNumber,
      AyahRange(startAyah: config.startAyah, endAyah: config.endAyah),
    );
    final result = await _settings.save(next);
    if (isClosed) return;
    result.fold((Failure _) {}, (_) => emit(state.copyWith(defaults: next)));
  }

  /// A range the reader picked — from an ayah's actions, or the sheet.
  void chooseRange(AyahRef from, AyahRef to) {
    if (!state.ready) return;
    _apply(_withRange(from, to), rangeChosen: true);
  }

  /// Moves one end, nudging the other rather than letting them cross.
  void setStart(AyahRef from) {
    final SessionConfig? c = state.config;
    if (c == null) return;
    final AyahRef start = _clamped(from);
    chooseRange(start, start > c.end ? start : c.end);
  }

  void setEnd(AyahRef to) {
    final SessionConfig? c = state.config;
    if (c == null) return;
    final AyahRef end = _clamped(to);
    chooseRange(end < c.start ? end : c.start, end);
  }

  /// Gives the range back to the page.
  void clearRange() => emit(state.copyWith(rangeChosen: false));

  /// The last ayah of [surahNumber], from the catalog.
  AyahRef? endOfSurah(int surahNumber) {
    final Surah? surah = state.surah(surahNumber);
    return surah == null ? null : AyahRef(surah.number, surah.ayahCount);
  }

  AyahRef _clamped(AyahRef ref) {
    final Surah? surah = state.surah(ref.surah);
    if (surah == null) return ref;
    return AyahRef(surah.number, ref.ayah.clamp(1, surah.ayahCount));
  }

  SessionConfig _withRange(AyahRef from, AyahRef to) {
    final SessionConfig base = state.config ?? _fromDefaults(state.defaults);
    return SessionConfig(
      surahNumber: from.surah,
      startAyah: from.ayah,
      endSurahNumber: to.surah,
      endAyah: to.ayah,
      repeatCount: base.repeatCount,
      connectMode: base.connectMode,
      finalFullPass: base.finalFullPass,
      intraBlockPauseMs: base.intraBlockPauseMs,
      betweenRepeatPauseMs: base.betweenRepeatPauseMs,
      betweenStepsPauseMs: base.betweenStepsPauseMs,
      playbackSpeed: base.playbackSpeed,
      playIstiadhah: base.playIstiadhah,
    );
  }

  /// The tuning a fresh session starts from. The range here is a placeholder
  /// that [_withRange] replaces at once.
  static SessionConfig _fromDefaults(AppSettings settings) => SessionConfig(
    surahNumber: 1,
    startAyah: 1,
    endAyah: 1,
    repeatCount: settings.defaultRepeatCount,
    connectMode: settings.defaultConnectMode,
    // Null lets SessionConfig apply the mode's own default.
    finalFullPass: settings.defaultFinalFullPass,
    intraBlockPauseMs: settings.defaultIntraBlockPauseMs,
    betweenRepeatPauseMs: settings.defaultBetweenRepeatPauseMs,
    betweenStepsPauseMs: settings.defaultBetweenStepsPauseMs,
    playbackSpeed: settings.defaultPlaybackSpeed,
  );

  // --- tuning --------------------------------------------------------------

  void setReciter(Reciter reciter) {
    emit(state.copyWith(chosenReciter: reciter));
    unawaited(_estimate());
  }

  void setRepeatCount(int value) => _change(
    (SessionConfig c) => c.copyWith(
      repeatCount: value.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
    ),
  );

  /// Changing the mode rebuilds the config without an explicit
  /// [SessionConfig.finalFullPass], so the closing-pass toggle follows the new
  /// mode's own default. Carrying the old value across is how a continuous
  /// session ends up quietly reciting the range twice.
  void setConnectMode(ConnectMode mode) => _change(
    (SessionConfig c) => SessionConfig(
      surahNumber: c.surahNumber,
      startAyah: c.startAyah,
      endSurahNumber: c.endSurahNumber,
      endAyah: c.endAyah,
      repeatCount: c.repeatCount,
      connectMode: mode,
      intraBlockPauseMs: c.intraBlockPauseMs,
      betweenRepeatPauseMs: c.betweenRepeatPauseMs,
      betweenStepsPauseMs: c.betweenStepsPauseMs,
      playbackSpeed: c.playbackSpeed,
      playIstiadhah: c.playIstiadhah,
    ),
  );

  void setFinalFullPass(bool value) =>
      _change((SessionConfig c) => c.copyWith(finalFullPass: value));

  void setPlayIstiadhah(bool value) =>
      _change((SessionConfig c) => c.copyWith(playIstiadhah: value));

  void setIntraBlockPause(int ms) =>
      _changePause((SessionConfig c) => c.copyWith(intraBlockPauseMs: ms));

  void setBetweenRepeatPause(int ms) =>
      _changePause((SessionConfig c) => c.copyWith(betweenRepeatPauseMs: ms));

  void setBetweenStepsPause(int ms) =>
      _changePause((SessionConfig c) => c.copyWith(betweenStepsPauseMs: ms));

  /// Speed is the one setting the player takes as it is: it moves nothing.
  void setPlaybackSpeed(double speed) {
    _change((SessionConfig c) => c.copyWith(playbackSpeed: speed));
    if (state.isActive) unawaited(_player.setSpeed(speed));
  }

  /// Pauses are clips of silence in the queue, so a running session takes new
  /// ones by being queued again and picked up at the very play it was on.
  /// Nobody is asked: it is the same session with different gaps.
  void _changePause(SessionConfig Function(SessionConfig) change) {
    _change(change);
    if (!state.isActive) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(pauseSettleTime, () => unawaited(_requeuePauses()));
  }

  Future<void> _requeuePauses() async {
    final SessionPlan? active = state.activePlan;
    final SessionConfig? draft = state.config;
    final Reciter? reciter = state.activeReciter;
    if (!state.isActive || active == null || draft == null || reciter == null) {
      return;
    }
    // Only the gaps: everything else about the running session stays as it
    // is until the reader says what to do with their other changes.
    final SessionConfig next = active.config.copyWith(
      intraBlockPauseMs: draft.intraBlockPauseMs,
      betweenRepeatPauseMs: draft.betweenRepeatPauseMs,
      betweenStepsPauseMs: draft.betweenStepsPauseMs,
    );
    if (next == active.config) return;
    final SessionPlan? plan = _build(next);
    if (plan == null) return;
    final PlaybackUnit? unit = state.currentUnit;
    await _run(
      plan,
      reciter,
      startAtUnit: unit == null ? 0 : active.units.indexOf(unit),
      autoplay: state.playing,
    );
  }

  // --- defaults ------------------------------------------------------------

  /// Reloads the tuning from the persisted defaults, leaving the range alone.
  void resetToDefaults() {
    final SessionConfig? c = state.config;
    if (c == null) return;
    final SessionConfig d = _fromDefaults(state.defaults);
    _apply(
      SessionConfig(
        surahNumber: c.surahNumber,
        startAyah: c.startAyah,
        endSurahNumber: c.endSurahNumber,
        endAyah: c.endAyah,
        repeatCount: d.repeatCount,
        connectMode: d.connectMode,
        finalFullPass: state.defaults.defaultFinalFullPass,
        intraBlockPauseMs: d.intraBlockPauseMs,
        betweenRepeatPauseMs: d.betweenRepeatPauseMs,
        betweenStepsPauseMs: d.betweenStepsPauseMs,
        playbackSpeed: d.playbackSpeed,
        playIstiadhah: c.playIstiadhah,
      ),
      rangeChosen: state.rangeChosen,
    );
  }

  /// Writes the current tuning back as the defaults for every session.
  Future<void> saveAsDefaults() async {
    final SessionConfig? c = state.config;
    if (c == null) return;
    final AppSettings next = state.defaults.copyWith(
      defaultRepeatCount: c.repeatCount,
      defaultConnectMode: c.connectMode,
      defaultFinalFullPass: c.finalFullPass,
      defaultIntraBlockPauseMs: c.intraBlockPauseMs,
      defaultBetweenRepeatPauseMs: c.betweenRepeatPauseMs,
      defaultBetweenStepsPauseMs: c.betweenStepsPauseMs,
      defaultPlaybackSpeed: c.playbackSpeed,
    );
    final result = await _settings.save(next);
    if (isClosed) return;
    result.fold(
      (Failure f) => emit(state.copyWith(errorDetail: f.message)),
      (_) =>
          emit(state.copyWith(defaults: next, defaultsSavedAt: DateTime.now())),
    );
  }

  // --- playing -------------------------------------------------------------

  /// Starts the session that is set up, from the top.
  Future<void> start() async {
    final SessionPlan? plan = state.plan;
    final Reciter? reciter = state.reciter;
    if (plan == null || reciter == null) return;
    emit(state.copyWith(phase: SessionPhase.loading, clearFailure: true));
    await _recordProgress();
    unawaited(_rememberRange(plan.config));
    await _run(plan, reciter, startAtUnit: 0, autoplay: true);
  }

  /// Takes up the settings changed under a running session: from the top, or
  /// from the ayah being heard — the start of that ayah's drill in the new
  /// plan, or the top if the new range no longer holds it.
  Future<void> applyChanges({required bool restart}) async {
    final SessionPlan? plan = state.plan;
    final Reciter? reciter = state.reciter;
    if (plan == null || reciter == null) return;
    final AyahRef? here = state.currentUnit?.ref;
    final int at = restart || here == null ? 0 : (plan.firstUnitOf(here) ?? 0);
    // Said before anything is awaited: the question has been answered, and
    // whoever asked it must see that now, not when the new queue has loaded.
    emit(state.copyWith(phase: SessionPhase.loading, clearFailure: true));
    if (restart) await _recordProgress();
    await _run(plan, reciter, startAtUnit: at, autoplay: true);
  }

  /// Puts the settings back to those of the running session.
  void discardChanges() {
    final SessionPlan? active = state.activePlan;
    if (active == null) return;
    emit(
      state.copyWith(
        chosenReciter: state.activeReciter,
        config: active.config,
        plan: active,
        clearConfigError: true,
      ),
    );
  }

  Future<void> _run(
    SessionPlan plan,
    Reciter reciter, {
    required int startAtUnit,
    required bool autoplay,
  }) async {
    _pauseTimer?.cancel();
    // A second run on the same cubit: the last one's subscriptions go first,
    // or every repeat would be counted twice.
    await _unitSub?.cancel();
    await _stateSub?.cancel();
    _unitSub = null;
    _stateSub = null;

    emit(state.copyWith(phase: SessionPhase.loading, clearFailure: true));

    try {
      await _player.load(
        plan: plan,
        reciter: reciter,
        surahs: state.surahs,
        startAtUnit: startAtUnit < 0 ? 0 : startAtUnit,
      );
    } catch (e) {
      _fail(e);
      return;
    }
    if (isClosed) return;

    _unitSub = _player.currentUnitStream.listen((PlaybackUnit unit) {
      _played.update(unit.ref, (int n) => n + 1, ifAbsent: () => 1);
      emit(state.copyWith(currentUnit: unit));
    });
    _stateSub = _player.playerStateStream.listen(
      (ja.PlayerState s) {
        final bool finished = s.processingState == ja.ProcessingState.completed;
        emit(
          state.copyWith(playing: s.playing && !finished, finished: finished),
        );
        if (finished) unawaited(_recordProgress());
      },
      // A connection lost mid-session surfaces here rather than at load. What
      // was recited up to that point is still worth keeping.
      onError: (Object error) {
        unawaited(_recordProgress());
        _fail(error);
      },
    );

    emit(
      state.copyWith(
        phase: SessionPhase.active,
        activePlan: plan,
        activeReciter: reciter,
        currentUnit: plan.units[startAtUnit < 0 ? 0 : startAtUnit],
        finished: false,
      ),
    );

    if (!autoplay) return;
    // The first clip is opened here, so an unreachable source raises on this
    // call rather than on load.
    try {
      await _player.play();
    } catch (e) {
      _fail(e);
    }
  }

  void _fail(Object error) {
    if (isClosed) return;
    emit(
      state.copyWith(
        phase: SessionPhase.failed,
        playing: false,
        failure: classifyFailure(error, streamsAnyAyah: _player.streamsAnyAyah),
        errorDetail: '$error',
      ),
    );
  }

  /// Which sentence the listener gets.
  ///
  /// The exception itself only ever says *that* a source would not open —
  /// `PlayerException` carries a platform code, not a cause — so what
  /// separates the two cases is the queue: if every clip was already on the
  /// device, the network is not what went missing, and telling someone to
  /// check their connection would send them after the wrong thing.
  @visibleForTesting
  static SessionFailure classifyFailure(
    Object error, {
    required bool streamsAnyAyah,
  }) => switch (error) {
    SessionConfigException() => SessionFailure.configuration,
    _ when streamsAnyAyah => SessionFailure.audioUnreachable,
    _ => SessionFailure.unknown,
  };

  Future<void> togglePlayPause() async {
    if (!state.isActive) return;
    if (state.finished) {
      await _player.stop();
      await _player.play();
      return;
    }
    await (state.playing ? _player.pause() : _player.play());
  }

  Future<void> nextStep() => _player.skipToNextStep();

  Future<void> previousStep() => _player.skipToPreviousStep();

  /// Ends the session: what was recited is written down, the lock screen is
  /// cleared, and the bar goes back to offering a start.
  Future<void> stop() async {
    _pauseTimer?.cancel();
    await _unitSub?.cancel();
    await _stateSub?.cancel();
    _unitSub = null;
    _stateSub = null;
    await _player.endSession();
    await _recordProgress();
    if (isClosed) return;
    emit(state.copyWith(phase: SessionPhase.idle, clearSession: true));
  }

  Future<void> setKeepAwake(bool enabled) async {
    await _keepAwake.setEnabled(enabled);
    if (!isClosed) emit(state.copyWith(keepAwake: enabled));
  }

  /// Writes what was actually recited, then clears the tally so a stop
  /// followed by a completion cannot double-count.
  Future<void> _recordProgress() async {
    if (_played.isEmpty) return;
    final Map<AyahRef, int> tally = Map<AyahRef, int>.of(_played);
    _played.clear();
    final DateTime now = DateTime.now();
    for (final MapEntry<AyahRef, int> e in tally.entries) {
      await _progress.recordRepeats(e.key.surah, e.key.ayah, e.value, at: now);
    }
  }

  // --- plumbing ------------------------------------------------------------

  void _change(SessionConfig Function(SessionConfig) change) {
    final SessionConfig? c = state.config;
    if (c == null) return;
    _apply(change(c), rangeChosen: state.rangeChosen);
  }

  void _apply(SessionConfig config, {required bool rangeChosen}) {
    final (SessionPlan? plan, String? error) = _builder
        .build(config, ayahCounts: state.ayahCounts)
        .fold((Failure f) => (null, f.message), (SessionPlan p) => (p, null));
    emit(
      state.copyWith(
        config: config,
        rangeChosen: rangeChosen,
        plan: plan,
        clearPlan: plan == null,
        configError: error,
        clearConfigError: error == null,
      ),
    );
    unawaited(_estimate());
  }

  SessionPlan? _build(SessionConfig config) => _builder
      .build(config, ayahCounts: state.ayahCounts)
      .fold((Failure _) => null, (SessionPlan plan) => plan);

  /// Adds up real clip lengths for the summary. Only when every surah of the
  /// range can be measured on the device; otherwise there is no honest number
  /// and none is shown.
  Future<void> _estimate() async {
    final int token = ++_estimateToken;
    final SessionPlan? plan = state.plan;
    final Reciter? reciter = state.reciter;
    if (plan == null || reciter == null) {
      if (state.estimatedDuration != null) {
        emit(state.copyWith(clearEstimate: true));
      }
      return;
    }

    final Map<AyahRef, Duration> clips = <AyahRef, Duration>{};
    try {
      for (final Surah surah in state.rangeSurahs) {
        final Map<int, Duration> one = await _durations.durationsFor(
          reciter: reciter,
          surah: surah,
        );
        if (one.isEmpty) {
          clips.clear();
          break;
        }
        for (final MapEntry<int, Duration> e in one.entries) {
          clips[AyahRef(surah.number, e.key)] = e.value;
        }
      }
    } on Object {
      clips.clear();
    }
    // The reader has moved on to another range while this was measuring.
    if (isClosed || token != _estimateToken || state.plan != plan) return;

    final bool complete = plan.units.every(
      (PlaybackUnit u) => clips.containsKey(u.ref),
    );
    emit(
      complete
          ? state.copyWith(
              estimatedDuration: plan.estimatedDuration(clipDurations: clips),
            )
          : state.copyWith(clearEstimate: true),
    );
  }

  @override
  Future<void> close() async {
    _pauseTimer?.cancel();
    await _unitSub?.cancel();
    await _stateSub?.cancel();
    await _recordProgress();
    // Only undone if it was done: the screen is not this cubit's to dim
    // otherwise.
    if (state.keepAwake) await _keepAwake.setEnabled(false);
    // Leaving the reading screen ends the session, and the lock screen should
    // stop offering to resume it.
    if (state.phase != SessionPhase.idle) await _player.endSession();
    return super.close();
  }
}
