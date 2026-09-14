import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/engine/repetition_plan_builder.dart';
import '../../../domain/entities/session_config.dart';
import '../../../domain/entities/session_plan.dart';
import '../../../services/audio/ayah_duration_service.dart';
import 'reader_state.dart';

/// Owns one surah's reading page and the session that will be started from it.
///
/// This replaces `SessionSetupCubit`: the same plan-building and the same
/// measured duration estimate, but the config is now something the reader
/// nudges from a drawer beside the text rather than a form standing between
/// them and the surah.
class ReaderCubit extends Cubit<ReaderState> {
  ReaderCubit({
    required QuranRepository quranRepository,
    required SettingsRepository settingsRepository,
    required AyahDurationService durationService,
    required RepetitionPlanBuilder planBuilder,
  }) : _quran = quranRepository,
       _settings = settingsRepository,
       _durations = durationService,
       _builder = planBuilder,
       super(const ReaderState());

  final QuranRepository _quran;
  final SettingsRepository _settings;
  final AyahDurationService _durations;
  final RepetitionPlanBuilder _builder;

  Future<void> load(int surahNumber) async {
    emit(state.copyWith(status: LoadStatus.loading));

    final surahResult = await _quran.getSurah(surahNumber);
    final Surah? surah = surahResult.fold((Failure f) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: f.message));
      return null;
    }, (Surah s) => s);
    if (surah == null) return;

    final recitersResult = await _quran.getReciters();
    final List<Reciter>? reciters = recitersResult.fold((Failure f) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: f.message));
      return null;
    }, (List<Reciter> r) => r);
    if (reciters == null) return;

    final List<Reciter> withSurah = reciters
        .where((Reciter r) => r.hasSurah(surahNumber))
        .toList();
    if (withSurah.isEmpty) {
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          errorMessage:
              'No reciter in the catalog has audio for surah $surahNumber.',
        ),
      );
      return;
    }

    final AppSettings settings = (await _settings.read()).getOrElse(
      () => const AppSettings(),
    );

    // The chosen reciter, or the first that has this surah when the choice is
    // unset or no longer covers it.
    final Reciter reciter = withSurah.firstWhere(
      (Reciter r) => r.id == settings.reciterId,
      orElse: () => withSurah.first,
    );

    final ayahsResult = await _quran.getAyahs(surahNumber);
    final List<Ayah>? ayahs = ayahsResult.fold((Failure f) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: f.message));
      return null;
    }, (List<Ayah> a) => a);
    if (ayahs == null) return;

    final String? bismillahText = surah.needsBismillahPreamble
        ? await _loadBismillahText()
        : null;

    final Map<int, Duration> durations;
    try {
      durations = await _durations.durationsFor(reciter: reciter, surah: surah);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: '$e'));
      return;
    }

    // A remembered range only applies while it still fits the surah — a
    // catalog correction to ayahCount must never hand back an out-of-bounds
    // selection.
    final AyahRange? remembered = settings.rememberedRangeFor(surahNumber);
    final bool rememberedFits =
        remembered != null &&
        remembered.startAyah >= 1 &&
        remembered.endAyah <= surah.ayahCount &&
        remembered.startAyah <= remembered.endAyah;

    final SessionConfig config = _configFrom(
      settings,
      surahNumber: surahNumber,
      startAyah: rememberedFits ? remembered.startAyah : 1,
      endAyah: rememberedFits ? remembered.endAyah : surah.ayahCount,
    );

    emit(
      _withPlan(
        state.copyWith(
          status: LoadStatus.ready,
          surah: surah,
          reciter: reciter,
          ayahs: ayahs,
          bismillahText: bismillahText,
          ayahDurations: durations,
          defaults: settings,
          config: config,
          selectionPhase: rememberedFits
              ? SelectionPhase.ranged
              : SelectionPhase.wholeSurah,
        ),
      ),
    );
  }

  /// The basmala, verbatim, for surahs that recite it unnumbered.
  ///
  /// It is not a string literal anywhere in this app. `bismillahMode` is the
  /// catalog's own statement that some surah numbers these exact words as its
  /// ayah 1, so that ayah *is* the verbatim source, and this reads it from the
  /// asset like any other scripture. Which surah that is comes from the
  /// catalog, never from Dart (CLAUDE.md A.2 rules 1 and 2).
  ///
  /// Returns null if the catalog has no such surah, or if the read fails. The
  /// caller then draws no header, which is the only honest option: an absent
  /// header costs a line of presentation, and a typed one would be scripture
  /// this app invented.
  Future<String?> _loadBismillahText() async {
    final surahsResult = await _quran.getSurahs();
    final List<Surah> surahs = surahsResult.getOrElse(() => const <Surah>[]);

    final Surah? source = surahs
        .where((Surah s) => s.bismillahMode == BismillahMode.countedAsAyah1)
        .firstOrNull;
    if (source == null) return null;

    final ayahResult = await _quran.getAyahRange(
      source.number,
      startAyah: 1,
      endAyah: 1,
    );
    final List<Ayah> found = ayahResult.getOrElse(() => const <Ayah>[]);
    return found.isEmpty ? null : found.first.text;
  }

  /// Builds a config from persisted defaults. Used on load and by "reset".
  static SessionConfig _configFrom(
    AppSettings settings, {
    required int surahNumber,
    required int startAyah,
    required int endAyah,
  }) => SessionConfig(
    surahNumber: surahNumber,
    startAyah: startAyah,
    endAyah: endAyah,
    repeatCount: settings.defaultRepeatCount,
    connectMode: settings.defaultConnectMode,
    // Null lets SessionConfig apply the mode's own default.
    finalFullPass: settings.defaultFinalFullPass,
    intraBlockPauseMs: settings.defaultIntraBlockPauseMs,
    betweenRepeatPauseMs: settings.defaultBetweenRepeatPauseMs,
    betweenStepsPauseMs: settings.defaultBetweenStepsPauseMs,
    playbackSpeed: settings.defaultPlaybackSpeed,
  );

  // --- selection ------------------------------------------------------------

  /// Tap-to-select, as the reader experiences it:
  ///
  ///  * nothing selected -> this ayah becomes both ends of the range;
  ///  * one end chosen   -> this ayah becomes the other end;
  ///  * an endpoint of an existing range -> selection clears to the whole
  ///    surah, which is the only way back out without a second control;
  ///  * anything else while a range exists -> starts a fresh selection here,
  ///    rather than silently extending a range the reader has finished with.
  void tapAyah(int ayahNumber) {
    final SessionConfig? config = state.config;
    final Surah? surah = state.surah;
    if (config == null || surah == null) return;

    if (state.isSelectionEndpoint(ayahNumber)) {
      _selectWholeSurah();
      return;
    }

    if (state.selectionPhase == SelectionPhase.anchored) {
      final int anchor = config.startAyah;
      _apply(
        config.copyWith(
          startAyah: anchor < ayahNumber ? anchor : ayahNumber,
          endAyah: anchor < ayahNumber ? ayahNumber : anchor,
        ),
        phase: SelectionPhase.ranged,
      );
      return;
    }

    _apply(
      config.copyWith(startAyah: ayahNumber, endAyah: ayahNumber),
      phase: SelectionPhase.anchored,
    );
  }

  /// Drops the selection back to the whole surah.
  void clearSelection() => _selectWholeSurah();

  void _selectWholeSurah() {
    final SessionConfig? config = state.config;
    final Surah? surah = state.surah;
    if (config == null || surah == null) return;
    _apply(
      config.copyWith(startAyah: 1, endAyah: surah.ayahCount),
      phase: SelectionPhase.wholeSurah,
    );
  }

  /// The drawer's from/to steppers. An explicit range, so the highlight shows
  /// even when it happens to span the whole surah.
  void setRange({int? startAyah, int? endAyah}) {
    final SessionConfig? config = state.config;
    final Surah? surah = state.surah;
    if (config == null || surah == null) return;

    int start = (startAyah ?? config.startAyah).clamp(1, surah.ayahCount);
    int end = (endAyah ?? config.endAyah).clamp(1, surah.ayahCount);

    // Nudge the other end rather than letting the pickers cross over.
    if (startAyah != null && start > end) end = start;
    if (endAyah != null && end < start) start = end;

    _apply(
      config.copyWith(startAyah: start, endAyah: end),
      phase: SelectionPhase.ranged,
    );
  }

  // --- session tuning -------------------------------------------------------

  void setRepeatCount(int value) => _applyFrom(
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
  void setConnectMode(ConnectMode mode) => _applyFrom(
    (SessionConfig c) => SessionConfig(
      surahNumber: c.surahNumber,
      startAyah: c.startAyah,
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
      _applyFrom((SessionConfig c) => c.copyWith(finalFullPass: value));

  void setPlayIstiadhah(bool value) =>
      _applyFrom((SessionConfig c) => c.copyWith(playIstiadhah: value));

  void setIntraBlockPause(int ms) =>
      _applyFrom((SessionConfig c) => c.copyWith(intraBlockPauseMs: ms));

  void setBetweenRepeatPause(int ms) =>
      _applyFrom((SessionConfig c) => c.copyWith(betweenRepeatPauseMs: ms));

  void setBetweenStepsPause(int ms) =>
      _applyFrom((SessionConfig c) => c.copyWith(betweenStepsPauseMs: ms));

  void setPlaybackSpeed(double speed) =>
      _applyFrom((SessionConfig c) => c.copyWith(playbackSpeed: speed));

  // --- defaults -------------------------------------------------------------

  /// Reloads the session values from the persisted defaults, leaving the ayah
  /// selection alone: the reader picked that on this page and would not expect
  /// a "reset" of the tuning to also throw away where they were reading.
  void resetToDefaults() {
    final SessionConfig? config = state.config;
    if (config == null) return;
    _apply(
      _configFrom(
        state.defaults,
        surahNumber: config.surahNumber,
        startAyah: config.startAyah,
        endAyah: config.endAyah,
      ),
      phase: state.selectionPhase,
    );
  }

  /// Writes the current session values back as the defaults for every surah.
  ///
  /// Without this, drawer edits are deliberately per-session and vanish when
  /// the screen closes.
  Future<void> saveAsDefaults() async {
    final SessionConfig? config = state.config;
    if (config == null) return;

    final AppSettings next = state.defaults.copyWith(
      defaultRepeatCount: config.repeatCount,
      defaultConnectMode: config.connectMode,
      defaultFinalFullPass: config.finalFullPass,
      defaultIntraBlockPauseMs: config.intraBlockPauseMs,
      defaultBetweenRepeatPauseMs: config.betweenRepeatPauseMs,
      defaultBetweenStepsPauseMs: config.betweenStepsPauseMs,
      defaultPlaybackSpeed: config.playbackSpeed,
    );

    final result = await _settings.save(next);
    if (isClosed) return;
    result.fold(
      (Failure f) => emit(state.copyWith(errorMessage: f.message)),
      (_) => emit(
        state.copyWith(defaults: next, defaultsSavedAt: DateTime.now()),
      ),
    );
  }

  /// Records the range a session is actually started with, so
  /// [RangeBehaviour.lastUsed] has something to offer next time.
  ///
  /// Fire-and-forget on the way to the player: a failed write costs a
  /// remembered range, which is not worth blocking the session over.
  Future<void> rememberStartedRange() async {
    final SessionConfig? config = state.config;
    if (config == null) return;
    if (state.defaults.defaultRangeBehaviour != RangeBehaviour.lastUsed) return;

    final AppSettings next = state.defaults.rememberRange(
      config.surahNumber,
      AyahRange(startAyah: config.startAyah, endAyah: config.endAyah),
    );
    final result = await _settings.save(next);
    if (isClosed) return;
    result.fold((Failure _) {}, (_) => emit(state.copyWith(defaults: next)));
  }

  // --- plumbing -------------------------------------------------------------

  void _applyFrom(SessionConfig Function(SessionConfig) change) {
    final SessionConfig? config = state.config;
    if (config == null) return;
    _apply(change(config), phase: state.selectionPhase);
  }

  void _apply(SessionConfig config, {required SelectionPhase phase}) => emit(
    _withPlan(state.copyWith(config: config, selectionPhase: phase)),
  );

  /// Rebuilds the plan and the duration estimate for the state's config.
  ReaderState _withPlan(ReaderState next) {
    final SessionConfig? config = next.config;
    final Surah? surah = next.surah;
    if (config == null || surah == null) return next;

    return _builder
        .build(config, surahAyahCount: surah.ayahCount)
        .fold(
          (Failure failure) => next.copyWith(configError: failure.message),
          (SessionPlan plan) => next.copyWith(
            plan: plan,
            estimatedDuration: plan.estimatedDuration(
              ayahDurations: next.ayahDurations,
            ),
          ),
        );
  }
}
