import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide State;
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/error/failures.dart';
import '../data/models/app_settings.dart';
import '../data/models/memorization_progress.dart';
import '../data/models/reading_position.dart';
import '../data/repositories/practice_repository.dart';
import '../data/repositories/progress_repository.dart';
import '../data/repositories/review_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/datasources/practice_local_data_source.dart';
import '../domain/entities/hifz_plan.dart';
import '../domain/entities/practice_stats.dart';
import '../domain/entities/review_card.dart';

/// Why a file could not be taken in.
enum BackupRefusal {
  /// Not JSON, or not a backup this app wrote.
  notABackup,

  /// Written by a newer version of the app, in a shape this one cannot read.
  newerVersion,

  /// The file could not be read from the device.
  unreadable,
}

/// What an import changed, for the screen to say.
class BackupMerge extends Equatable {
  const BackupMerge({
    this.ayahs = 0,
    this.reviews = 0,
    this.days = 0,
    this.plan = false,
    this.mark = false,
    this.skipped = 0,
  });

  /// Ayah records written — new, or moved forward.
  final int ayahs;
  final int reviews;
  final int days;

  /// Whether the backup's hifz plan was taken in (there was none here).
  final bool plan;

  /// Whether its reading mark was taken in (there was none here).
  final bool mark;

  /// Entries in the file that could not be read, and were left out.
  final int skipped;

  @override
  List<Object?> get props => <Object?>[
    ayahs,
    reviews,
    days,
    plan,
    mark,
    skipped,
  ];
}

/// A backup file on the device.
class BackupFile extends Equatable {
  const BackupFile({
    required this.path,
    required this.modified,
    this.bytes = 0,
  });

  final String path;
  final DateTime modified;

  /// The file's size; 0 where it was not read.
  final int bytes;

  String get name => p.basename(path);

  @override
  List<Object?> get props => <Object?>[path, modified, bytes];
}

/// The reader's progress as one file, out and back in.
///
/// No account and no server (CLAUDE.md A.2 rule 3): the file is written into
/// a folder the reader can reach — the Files app on iOS, the app's folder
/// over a USB cable on Android — and read back from the same folder. There is
/// no share sheet and no file picker, because neither package is approved
/// (A.4); the folder is the picker.
///
/// Import **merges**, never overwrites: per ayah the further status, the
/// larger counts and the later dates; per review card the one reviewed more
/// recently; per day the larger tally, so a file taken in twice counts
/// nothing twice. A plan or a reading mark is taken only where the device
/// has none. Nothing is written until the whole file has been read.
class BackupService {
  BackupService({
    required ProgressRepository progressRepository,
    required ReviewRepository reviewRepository,
    required PracticeRepository practiceRepository,
    required SettingsRepository settingsRepository,
    Future<Directory?> Function()? resolveDirectory,
    this.clock = DateTime.now,
  }) : _progress = progressRepository,
       _reviews = reviewRepository,
       _practice = practiceRepository,
       _settings = settingsRepository,
       _resolveDirectory = resolveDirectory ?? _defaultDirectory;

  static const String format = 'mirqat-progress';
  static const int schemaVersion = 1;
  static const String filePrefix = 'mirqat-progress-';

  final ProgressRepository _progress;
  final ReviewRepository _reviews;
  final PracticeRepository _practice;
  final SettingsRepository _settings;
  final Future<Directory?> Function() _resolveDirectory;
  final DateTime Function() clock;

  /// Where backups go. Android's app-specific external folder is the one a
  /// USB cable reaches; everywhere else, Documents — which on iOS the Files
  /// app shows, because Info.plist says so.
  static Future<Directory?> _defaultDirectory() async => Platform.isAndroid
      ? getExternalStorageDirectory()
      : getApplicationDocumentsDirectory();

  /// The folder backups are written to, for the screen to show. Null where
  /// the platform has none.
  Future<String?> folder() async => (await _resolveDirectory())?.path;

