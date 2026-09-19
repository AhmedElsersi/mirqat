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
