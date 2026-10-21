import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/datasources/practice_local_data_source.dart';
import 'package:mirqat/data/datasources/progress_local_data_source.dart';
import 'package:mirqat/data/datasources/review_local_data_source.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/models/reading_position.dart';
import 'package:mirqat/data/repositories/practice_repository.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/data/repositories/review_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/engine/review_scheduler.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/hifz_plan.dart';
import 'package:mirqat/domain/entities/practice_stats.dart';
import 'package:mirqat/domain/entities/review_card.dart';
import 'package:mirqat/services/backup_service.dart';

class _Settings implements SettingsRepository {
  AppSettings current = const AppSettings();

  @override
  Future<Either<Failure, AppSettings>> read() async =>
      Right<Failure, AppSettings>(current);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings s) async {
    current = s;
    return Right<Failure, AppSettings>(s);
  }

  @override
  Stream<AppSettings> get changes => const Stream<AppSettings>.empty();
}

/// One device: its own Hive folder, its own settings.
class _Device {
  late ProgressRepository progress;
  late ReviewRepository reviews;
  late PracticeRepository practice;
  final _Settings settings = _Settings();

  Future<void> open() async {
    final ProgressLocalDataSourceImpl p = ProgressLocalDataSourceImpl();
    await p.open();
    final ReviewLocalDataSourceImpl r = ReviewLocalDataSourceImpl();
    await r.open();
    final PracticeLocalDataSourceImpl d = PracticeLocalDataSourceImpl();
    await d.open();
    progress = ProgressRepositoryImpl(p);
    reviews = ReviewRepositoryImpl(r);
    practice = PracticeRepositoryImpl(d);
  }

  BackupService backup(Directory folder) => BackupService(
    progressRepository: progress,
    reviewRepository: reviews,
    practiceRepository: practice,
    settingsRepository: settings,
    resolveDirectory: () async => folder,
    clock: () => DateTime(2026, 10, 21, 9, 15),
  );
}