  /// Writes everything to a new file and returns its path.
  Future<Either<Failure, String>> export() async {
    try {
      final Directory? dir = await _resolveDirectory();
      if (dir == null) {
        return const Left<Failure, String>(
          StorageFailure('There is no folder to write a backup to.'),
        );
      }
      final AppSettings settings = (await _settings.read()).getOrElse(
        () => const AppSettings(),
      );
      final Map<String, dynamic> doc = <String, dynamic>{
        'format': format,
        'schemaVersion': schemaVersion,
        'exportedAt': clock().toIso8601String(),
        'progress': <Map<String, dynamic>>[
          for (final MemorizationProgress r
              in (await _progress.all()).getOrElse(
                () => const <MemorizationProgress>[],
              ))
            r.toMap(),
        ],
        'reviews': <Map<String, dynamic>>[
          for (final ReviewCard c in (await _reviews.all()).getOrElse(
            () => const <ReviewCard>[],
          ))
            c.toMap(),
        ],
        'practice': <String, dynamic>{
          for (final MapEntry<DateTime, PracticeDay> e
              in (await _practice.all())
                  .getOrElse(() => const <DateTime, PracticeDay>{})
                  .entries)
            PracticeLocalDataSourceImpl.keyFor(e.key): e.value.toMap(),
        },
        'hifzPlan': settings.hifzPlan?.toMap(),
        'readingMark': settings.readingMark?.toMap(),
      };
      await dir.create(recursive: true);
      final File file = File(
        p.join(dir.path, '$filePrefix${_stamp(clock())}.json'),
      );
      await file.writeAsString(
        const JsonEncoder.withIndent(' ').convert(doc),
        flush: true,
      );
      return Right<Failure, String>(file.path);
    } on FileSystemException catch (e) {
      return Left<Failure, String>(StorageFailure('Could not write: $e'));
    }
  }

  /// `2026-10-21-0915`: sorts by time, and two backups a minute apart do not
  /// overwrite each other.
  static String _stamp(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}-'
      '${t.hour.toString().padLeft(2, '0')}'
      '${t.minute.toString().padLeft(2, '0')}';

  /// Every backup in the folder, newest first.
  Future<List<BackupFile>> list() async {
    final Directory? dir = await _resolveDirectory();
    if (dir == null || !dir.existsSync()) return const <BackupFile>[];
    final List<BackupFile> files = <BackupFile>[
      for (final FileSystemEntity f in dir.listSync())
        if (f is File &&
            p.basename(f.path).startsWith(filePrefix) &&
            f.path.endsWith('.json'))
          BackupFile(
            path: f.path,
            modified: f.lastModifiedSync(),
            bytes: f.lengthSync(),
          ),
    ]..sort((BackupFile a, BackupFile b) => b.name.compareTo(a.name));
    return files;
  }

  /// Reads [path] whole, and only then merges it in.
  Future<Either<BackupRefusal, BackupMerge>> import(String path) async {
    final String contents;
    try {
      contents = await File(path).readAsString();
    } on FileSystemException {
      return const Left<BackupRefusal, BackupMerge>(BackupRefusal.unreadable);
    }
    return importContents(contents);
  }

