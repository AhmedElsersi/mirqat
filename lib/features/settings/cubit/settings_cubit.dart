import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/entities/session_config.dart';
import '../../../services/audio/reciter_catalog.dart';
import 'settings_state.dart';

/// Owns the persisted settings. Held app-wide rather than per-screen, because
/// the theme and the Arabic font size are read by every screen.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsRepository settingsRepository,
    required QuranRepository quranRepository,
    required ReciterCatalog reciterCatalog,
  }) : _settings = settingsRepository,
       _quran = quranRepository,
       _reciters = reciterCatalog,
       super(const SettingsState());

  final SettingsRepository _settings;
  final QuranRepository _quran;
  final ReciterCatalog _reciters;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    final settingsResult = await _settings.read();
    final AppSettings settings = settingsResult.getOrElse(
      () => const AppSettings(),
    );

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
        SettingsState(
          status: LoadStatus.ready,
          settings: settings,
          reciters: reciters,
          previewAyah: state.previewAyah,
        ),
      ),
    );

    await _loadPreviewAyah();
  }

  /// The font-size control previews the real mushaf face on real scripture.
  /// A preview failure is not worth surfacing — the control still works, it
  /// simply renders without a sample.
  Future<void> _loadPreviewAyah() async {
    final surahsResult = await _quran.getSurahs();
    final List<Surah> surahs = surahsResult.getOrElse(() => const <Surah>[]);
    if (surahs.isEmpty) return;

    final ayahsResult = await _quran.getAyahRange(
      surahs.first.number,
      startAyah: 1,
      endAyah: 1,
    );
    final List<Ayah> ayahs = ayahsResult.getOrElse(() => const <Ayah>[]);
    if (ayahs.isEmpty || isClosed) return;

    emit(state.copyWith(previewAyah: ayahs.first));
  }

  Future<void> setReciter(String reciterId) =>
      _save(state.settings.copyWith(reciterId: reciterId));

  /// The bitrate downloads and streams ask for. Nothing already on the device
  /// is re-fetched or discarded: this is a preference for what happens next.
  Future<void> setAudioQuality(AudioQuality quality) =>
      _save(state.settings.copyWith(audioQuality: quality));

  Future<void> setDownloadOverWifiOnly(bool value) =>
      _save(state.settings.copyWith(downloadOverWifiOnly: value));

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
