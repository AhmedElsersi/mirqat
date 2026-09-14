import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/session_config.dart';
import '../../../domain/entities/session_plan.dart';

/// Where the reader's tap-to-select has got to.
enum SelectionPhase {
  /// No explicit selection: the range is the whole surah.
  wholeSurah,

  /// One ayah tapped. It is both ends of the range until a second tap widens
  /// it, so the play button always has a valid range to work with.
  anchored,

  /// Both ends chosen, by tapping or from the drawer's steppers.
  ranged,
}

class ReaderState extends Equatable {
  const ReaderState({
    this.status = LoadStatus.initial,
    this.surah,
    this.reciter,
    this.ayahs = const <Ayah>[],
    this.bismillahText,
    this.ayahDurations = const <int, Duration>{},
    this.config,
    this.plan,
    this.estimatedDuration,
    this.selectionPhase = SelectionPhase.wholeSurah,
    this.defaults = const AppSettings(),
    this.configError,
    this.errorMessage,
    this.defaultsSavedAt,
  });

  final LoadStatus status;
  final Surah? surah;
  final Reciter? reciter;

  /// Every ayah of the surah, in order — the reading area shows all of them
  /// whatever the selection is.
  final List<Ayah> ayahs;

  /// The basmala, read verbatim out of the ayah assets for surahs that recite
  /// it as an unnumbered preamble. Null when the catalog holds no surah that
  /// numbers it as ayah 1, and so offers no verbatim source — the header is
  /// then not drawn rather than invented (CLAUDE.md A.2 rule 1).
  final String? bismillahText;

  /// Real clip lengths, so the drawer's summary is measured rather than
  /// guessed.
  final Map<int, Duration> ayahDurations;

  /// The live session config. Drawer edits land here and are discarded when
  /// the screen closes, unless explicitly saved as defaults.
  final SessionConfig? config;

  /// Rebuilt on every config change, so the summary and the play button are
  /// always talking about the same plan.
  final SessionPlan? plan;
  final Duration? estimatedDuration;

  final SelectionPhase selectionPhase;

  /// The persisted defaults this screen opened with, kept so "reset" has
  /// something to reset *to* without a second read.
  final AppSettings defaults;

  /// Why the current config cannot produce a plan, if it cannot.
  final String? configError;

  final String? errorMessage;

  /// Bumped when the drawer writes the current values back as defaults, so the
  /// screen can confirm it once. A timestamp rather than a bool: two saves in
  /// a row are two separate confirmations.
  final DateTime? defaultsSavedAt;

  bool get canStart => plan != null && configError == null;

  bool get isWholeSurahSelected => selectionPhase == SelectionPhase.wholeSurah;

  /// Whether [ayahNumber] is inside the selected range. With no explicit
  /// selection nothing is highlighted — the whole surah is implied, and
  /// tinting every line says nothing.
  bool isSelected(int ayahNumber) {
    final SessionConfig? c = config;
    if (c == null || isWholeSurahSelected) return false;
    return ayahNumber >= c.startAyah && ayahNumber <= c.endAyah;
  }

  /// Whether tapping [ayahNumber] would clear the selection — true for either
  /// endpoint of an explicit range.
  bool isSelectionEndpoint(int ayahNumber) {
    final SessionConfig? c = config;
    if (c == null || isWholeSurahSelected) return false;
    return ayahNumber == c.startAyah || ayahNumber == c.endAyah;
  }

  ReaderState copyWith({
    LoadStatus? status,
    Surah? surah,
    Reciter? reciter,
    List<Ayah>? ayahs,
    String? bismillahText,
    Map<int, Duration>? ayahDurations,
    SessionConfig? config,
    SessionPlan? plan,
    Duration? estimatedDuration,
    SelectionPhase? selectionPhase,
    AppSettings? defaults,
    String? configError,
    String? errorMessage,
    DateTime? defaultsSavedAt,
  }) => ReaderState(
    status: status ?? this.status,
    surah: surah ?? this.surah,
    reciter: reciter ?? this.reciter,
    ayahs: ayahs ?? this.ayahs,
    bismillahText: bismillahText ?? this.bismillahText,
    ayahDurations: ayahDurations ?? this.ayahDurations,
    config: config ?? this.config,
    // plan, estimatedDuration and configError are recomputed from the config
    // on every change, so they are replaced rather than merged: carrying a
    // stale plan forward would leave the play button pointing at a range the
    // reader has already changed.
    plan: plan,
    estimatedDuration: estimatedDuration,
    selectionPhase: selectionPhase ?? this.selectionPhase,
    defaults: defaults ?? this.defaults,
    configError: configError,
    errorMessage: errorMessage ?? this.errorMessage,
    defaultsSavedAt: defaultsSavedAt ?? this.defaultsSavedAt,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    surah,
    reciter,
    ayahs,
    bismillahText,
    ayahDurations,
    config,
    plan,
    estimatedDuration,
    selectionPhase,
    defaults,
    configError,
    errorMessage,
    defaultsSavedAt,
  ];
}