  /// A backup's contents, from wherever they came — the app's folder, or a
  /// file the reader picked — checked whole, and only then merged in.
  Future<Either<BackupRefusal, BackupMerge>> importContents(
    String contents,
  ) async {
    final Object? doc;
    try {
      doc = jsonDecode(contents);
    } on FormatException {
      return const Left<BackupRefusal, BackupMerge>(BackupRefusal.notABackup);
    }
    if (doc is! Map ||
        doc['format'] != format ||
        doc['schemaVersion'] is! int) {
      return const Left<BackupRefusal, BackupMerge>(BackupRefusal.notABackup);
    }
    if ((doc['schemaVersion'] as int) > schemaVersion) {
      return const Left<BackupRefusal, BackupMerge>(BackupRefusal.newerVersion);
    }

    // Read everything first.
    int skipped = 0;
    final List<MemorizationProgress> progress = <MemorizationProgress>[];
    for (final Object? raw in _list(doc['progress'])) {
      try {
        if (raw is! Map) throw const FormatException();
        progress.add(MemorizationProgress.fromMap(raw));
      } catch (_) {
        skipped++;
      }
    }
    final List<ReviewCard> cards = <ReviewCard>[];
    for (final Object? raw in _list(doc['reviews'])) {
      final ReviewCard? c = ReviewCard.fromMap(raw);
      c == null ? skipped++ : cards.add(c);
    }
    final Map<DateTime, PracticeDay> days = <DateTime, PracticeDay>{};
    final Object? practice = doc['practice'];
    if (practice is Map) {
      for (final MapEntry<dynamic, dynamic> e in practice.entries) {
        final DateTime? day = PracticeLocalDataSourceImpl.dayOf(e.key);
        final PracticeDay? d = PracticeDay.fromMap(e.value);
        if (day == null || d == null) {
          skipped++;
        } else {
          days[day] = d;
        }
      }
    }
    final HifzPlan? plan = HifzPlan.fromMap(doc['hifzPlan']);
    final Object? rawMark = doc['readingMark'];
    ReadingPosition? mark;
    if (rawMark is Map) {
      try {
        mark = ReadingPosition.fromMap(rawMark);
      } catch (_) {
        skipped++;
      }
    }

    // Then merge.
    final Map<String, MemorizationProgress> mine =
        <String, MemorizationProgress>{
          for (final MemorizationProgress r
              in (await _progress.all()).getOrElse(
                () => const <MemorizationProgress>[],
              ))
            r.storageKey: r,
        };
    int ayahs = 0;
    for (final MemorizationProgress theirs in progress) {
      final MemorizationProgress? here = mine[theirs.storageKey];
      final MemorizationProgress merged = here == null
          ? theirs
          : mergeProgress(here, theirs);
      if (merged != here) {
        await _progress.save(merged);
        ayahs++;
      }
    }

    final Map<String, ReviewCard> myCards = <String, ReviewCard>{
      for (final ReviewCard c in (await _reviews.all()).getOrElse(
        () => const <ReviewCard>[],
      ))
        c.id: c,
    };
    int reviews = 0;
    for (final ReviewCard theirs in cards) {
      final ReviewCard? here = myCards[theirs.id];
      if (here == null || _later(theirs.lastReviewed, here.lastReviewed)) {
        await _reviews.save(theirs);
        reviews++;
      }
    }

    final Map<DateTime, PracticeDay> myDays = (await _practice.all()).getOrElse(
      () => const <DateTime, PracticeDay>{},
    );
    int dayCount = 0;
    for (final MapEntry<DateTime, PracticeDay> e in days.entries) {
      final PracticeDay here = myDays[e.key] ?? const PracticeDay();
      final PracticeDay merged = PracticeDay(
        plays: here.plays > e.value.plays ? here.plays : e.value.plays,
        seconds: here.seconds > e.value.seconds
            ? here.seconds
            : e.value.seconds,
      );
      if (merged != here) {
        await _practice.set(e.key, merged);
        dayCount++;
      }
    }

    final AppSettings settings = (await _settings.read()).getOrElse(
      () => const AppSettings(),
    );
    final bool takePlan = settings.hifzPlan == null && plan != null;
    final bool takeMark = settings.readingMark == null && mark != null;
    if (takePlan || takeMark) {
      await _settings.save(
        settings.copyWith(
          hifzPlan: takePlan ? plan : null,
          readingMark: takeMark ? mark : null,
        ),
      );
    }

    return Right<BackupRefusal, BackupMerge>(
      BackupMerge(
        ayahs: ayahs,
        reviews: reviews,
        days: dayCount,
        plan: takePlan,
        mark: takeMark,
        skipped: skipped,
      ),
    );
  }

  static List<Object?> _list(Object? raw) =>
      raw is List ? raw : const <Object?>[];

  static bool _later(DateTime? a, DateTime? b) =>
      a != null && (b == null || a.isAfter(b));

  /// One ayah's record from two devices: the further status, the larger
  /// counts, the later dates. Merging never takes progress away.
  static MemorizationProgress mergeProgress(
    MemorizationProgress a,
    MemorizationProgress b,
  ) {
    DateTime? later(DateTime? x, DateTime? y) => _later(x, y) ? x : y;
    final int stumbles = a.stumbles > b.stumbles ? a.stumbles : b.stumbles;
    return MemorizationProgress(
      surahNumber: a.surahNumber,
      ayahNumber: a.ayahNumber,
      status: a.status.index >= b.status.index ? a.status : b.status,
      lastSessionAt: later(a.lastSessionAt, b.lastSessionAt),
      cumulativeRepeats: a.cumulativeRepeats > b.cumulativeRepeats
          ? a.cumulativeRepeats
          : b.cumulativeRepeats,
      stumbles: stumbles,
      lastStumbleAt: stumbles == 0
          ? null
          : later(a.lastStumbleAt, b.lastStumbleAt),
    );
  }
}
