import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/engine/repetition_plan_builder.dart';
import '../../../domain/entities/session_config.dart';
import '../../../domain/entities/session_plan.dart';
import '../../../services/audio/ayah_duration_service.dart';
import 'session_setup_state.dart';

class SessionSetupCubit extends Cubit<SessionSetupState> {
  SessionSetupCubit({
    required QuranRepository quranRepository,
    required SettingsRepository settingsRepository,
    required AyahDurationService durationService,
    required RepetitionPlanBuilder planBuilder,
  }) : _quran = quranRepository,
       _settings = settingsRepository,
       _durations = durationService,
       _builder = planBuilder,
       super(const SessionSetupState());

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

    Map<int, Duration> durations;
    try {
      durations = await _durations.durationsFor(reciter: reciter, surah: surah);
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: '$e'));
      return;
    }

    final SessionConfig config = SessionConfig(
      surahNumber: surahNumber,
      startAyah: 1,
      endAyah: surah.ayahCount,
      repeatCount: settings.defaultRepeatCount,
      connectMode: settings.defaultConnectMode,
    );

    emit(
      _withPlan(
        state.copyWith(
          status: LoadStatus.ready,
          surah: surah,
          reciter: reciter,
          ayahs: ayahs,
          ayahDurations: durations,
          config: config,
        ),
      ),
    );
  }

  void setRange({int? startAyah, int? endAyah}) {
    final SessionConfig? config = state.config;
    final Surah? surah = state.surah;
    if (config == null || surah == null) return;

    int start = startAyah ?? config.startAyah;
    int end = endAyah ?? config.endAyah;

    // Nudge the other end rather than letting the pickers cross over.
    if (startAyah != null && start > end) end = start;
    if (endAyah != null && end < start) start = end;

    _update(config.copyWith(startAyah: start, endAyah: end));
  }

  void setRepeatCount(int value) => _updateFrom(
    (SessionConfig c) => c.copyWith(
      repeatCount: value.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
    ),
  );

  void setConnectMode(ConnectMode mode) => _updateFrom(
    // finalFullPass follows the mode's own default whenever the mode changes.
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
      _updateFrom((SessionConfig c) => c.copyWith(finalFullPass: value));

  void setPlayIstiadhah(bool value) =>
      _updateFrom((SessionConfig c) => c.copyWith(playIstiadhah: value));

  void setIntraBlockPause(int ms) =>
      _updateFrom((SessionConfig c) => c.copyWith(intraBlockPauseMs: ms));

  void setBetweenRepeatPause(int ms) =>
      _updateFrom((SessionConfig c) => c.copyWith(betweenRepeatPauseMs: ms));

  void setBetweenStepsPause(int ms) =>
      _updateFrom((SessionConfig c) => c.copyWith(betweenStepsPauseMs: ms));

  void setPlaybackSpeed(double speed) =>
      _updateFrom((SessionConfig c) => c.copyWith(playbackSpeed: speed));

  void _updateFrom(SessionConfig Function(SessionConfig) change) {
    final SessionConfig? config = state.config;
    if (config == null) return;
    _update(change(config));
  }

  void _update(SessionConfig config) =>
      emit(_withPlan(state.copyWith(config: config)));

  /// Rebuilds the plan and the duration estimate for the state's config.
  SessionSetupState _withPlan(SessionSetupState next) {
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
