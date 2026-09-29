import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reading_position.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/entities/session_config.dart';
import '../../../services/app_version_service.dart';
import '../../../services/audio/reciter_catalog.dart';
import 'settings_state.dart';

/// Owns the persisted settings. Held app-wide rather than per-screen, because
/// the theme and the home view are read outside the settings screen.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsRepository settingsRepository,
    required ReciterCatalog reciterCatalog,
    QuranRepository? quranRepository,
    AppVersionService? appVersionService,
  }) : _settings = settingsRepository,
       _quran = quranRepository,
       _appVersion = appVersionService,
       _reciters = reciterCatalog,
       super(const SettingsState()) {
    // Someone else saved — a session keeping its values as defaults, say.
    // Taken up at once, so that the next save from here does not write an
    // older copy back over theirs.
    _saved = _settings.changes.listen((AppSettings saved) {
      if (saved != state.settings) emit(state.copyWith(settings: saved));
    });
  }

  StreamSubscription<AppSettings>? _saved;

  @override
  Future<void> close() async {
    await _saved?.cancel();
    return super.close();
  }

  final SettingsRepository _settings;
  final ReciterCatalog _reciters;

  /// For the text-size preview's sample ayah. Optional: without it the
  /// control works and simply shows no sample.
  final QuranRepository? _quran;

  /// Optional, so that the many tests of the settings themselves need no
  /// platform to ask.
  final AppVersionService? _appVersion;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    final settingsResult = await _settings.read();
    final AppSettings settings = settingsResult.getOrElse(
      () => const AppSettings(),
    );
    // Said at once, before the reciters: they may wait on the network, and
    // the theme, the home view and whether the introduction has been seen
    // are all needed sooner than that.
    emit(
      state.copyWith(
        settings: settings,
        settingsRead: settingsResult.isRight(),
      ),
    );

    // Off to the side: a line of small print, and a sample line for the text
    // size, must not hold the settings up.
    unawaited(_readVersion());
    unawaited(_loadPreviewAyah());

    final recitersResult = await _reciters.reciters();
    recitersResult.fold(
      (Failure f) => emit(
        state.copyWith(
          status: LoadStatus.failure,
          settings: settings,
          errorMessage: f.message,
        ),
      ),
      (List<Reciter> reciters) => emit(
        state.copyWith(
          status: LoadStatus.ready,
          settings: settings,
          reciters: reciters,
        ),
      ),
    );
  }

  /// The text-size control previews the real mushaf face on real scripture:
  /// ayah 1 of the first surah in the catalog, whichever that is
  /// (CLAUDE.md A.2 rule 2). A preview failure is not worth surfacing — the
  /// control still works, it simply renders without a sample.
  Future<void> _loadPreviewAyah() async {
    final QuranRepository? quran = _quran;
    if (quran == null || state.previewAyah != null) return;
    final List<Surah> surahs = (await quran.getSurahs()).getOrElse(
      () => const <Surah>[],
    );
    if (surahs.isEmpty) return;

    final List<Ayah> ayahs = (await quran.getAyahRange(
      surahs.first.number,
      startAyah: 1,
      endAyah: 1,
    )).getOrElse(() => const <Ayah>[]);
    if (ayahs.isEmpty || isClosed) return;

    emit(state.copyWith(previewAyah: ayahs.first));
  }

  Future<void> _readVersion() async {
    final InstalledVersion? version = await _appVersion?.read();
    if (version != null && !isClosed) {
      emit(state.copyWith(appVersion: version));
    }
  }

  /// An optional update has just been put off; it is not mentioned again for
  /// a day.
  Future<void> markUpdatePrompted(DateTime at) =>
      _save(state.settings.copyWith(updatePromptedAt: at));

  /// The reader says they stopped here. One mark; a new one replaces it.
  Future<void> markReading(ReadingPosition position) =>
      _save(state.settings.copyWith(readingMark: position));

  Future<void> clearReadingMark() =>
      _save(state.settings.copyWith(clearReadingMark: true));

  Future<void> setReciter(String reciterId) =>
      _save(state.settings.copyWith(reciterId: reciterId));

  /// The bitrate downloads and streams ask for. Nothing already on the device
  /// is re-fetched or discarded: this is a preference for what happens next.
  Future<void> setAudioQuality(AudioQuality quality) =>
      _save(state.settings.copyWith(audioQuality: quality));

  Future<void> setDownloadOverWifiOnly(bool value) =>
      _save(state.settings.copyWith(downloadOverWifiOnly: value));

  /// The introduction has been read through, or skipped: either way it is
  /// not shown on its own again. It stays one tap away, under How to use.
  Future<void> markOnboardingSeen() =>
      _save(state.settings.copyWith(onboardingSeen: true));

  Future<void> setDefaultRepeatCount(int value) => _save(
    state.settings.copyWith(
      defaultRepeatCount: value.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
    ),
  );

  /// Changing the mode also releases an explicit final-full-pass choice, so
  /// the toggle follows the new mode's own default until the user overrides it
  /// again. Without this, a `true` set under [ConnectMode.none] would silently
  /// append a duplicate pass to every continuous session.
  Future<void> setDefaultConnectMode(ConnectMode mode) => _save(
    state.settings.copyWith(
      defaultConnectMode: mode,
      clearDefaultFinalFullPass: true,
    ),
  );

  Future<void> setDefaultFinalFullPass(bool value) =>
      _save(state.settings.copyWith(defaultFinalFullPass: value));

  Future<void> setDefaultIntraBlockPause(int ms) =>
      _save(state.settings.copyWith(defaultIntraBlockPauseMs: _pause(ms)));

  Future<void> setDefaultBetweenRepeatPause(int ms) =>
      _save(state.settings.copyWith(defaultBetweenRepeatPauseMs: _pause(ms)));

  Future<void> setDefaultBetweenStepsPause(int ms) =>
      _save(state.settings.copyWith(defaultBetweenStepsPauseMs: _pause(ms)));

  Future<void> setDefaultPlaybackSpeed(double speed) => _save(
    state.settings.copyWith(
      defaultPlaybackSpeed: speed.clamp(
        SessionConfig.minPlaybackSpeed,
        SessionConfig.maxPlaybackSpeed,
      ),
    ),
  );

  Future<void> setDefaultRangeBehaviour(RangeBehaviour behaviour) =>
      _save(state.settings.copyWith(defaultRangeBehaviour: behaviour));

  Future<void> setHomeViewMode(HomeViewMode mode) =>
      _save(state.settings.copyWith(homeViewMode: mode));

  /// Remembers the range a session was actually started with, so
  /// [RangeBehaviour.lastUsed] has something to offer next time.
  Future<void> rememberRange(
    int surahNumber, {
    required int startAyah,
    required int endAyah,
  }) => _save(
    state.settings.rememberRange(
      surahNumber,
      AyahRange(startAyah: startAyah, endAyah: endAyah),
    ),
  );

  /// Writes a whole set of session defaults at once — the reader's drawer
  /// "save as default" action, which would otherwise fire six writes and six
  /// rebuilds for one tap.
  Future<void> saveSessionDefaults({
    required int repeatCount,
    required ConnectMode connectMode,
    required bool finalFullPass,
    required int intraBlockPauseMs,
    required int betweenRepeatPauseMs,
    required int betweenStepsPauseMs,
    required double playbackSpeed,
  }) => _save(
    state.settings.copyWith(
      defaultRepeatCount: repeatCount.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
      defaultConnectMode: connectMode,
      defaultFinalFullPass: finalFullPass,
      defaultIntraBlockPauseMs: _pause(intraBlockPauseMs),
      defaultBetweenRepeatPauseMs: _pause(betweenRepeatPauseMs),
      defaultBetweenStepsPauseMs: _pause(betweenStepsPauseMs),
      defaultPlaybackSpeed: playbackSpeed.clamp(
        SessionConfig.minPlaybackSpeed,
        SessionConfig.maxPlaybackSpeed,
      ),
    ),
  );

  /// A pause is a length of silence: negative is meaningless, and the plan
  /// builder rejects it outright.
  static int _pause(int ms) => ms < 0 ? 0 : ms;

  Future<void> setThemeMode(AppThemeMode mode) =>
      _save(state.settings.copyWith(themeMode: mode));

  Future<void> setArabicFontSize(double size) => _save(
    state.settings.copyWith(
      arabicFontSize: size.clamp(
        AppSettings.minArabicFontSize,
        AppSettings.maxArabicFontSize,
      ),
    ),
  );

  Future<void> _save(AppSettings next) async {
    // Show the change immediately; a storage failure surfaces as a message
    // rather than a control that silently springs back.
    emit(state.copyWith(settings: next, errorMessage: null));

    final result = await _settings.save(next);
    result.fold(
      (Failure f) => emit(state.copyWith(errorMessage: f.message)),
      (_) {},
    );
  }
}
