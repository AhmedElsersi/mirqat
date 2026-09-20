import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../../services/app_version_service.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.status = LoadStatus.initial,
    this.settings = const AppSettings(),
    this.reciters = const <Reciter>[],
    this.settingsRead = false,
    this.appVersion,
    this.errorMessage,
  });

  final LoadStatus status;
  final AppSettings settings;
  final List<Reciter> reciters;

  /// Whether [settings] is what storage holds, rather than the defaults this
  /// state starts with. True well before [status] is ready: the reciters come
  /// from a catalog that may wait on the network, and what the reader chose
  /// last time should not have to wait with them.
  final bool settingsRead;

  /// The running app's own version, for the foot of the page. Null until it
  /// has been read, and where the platform will not say.
  final InstalledVersion? appVersion;

  final String? errorMessage;

  SettingsState copyWith({
    LoadStatus? status,
    AppSettings? settings,
    List<Reciter>? reciters,
    bool? settingsRead,
    InstalledVersion? appVersion,
    String? errorMessage,
  }) => SettingsState(
    status: status ?? this.status,
    settings: settings ?? this.settings,
    reciters: reciters ?? this.reciters,
    settingsRead: settingsRead ?? this.settingsRead,
    appVersion: appVersion ?? this.appVersion,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    settings,
    reciters,
    settingsRead,
    appVersion?.version,
    appVersion?.buildNumber,
    errorMessage,
  ];
}
