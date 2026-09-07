import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/session_config.dart';
import '../../../domain/entities/session_plan.dart';

class SessionSetupState extends Equatable {
  const SessionSetupState({
    this.status = LoadStatus.initial,
    this.surah,
    this.reciter,
    this.ayahs = const <Ayah>[],
    this.ayahDurations = const <int, Duration>{},
    this.config,
    this.plan,
    this.estimatedDuration,
    this.configError,
    this.errorMessage,
  });

  final LoadStatus status;
  final Surah? surah;
  final Reciter? reciter;
  final List<Ayah> ayahs;
  final Map<int, Duration> ayahDurations;
  final SessionConfig? config;

  /// Rebuilt on every config change, so the summary is always live.
  final SessionPlan? plan;
  final Duration? estimatedDuration;

  /// Why the current config cannot produce a plan, if it cannot.
  final String? configError;

  final String? errorMessage;

  bool get canStart => plan != null && configError == null;

  SessionSetupState copyWith({
    LoadStatus? status,
    Surah? surah,
    Reciter? reciter,
    List<Ayah>? ayahs,
    Map<int, Duration>? ayahDurations,
    SessionConfig? config,
    SessionPlan? plan,
    Duration? estimatedDuration,
    String? configError,
    String? errorMessage,
  }) => SessionSetupState(
    status: status ?? this.status,
    surah: surah ?? this.surah,
    reciter: reciter ?? this.reciter,
    ayahs: ayahs ?? this.ayahs,
    ayahDurations: ayahDurations ?? this.ayahDurations,
    config: config ?? this.config,
    plan: plan,
    estimatedDuration: estimatedDuration,
    configError: configError,
    errorMessage: errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    surah,
    reciter,
    ayahs,
    ayahDurations,
    config,
    plan,
    estimatedDuration,
    configError,
    errorMessage,
  ];
}
