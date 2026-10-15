import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;

import 'segment_planner.dart';

/// Where one recording of a batch stands.
enum BatchStatus {
  /// Not reached yet.
  pending,

  /// Being split right now.
  splitting,

  /// Split to the expected count and every clip fits its text.
  clean,

  /// Split to the expected count, but some clips' lengths their text cannot
  /// explain — worth an ear before publishing.
  suspect,

  /// The split did not reach the expected count.
  mismatch,

  /// The file could not be processed at all, or could not be matched to a
  /// surah.
  failed,

  /// Uploaded, pack and manifest included.
  published,
}

/// One recording of a batch: the file, the surah its name claims, and what
/// came of splitting it.
class BatchEntry extends Equatable {
  const BatchEntry({
    required this.path,
    required this.surahNumber,
    this.status = BatchStatus.pending,
    this.detail = '',
    this.plan,
    this.candidates = const <AudioSegment>[],
    this.suspects = const <int>[],
    this.total,
  });

  final String path;

  /// Zero when the file's name does not say which surah it is.
  final int surahNumber;

  final BatchStatus status;

  /// What went wrong, or what is worth knowing — the words the README gets.
  final String detail;

  /// The split, kept so the entry can be opened in the review list and fixed
  /// by ear without splitting again.
  final SegmentPlan? plan;
  final List<AudioSegment> candidates;
  final List<int> suspects;
  final Duration? total;

  String get fileName => p.basename(path);

  bool get isClean => status == BatchStatus.clean;

  /// Whether the operator still has something to do with this entry.
  bool get needsAttention =>
      status == BatchStatus.suspect ||
      status == BatchStatus.mismatch ||
      status == BatchStatus.failed;

  BatchEntry copyWith({
    BatchStatus? status,
    String? detail,
    SegmentPlan? plan,
    List<AudioSegment>? candidates,
    List<int>? suspects,
    Duration? total,
  }) => BatchEntry(
    path: path,
    surahNumber: surahNumber,
    status: status ?? this.status,
    detail: detail ?? this.detail,
    plan: plan ?? this.plan,
    candidates: candidates ?? this.candidates,
    suspects: suspects ?? this.suspects,
    total: total ?? this.total,
  );

  @override
  List<Object?> get props => <Object?>[
    path,
    surahNumber,
    status,
    detail,
    plan,
    candidates,
    suspects,
    total,
  ];
}

/// What the file panel's audio list says a recording can be.
const Set<String> _audioExtensions = <String>{
  '.mp3', '.m4a', '.aac', '.wav', '.aiff', '.aif', '.flac', '.ogg', //
  '.opus', '.wma',
};

/// The audio files of [folder], each matched to the surah its name claims.
///
/// A recording is named by its surah — `001.mp3`, `014 Ibrahim.wav` — so the
/// leading digits are the claim. A file with none, or with a number no surah
/// has, comes back with [BatchEntry.surahNumber] zero and a failed status: it
/// is reported rather than skipped, because a folder of 114 that quietly
/// processes 113 is how a surah goes missing. Two files claiming the same
/// surah both fail, for the same reason — the tool must never guess which
/// take was meant.
List<BatchEntry> recordingsIn(Directory folder) {
  final List<FileSystemEntity> listed = folder.listSync()
    ..sort(
      (FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path),
    );

  final List<BatchEntry> entries = <BatchEntry>[];
  for (final FileSystemEntity entity in listed) {
    if (entity is! File) continue;
    final String name = p.basename(entity.path);
    if (name.startsWith('.')) continue;
    if (!_audioExtensions.contains(p.extension(name).toLowerCase())) continue;

    final Match? digits = RegExp(r'^(\d{1,3})').firstMatch(name);
    final int surah = digits == null ? 0 : int.parse(digits.group(1)!);
    entries.add(
      surah >= 1 && surah <= 114
          ? BatchEntry(path: entity.path, surahNumber: surah)
          : BatchEntry(
              path: entity.path,
              surahNumber: 0,
              status: BatchStatus.failed,
              detail:
                  'The file name does not begin with a surah number '
                  '(001–114), so the tool cannot say which surah this is.',
            ),
    );
  }

  // Two files claiming one surah: neither can be trusted to be the meant
  // take, so both are failed rather than one chosen.
  final Map<int, int> claims = <int, int>{};
  for (final BatchEntry entry in entries) {
    if (entry.surahNumber > 0) {
      claims[entry.surahNumber] = (claims[entry.surahNumber] ?? 0) + 1;
    }
  }
  return List<BatchEntry>.unmodifiable(<BatchEntry>[
    for (final BatchEntry entry in entries)
      if ((claims[entry.surahNumber] ?? 0) > 1)
        entry.copyWith(
          status: BatchStatus.failed,
          detail:
              'More than one file names surah ${entry.surahNumber} — remove '
              'the take that is not meant and run the batch again.',
        )
      else
        entry,
  ]);
}

/// The report written beside the recordings, as `README.md`.
///
/// Everything that is *not* clean is spelled out — which file, which surah,
/// and what exactly is wrong — because this file is what the operator works
/// from after the batch: it is the to-do list. The clean ones are a count,
/// not a listing; a hundred lines of "fine" would bury the five that matter.
String batchReadme({
  required String reciterId,
  required List<BatchEntry> entries,
  required DateTime at,
}) {
  final List<BatchEntry> attention = <BatchEntry>[
    for (final BatchEntry e in entries)
      if (e.needsAttention) e,
  ];
  final int clean = entries.where((BatchEntry e) => e.isClean).length;
  final int published = entries
      .where((BatchEntry e) => e.status == BatchStatus.published)
      .length;
  final int pending = entries
      .where(
        (BatchEntry e) =>
            e.status == BatchStatus.pending ||
            e.status == BatchStatus.splitting,
      )
      .length;

  final StringBuffer out = StringBuffer()
    ..writeln('# Batch split — $reciterId')
    ..writeln()
    ..writeln(
      'Written by the Mirqat admin tool on '
      '${at.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}. '
      'Re-running the batch rewrites this file.',
    )
    ..writeln()
    ..writeln(
      '**${entries.length} recordings** — '
      '$clean clean'
      '${published > 0 ? ', $published published' : ''}'
      '${pending > 0 ? ', $pending not reached (the batch was stopped)' : ''}'
      ', ${attention.length} needing attention.',
    );

  if (attention.isEmpty) {
    out
      ..writeln()
      ..writeln(
        'Nothing needs attention: every recording split to the '
        'expected count and every clip fits its text.',
      );
  } else {
    out
      ..writeln()
      ..writeln('## Needs attention')
      ..writeln();
    for (final BatchEntry entry in attention) {
      final String what = switch (entry.status) {
        BatchStatus.suspect => 'clips that do not fit their text',
        BatchStatus.mismatch => 'wrong segment count',
        _ => 'failed',
      };
      out
        ..writeln(
          '- **${entry.fileName}**'
          '${entry.surahNumber > 0 ? ' (surah ${entry.surahNumber})' : ''}'
          ' — $what',
        )
        ..writeln('  ${entry.detail}');
    }
  }

  return out.toString();
}
