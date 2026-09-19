import 'package:equatable/equatable.dart';

import '../../core/state/load_status.dart';
import '../../data/models/ayah.dart';
import '../../data/models/surah.dart';
import '../services/publish_guard.dart';
import '../services/segment_planner.dart';

/// A reciter the tool can publish for.
class AdminReciter extends Equatable {
  const AdminReciter({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.riwayah = '',
    this.imagePath,
    this.surahCount = 0,
    this.inManifest = false,
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String riwayah;

  /// Their portrait on the CDN, relative to the manifest's baseUrl.
  final String? imagePath;

  /// How many surahs they already have published.
  final int surahCount;

  /// Whether the published manifest already names them. A bundled reciter who
  /// is not in it yet still shows here, so their first surah can be published
  /// without inventing an id.
  final bool inManifest;

  String get label =>
      '$nameAr — $nameEn'
      '${inManifest ? ' · $surahCount surah(s)' : ' · not published yet'}';

  @override
  List<Object?> get props => <Object?>[
    id,
    nameAr,
    nameEn,
    riwayah,
    imagePath,
    surahCount,
    inManifest,
  ];
}

/// What the pipeline is doing.
enum AdminStage { idle, splitting, reviewing, exporting, uploading, published }

class AdminState extends Equatable {
  const AdminState({
    this.status = LoadStatus.initial,
    this.stage = AdminStage.idle,
    this.surahs = const <Surah>[],
    this.surah,
    this.ayahs = const <Ayah>[],
    this.sourcePath,
    this.plan,
    this.reciterId = '',
    this.reciters = const <AdminReciter>[],
    this.thresholdDb = defaultThresholdDb,
    this.minimumSilenceMs = defaultMinimumSilenceMs,
    this.candidateCuts = const <AudioSegment>[],
    this.suspects = const <int>[],
    this.previewingIndex,
    this.recordingHasBasmala = true,
    this.recordingHasIstiadhah = false,
    this.recordingLength,
    this.ffmpegVersion,
    this.overrideReason = '',
    this.replaceExisting = false,
    this.progress,
    this.log = const <String>[],
    this.errorMessage,
  });

  final LoadStatus status;
  final AdminStage stage;

  /// Every surah, from `quran.db`. The dropdown is this list; nothing about
  /// surahs is written down in the admin tool (CLAUDE.md A.2 rule 2).
  final List<Surah> surahs;
  final Surah? surah;

  /// The chosen surah's ayahs, shown beside their segments during review —
  /// byte-for-byte as `quran.db` holds them (A.2 rule 1).
  final List<Ayah> ayahs;

  final String? sourcePath;
  final SegmentPlan? plan;

  /// The id publishing writes under.
  final String reciterId;

  /// Everyone the manifest knows, plus anyone the app bundles. This is the
  /// dropdown: adding a surah means picking a reciter already here, never
  /// typing an id and hoping it matches.
  final List<AdminReciter> reciters;

  AdminReciter? get reciter =>
      reciters.where((AdminReciter r) => r.id == reciterId).firstOrNull;

  /// How quiet counts as silence, in dBFS, and how long a gap has to last
  /// before it is a break between ayahs.
  ///
  /// The operator's to tune, because reciters differ: a slow, breathy reading
  /// needs a longer minimum than one that runs ayahs together, and a noisy
  /// room needs a higher threshold.
  final double thresholdDb;
  final int minimumSilenceMs;

  /// Quieter, shorter silences than the ones that produced the segments.
  ///
  /// Not breaks in their own right — they are where a *missed* break most
  /// likely is, and they are what "split here" cuts at instead of halving a
  /// segment down the middle.
  final List<AudioSegment> candidateCuts;

  /// Indices of segments whose length their text cannot explain — the rows to
  /// listen to before publishing. Recomputed after every edit.
  final List<int> suspects;

  /// The segment being played back, or null when nothing is. Drives the
  /// play/stop button on its row.
  final int? previewingIndex;

  /// Whether the chosen recording recites the basmala before ayah 1. Asked of
  /// the operator because recordings differ: some start straight at ayah 1.
  final bool recordingHasBasmala;

  /// Whether the chosen recording opens with the isti'adhah.
  final bool recordingHasIstiadhah;

  /// How long the chosen recording runs, measured once when it is split.
  final Duration? recordingLength;

  static const double defaultThresholdDb = -35;

  /// 350 ms, not the 600 ms this started at: a real recording of Al-Asr has
  /// gaps of 0.40 s and 0.54 s between its ayahs, and 600 ms walked straight
  /// past both — leaving one segment holding three ayahs and a count that
  /// could only be "fixed" by cutting somewhere arbitrary.
  static const int defaultMinimumSilenceMs = 350;

  /// The first line of `ffmpeg -version`, proving the binary is there.
  final String? ffmpegVersion;

  /// What the operator has typed to justify publishing a mismatched split.
  final String overrideReason;

  /// Whether a path that already holds *different* audio may be overwritten.
  ///
  /// Off by default and deliberately awkward: replacing audio that people have
  /// downloaded gives two recordings the same name. It exists for the one case
  /// where that cannot have happened yet — a surah uploaded but never named in
  /// a published manifest, which is to say one nobody could have fetched.
  final bool replaceExisting;

  /// 0..1 while exporting or uploading.
  final double? progress;

  /// What has happened, newest last. Never holds a credential.
  final List<String> log;
  final String? errorMessage;

  bool get canSplit =>
      surah != null && sourcePath != null && reciterId.trim().isNotEmpty;

  /// The guard's verdict on the current plan, recomputed rather than stored:
  /// every edit to a segment can change it.
  PublishDecision get decision {
    final SegmentPlan? plan = this.plan;
    if (plan == null) return const PublishBlocked('Nothing has been split.');
    return const PublishGuard().decide(
      plan: plan,
      override: overrideReason.trim().isEmpty
          ? null
          : PublishOverride(reason: overrideReason, at: DateTime(0)),
    );
  }

  bool get canPublish =>
      stage == AdminStage.reviewing && decision is! PublishBlocked;

  AdminState copyWith({
    LoadStatus? status,
    AdminStage? stage,
    List<Surah>? surahs,
    Surah? surah,
    List<Ayah>? ayahs,
    String? sourcePath,
    SegmentPlan? plan,
    String? reciterId,
    List<AdminReciter>? reciters,
    double? thresholdDb,
    int? minimumSilenceMs,
    List<AudioSegment>? candidateCuts,
    List<int>? suspects,
    int? previewingIndex,
    bool clearPreview = false,
    bool? recordingHasBasmala,
    bool? recordingHasIstiadhah,
    Duration? recordingLength,
    String? ffmpegVersion,
    String? overrideReason,
    bool? replaceExisting,
    double? progress,
    bool clearProgress = false,
    // A nullable field cannot be reset through `??`, so dropping a split is
    // its own flag. Without it, choosing another recording — or another
    // surah — would keep segments computed from the last one, and they would
    // be published under the new surah's numbers.
    bool clearPlan = false,
    List<String>? log,
    String? errorMessage,
  }) => AdminState(
    status: status ?? this.status,
    stage: stage ?? this.stage,
    surahs: surahs ?? this.surahs,
    surah: surah ?? this.surah,
    ayahs: ayahs ?? this.ayahs,
    sourcePath: sourcePath ?? this.sourcePath,
    plan: clearPlan ? null : (plan ?? this.plan),
    reciterId: reciterId ?? this.reciterId,
    reciters: reciters ?? this.reciters,
    thresholdDb: thresholdDb ?? this.thresholdDb,
    minimumSilenceMs: minimumSilenceMs ?? this.minimumSilenceMs,
    candidateCuts: candidateCuts ?? this.candidateCuts,
    suspects: clearPlan ? const <int>[] : (suspects ?? this.suspects),
    previewingIndex: clearPlan || clearPreview
        ? null
        : (previewingIndex ?? this.previewingIndex),
    recordingHasBasmala: recordingHasBasmala ?? this.recordingHasBasmala,
    recordingHasIstiadhah: recordingHasIstiadhah ?? this.recordingHasIstiadhah,
    recordingLength: recordingLength ?? this.recordingLength,
    ffmpegVersion: ffmpegVersion ?? this.ffmpegVersion,
    overrideReason: overrideReason ?? this.overrideReason,
    replaceExisting: replaceExisting ?? this.replaceExisting,
    progress: clearProgress ? null : (progress ?? this.progress),
    log: log ?? this.log,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    stage,
    surahs,
    surah,
    ayahs,
    sourcePath,
    plan,
    reciterId,
    reciters,
    thresholdDb,
    minimumSilenceMs,
    candidateCuts,
    suspects,
    previewingIndex,
    recordingHasBasmala,
    recordingHasIstiadhah,
    recordingLength,
    ffmpegVersion,
    overrideReason,
    replaceExisting,
    progress,
    log,
    errorMessage,
  ];
}
