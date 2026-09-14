import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.status = LoadStatus.initial,
    this.settings = const AppSettings(),
    this.reciters = const <Reciter>[],
    this.previewAyah,
    this.errorMessage,
  });

  final LoadStatus status;
  final AppSettings settings;
  final List<Reciter> reciters;

  /// A real ayah, so the font-size control previews the mushaf face at the
  /// chosen size rather than approximating it with UI text. Taken from the
  /// first surah in the catalog — no surah number is hardcoded
  /// (CLAUDE.md A.2 rule 2). Null until the catalog loads, or if it fails.
  final Ayah? previewAyah;

  final String? errorMessage;

  SettingsState copyWith({
    LoadStatus? status,
    AppSettings? settings,
    List<Reciter>? reciters,
    Ayah? previewAyah,
    String? errorMessage,
  }) => SettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    reciters: reciters ?? this.reciters,
    previewAyah: previewAyah ?? this.previewAyah,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    settings,
    reciters,
    previewAyah,
    errorMessage,
  ];
}
