import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.status = LoadStatus.initial,
    this.settings = const AppSettings(),
    this.reciters = const <Reciter>[],
    this.errorMessage,
  });

  final LoadStatus status;
  final AppSettings settings;
  final List<Reciter> reciters;
  final String? errorMessage;

  SettingsState copyWith({
    LoadStatus? status,
    AppSettings? settings,
    List<Reciter>? reciters,
    String? errorMessage,
  }) => SettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    reciters: reciters ?? this.reciters,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    settings,
    reciters,
    errorMessage,
  ];
}
