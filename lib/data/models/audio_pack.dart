import 'package:equatable/equatable.dart';

import '../../core/error/exceptions.dart';

/// What a recorded download is.
///
/// `failed` earns its row: a surah that could not be fetched is worth
/// remembering, because "retry the ones that failed" is a thing the user can
/// then ask for without hunting through 114 surahs to find them.
enum PackState {
  complete('complete'),
  stale('stale'),
  failed('failed');

  const PackState(this.storageValue);

  final String storageValue;

  static PackState fromStorage(Object? value) {
    for (final PackState state in PackState.values) {
      if (state.storageValue == value) return state;
    }
    return PackState.complete;
  }
}

/// One recorded audio pack: a reciter's surah, at the bitrate and version the
/// manifest offered when it was fetched.
///
/// [version] and [bitrate] are kept because they are what makes an install
/// stale: a reciter who re-cuts a recording bumps their manifest `version`,
/// and the pack on disk is then the old reading.
class InstalledPack extends Equatable {
  const InstalledPack({
    required this.reciterId,
    required this.surahNumber,
    required this.bitrate,
    required this.version,
    required this.ayahs,
    required this.bytes,
    required this.installedAt,
    this.state = PackState.complete,
  });

  final String reciterId;
  final int surahNumber;
  final int bitrate;
  final String version;

  /// Ayah count the pack was cut to, as the manifest declared it.
  final int ayahs;

  /// Size of the pack that was fetched, for a "free up space" figure.
  final int bytes;
  final DateTime installedAt;

  /// Whether this surah is playable offline, out of date, or a failure kept
  /// so it can be retried.
  final PackState state;

  /// Playable from disk right now.
  bool get isComplete => state == PackState.complete;

  /// Downloaded, but from a version of the recording the manifest has since
  /// replaced.
  bool get isStale => state == PackState.stale;

  InstalledPack copyWith({PackState? state, String? version}) => InstalledPack(
    reciterId: reciterId,
    surahNumber: surahNumber,
    bitrate: bitrate,
    version: version ?? this.version,
    ayahs: ayahs,
    bytes: bytes,
    installedAt: installedAt,
    state: state ?? this.state,
  );

  /// The storage key: one pack per reciter and surah.
  static String keyFor(String reciterId, int surahNumber) =>
      '$reciterId:${surahNumber.toString().padLeft(3, '0')}';

  String get key => keyFor(reciterId, surahNumber);

  /// A `downloads` row.
  Map<String, Object?> toRow() => <String, Object?>{
    'reciter_id': reciterId,
    'surah': surahNumber,
    'bitrate': bitrate,
    'version': version,
    'state': state.storageValue,
    'bytes': bytes,
    'ayahs': ayahs,
    'updated_at': installedAt.toIso8601String(),
  };

