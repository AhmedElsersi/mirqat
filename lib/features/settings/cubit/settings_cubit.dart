import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/entities/session_config.dart';
import 'settings_state.dart';

/// Owns the persisted settings. Held app-wide rather than per-screen, because
/// the theme and the Arabic font size are read by every screen.
class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit({
    required SettingsRepository settingsRepository,
    required QuranRepository quranRepository,
  }) : _settings = settingsRepository,
       _quran = quranRepository,
       super(const SettingsState());

  final SettingsRepository _settings;
  final QuranRepository _quran;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    final settingsResult = await _settings.read();
    final AppSettings settings = settingsResult.getOrElse(
      () => const AppSettings(),
    );

    final recitersResult = await _quran.getReciters();
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
        ),
      ),
    );
  }

  Future<void> setReciter(String reciterId) =>
      _save(state.settings.copyWith(reciterId: reciterId));

  Future<void> setDefaultRepeatCount(int value) => _save(
    state.settings.copyWith(
      defaultRepeatCount: value.clamp(
        SessionConfig.minRepeatCount,
        SessionConfig.maxRepeatCount,
      ),
    ),
  );

  Future<void> setDefaultConnectMode(ConnectMode mode) =>
      _save(state.settings.copyWith(defaultConnectMode: mode));

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