void main() {
  late Directory hive;
  late Directory folder;
  const ReviewScheduler scheduler = ReviewScheduler();

  setUp(() {
    hive = Directory.systemTemp.createTempSync('mirqat_backup_hive');
    folder = Directory.systemTemp.createTempSync('mirqat_backup_files');
    Hive.init(hive.path);
  });

  tearDown(() async {
    await Hive.close();
    for (final Directory d in <Directory>[hive, folder]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  /// A fresh device: the Hive boxes of the last one closed and emptied.
  Future<_Device> freshDevice() async {
    await Hive.close();
    hive.deleteSync(recursive: true);
    hive.createSync();
    Hive.init(hive.path);
    final _Device d = _Device();
    await d.open();
    return d;
  }

  final HifzPlan plan = HifzPlan(
    from: const AyahRef(67, 1),
    to: const AyahRef(67, 4),
    days: 2,
    started: DateTime(2026, 10, 20),
    portions: const <Portion>[
      Portion(AyahRef(67, 1), AyahRef(67, 2)),
      Portion(AyahRef(67, 3), AyahRef(67, 4)),
    ],
    completed: 1,
  );
  final ReadingPosition mark = ReadingPosition(
    surahNumber: 67,
    ayahNumber: 3,
    page: 562,
    at: DateTime(2026, 10, 20, 22),
  );

  Future<_Device> populated() async {
    final _Device d = _Device();
    await d.open();
    await d.progress.setStatus(67, 1, MemorizationStatus.memorized);
    await d.progress.recordRepeats(67, 1, 12, at: DateTime(2026, 10, 20));
    await d.progress.markStumble(67, 2, at: DateTime(2026, 10, 19));
    await d.reviews.save(
      scheduler.start(
        from: const AyahRef(67, 1),
        to: const AyahRef(67, 4),
        grade: Grade.solid,
        now: DateTime(2026, 10, 20),
      ),
    );
    await d.practice.set(
      DateTime(2026, 10, 20),
      const PracticeDay(plays: 30, seconds: 600),
    );
    d.settings.current = AppSettings(
      hifzPlan: plan,
      readingMark: mark,
      reciterId: 'mine',
    );
    return d;
  }

  test('a new device takes everything in, as it was', () async {
    final _Device old = await populated();
    final String path = (await old.backup(folder).export()).getOrElse(
      () => fail('export failed'),
    );
    expect(path, endsWith('mirqat-progress-2026-10-21-0915.json'));
    final List<MemorizationProgress> before = (await old.progress.all())
        .getOrElse(() => fail(''));

    final _Device fresh = await freshDevice();
    final BackupMerge merge = (await fresh.backup(folder).import(path))
        .getOrElse(() => fail('import refused'));

    expect((await fresh.progress.all()).getOrElse(() => fail('')), before);
    expect((await fresh.reviews.all()).getOrElse(() => fail('')), hasLength(1));
    expect(
      (await fresh.practice.all()).getOrElse(() => fail('')),
      <DateTime, PracticeDay>{
        DateTime(2026, 10, 20): const PracticeDay(plays: 30, seconds: 600),
      },
    );
    expect(fresh.settings.current.hifzPlan, plan);
    expect(fresh.settings.current.readingMark, mark);
    expect(merge.plan, isTrue);
    expect(merge.mark, isTrue);
    expect(merge.skipped, 0);
  });

  test('taken in twice, nothing counts twice', () async {
    final _Device d = await populated();
    final String path = (await d.backup(folder).export()).getOrElse(
      () => fail(''),
    );
    final BackupMerge again = (await d.backup(folder).import(path)).getOrElse(
      () => fail(''),
    );
    expect(again, const BackupMerge());
    expect(
      (await d.practice.all()).getOrElse(() => fail('')).values.single.plays,
      30,
    );
  });

  test('merging never takes progress away', () {
    final MemorizationProgress here = MemorizationProgress(
      surahNumber: 1,
      ayahNumber: 1,
      status: MemorizationStatus.memorized,
      cumulativeRepeats: 5,
      lastSessionAt: DateTime(2026, 10, 1),
    );
    final MemorizationProgress there = MemorizationProgress(
      surahNumber: 1,
      ayahNumber: 1,
      status: MemorizationStatus.inProgress,
      cumulativeRepeats: 9,
      lastSessionAt: DateTime(2026, 10, 5),
      stumbles: 2,
      lastStumbleAt: DateTime(2026, 10, 4),
    );
    final MemorizationProgress m = BackupService.mergeProgress(here, there);
    expect(m.status, MemorizationStatus.memorized);
    expect(m.cumulativeRepeats, 9);
    expect(m.lastSessionAt, DateTime(2026, 10, 5));
    expect(m.stumbles, 2);
    expect(BackupService.mergeProgress(there, here), m);
  });

  test(
    'the device\'s own plan, mark and review stand against an older copy',
    () async {
      final _Device d = await populated();
      final String path = (await d.backup(folder).export()).getOrElse(
        () => fail(''),
      );
      final HifzPlan newer = plan.copyWith(completed: 2);
      d.settings.current = d.settings.current.copyWith(hifzPlan: newer);
      final ReviewCard reviewed = scheduler.grade(
        (await d.reviews.all()).getOrElse(() => fail('')).single,
        Grade.forgot,
        DateTime(2026, 10, 25),
      );
      await d.reviews.save(reviewed);

      await d.backup(folder).import(path);
      expect(d.settings.current.hifzPlan, newer);
      expect(
        (await d.reviews.all()).getOrElse(() => fail('')).single,
        reviewed,
      );
      expect(d.settings.current.reciterId, 'mine');
    },
  );

  group('refused, and nothing changed', () {
    Future<void> expectRefused(String contents, BackupRefusal why) async {
      final _Device d = await populated();
      final File f = File('${folder.path}/mirqat-progress-x.json')
        ..writeAsStringSync(contents);
      final List<MemorizationProgress> before = (await d.progress.all())
          .getOrElse(() => fail(''));
      final Either<BackupRefusal, BackupMerge> r = await d
          .backup(folder)
          .import(f.path);
      expect(r, Left<BackupRefusal, BackupMerge>(why));
      expect((await d.progress.all()).getOrElse(() => fail('')), before);
    }

    test('not JSON', () => expectRefused('<html>', BackupRefusal.notABackup));
    test(
      'JSON, but not ours',
      () => expectRefused('{"a": 1}', BackupRefusal.notABackup),
    );
    test(
      'from a newer version',
      () => expectRefused(
        jsonEncode(<String, Object?>{
          'format': BackupService.format,
          'schemaVersion': BackupService.schemaVersion + 1,
          'progress': <Object?>[],
        }),
        BackupRefusal.newerVersion,
      ),
    );
    test('a file that is not there', () async {
      final _Device d = await populated();
      expect(
        await d.backup(folder).import('${folder.path}/missing.json'),
        const Left<BackupRefusal, BackupMerge>(BackupRefusal.unreadable),
      );
    });
  });

  test('a bad entry in a good file is left out and counted', () async {
    final _Device d = await populated();
    final File f = File('${folder.path}/mirqat-progress-y.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'format': BackupService.format,
          'schemaVersion': 1,
          'progress': <Object?>[
            'nonsense',
            <String, Object?>{'surahNumber': 'one'},
          ],
          'reviews': <Object?>[<String, Object?>{}],
          'practice': <String, Object?>{'someday': <String, Object?>{}},
        }),
      );
    final BackupMerge m = (await d.backup(folder).import(f.path)).getOrElse(
      () => fail('refused'),
    );
    expect(m.skipped, 4);
    expect(m.ayahs, 0);
  });

  test(
    'lists the copies in the folder, newest first, and nothing else',
    () async {
      final _Device d = await populated();
      File(
        '${folder.path}/mirqat-progress-2026-01-01-0800.json',
      ).writeAsStringSync('{}');
      File(
        '${folder.path}/mirqat-progress-2026-05-01-0800.json',
      ).writeAsStringSync('{}');
      File('${folder.path}/notes.txt').writeAsStringSync('x');
      expect(
        (await d.backup(folder).list()).map((BackupFile f) => f.name),
        <String>[
          'mirqat-progress-2026-05-01-0800.json',
          'mirqat-progress-2026-01-01-0800.json',
        ],
      );
    },
  );
}