  factory InstalledPack.fromRow(Map<String, Object?> row) {
    Never bad(String why) => throw StorageException('Downloads row: $why.');

    final Object? reciterId = row['reciter_id'];
    final Object? surah = row['surah'];
    if (reciterId is! String || reciterId.isEmpty) bad('no reciter_id');
    if (surah is! int) bad('no surah number');

    return InstalledPack(
      reciterId: reciterId,
      surahNumber: surah,
      bitrate: row['bitrate'] as int? ?? 0,
      version: '${row['version'] ?? ''}',
      ayahs: row['ayahs'] as int? ?? 0,
      bytes: row['bytes'] as int? ?? 0,
      installedAt:
          DateTime.tryParse('${row['updated_at']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      state: PackState.fromStorage(row['state']),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    reciterId,
    surahNumber,
    bitrate,
    version,
    ayahs,
    bytes,
    installedAt,
    state,
  ];
}

/// Where one pack download has got to.
///
/// [verifying] and [installing] are separate states on purpose: they are the
/// slow, silent part of a download — hashing 40 MB and unzipping it — and a
/// progress bar that sat at 100% through both would look stuck.
enum PackStatus {
  /// Nothing has been asked for; the surah is bundled, installed or streamed.
  idle,
  queued,
  downloading,
  verifying,
  installing,
  installed,
  failed,
  cancelled,
}

/// A download's live state, as the UI sees it.
class PackDownload extends Equatable {
  const PackDownload({
    required this.reciterId,
    required this.surahNumber,
    required this.status,
    this.progress = 0,
    this.message,
  });

  const PackDownload.idle({required this.reciterId, required this.surahNumber})
    : status = PackStatus.idle,
      progress = 0,
      message = null;

  final String reciterId;
  final int surahNumber;
  final PackStatus status;

  /// 0..1 while [PackStatus.downloading]; meaningless otherwise.
  final double progress;

  /// Developer-facing detail for a failure. User-facing copy comes from the
  /// translation files, keyed off the status (CLAUDE.md A.3, Errors).
  final String? message;

  bool get isBusy => switch (status) {
    PackStatus.queued ||
    PackStatus.downloading ||
    PackStatus.verifying ||
    PackStatus.installing => true,
    PackStatus.idle ||
    PackStatus.installed ||
    PackStatus.failed ||
    PackStatus.cancelled => false,
  };

  PackDownload copyWith({
    PackStatus? status,
    double? progress,
    String? message,
  }) => PackDownload(
    reciterId: reciterId,
    surahNumber: surahNumber,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    message: message ?? this.message,
  );

  @override
  List<Object?> get props => <Object?>[
    reciterId,
    surahNumber,
    status,
    progress,
    message,
  ];
}

/// Where a whole-mushaf download has got to.
///
/// Its own state rather than a count derived from the `downloads` table: a run
/// is a thing with a beginning — the surahs it set out to fetch — and that
/// number cannot be recovered afterwards from what landed. [failed] is kept so
/// the screen can say which surahs did not arrive without the user re-reading
/// 114 rows to find them.
enum BulkStatus {
  /// Nothing has been asked for.
  idle,
  running,

  /// Every surah in the run was attempted.
  finished,

  /// Stopped by the user, or abandoned after too many failures in a row.
  cancelled,
}

/// One reciter's whole-mushaf download, as the UI sees it.
class BulkDownload extends Equatable {
  const BulkDownload({
    required this.reciterId,
    required this.status,
    this.total = 0,
    this.done = 0,
    this.failed = const <int>[],
    this.currentSurah,
    this.message,
  });

  const BulkDownload.idle(this.reciterId)
    : status = BulkStatus.idle,
      total = 0,
      done = 0,
      failed = const <int>[],
      currentSurah = null,
      message = null;

  final String reciterId;
  final BulkStatus status;

  /// How many surahs the run set out to fetch.
  final int total;

  /// How many of them arrived.
  final int done;

  /// The surahs that did not, in the order they were attempted.
  final List<int> failed;

  /// The surah being fetched right now, or the last one attempted.
  final int? currentSurah;

  /// Developer-facing detail for the last failure. User-facing copy comes
  /// from the translation files (CLAUDE.md A.3, Errors).
  final String? message;

  bool get isRunning => status == BulkStatus.running;

  /// How far through the run, counting a failure as attempted: the bar
  /// measures the queue, not the successes, or it would stall on a surah the
  /// CDN does not have.
  double get progress =>
      total == 0 ? 0 : ((done + failed.length) / total).clamp(0, 1);

  BulkDownload copyWith({
    BulkStatus? status,
    int? total,
    int? done,
    List<int>? failed,
    int? currentSurah,
    String? message,
  }) => BulkDownload(
    reciterId: reciterId,
    status: status ?? this.status,
    total: total ?? this.total,
    done: done ?? this.done,
    failed: failed ?? this.failed,
    currentSurah: currentSurah ?? this.currentSurah,
    message: message ?? this.message,
  );

  @override
  List<Object?> get props => <Object?>[
    reciterId,
    status,
    total,
    done,
    failed,
    currentSurah,
    message,
  ];
}

/// What a whole-mushaf download for one reciter would still cost.
///
/// [bytes] is 0 where the manifest does not say — a reciter published without
/// packs has no size to add up — and the screen then offers the download
/// without a figure rather than inventing one.
class PendingDownloads extends Equatable {
  const PendingDownloads({
    required this.reciterId,
    required this.surahs,
    required this.bytes,
    required this.offered,
    required this.onDevice,
  });

  const PendingDownloads.none(this.reciterId)
    : surahs = const <int>[],
      bytes = 0,
      offered = 0,
      onDevice = 0;

  final String reciterId;

  /// The surahs left to fetch, ascending: everything the reciter offers that
  /// is not already playable offline.
  final List<int> surahs;

  /// What fetching them costs, in bytes, as the manifest declares it.
  final int bytes;

  /// How many surahs this reciter has at all.
  final int offered;

  /// How many of them already play from the device — downloaded, or bundled.
  final int onDevice;

  /// Nothing left to fetch, and something there to begin with.
  bool get isComplete => offered > 0 && surahs.isEmpty;

  @override
  List<Object?> get props => <Object?>[
    reciterId,
    surahs,
    bytes,
    offered,
    onDevice,
  ];
}
