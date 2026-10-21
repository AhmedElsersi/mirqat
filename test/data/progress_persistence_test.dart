import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/datasources/progress_local_data_source.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';

void main() {
  late Directory storageDir;

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('mirqat_progress_test');
    Hive.init(storageDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (storageDir.existsSync()) storageDir.deleteSync(recursive: true);
  });

  Future<ProgressLocalDataSource> openSource() async {
    final ProgressLocalDataSourceImpl source = ProgressLocalDataSourceImpl();
    await source.open();
    return source;
  }

  test('an untouched ayah reads back as notStarted, not as absent', () async {
    final ProgressLocalDataSource source = await openSource();

    final MemorizationProgress progress = await source.get(1, 4);

    expect(progress.status, MemorizationStatus.notStarted);
    expect(progress.cumulativeRepeats, 0);
    expect(progress.lastSessionAt, isNull);
  });

  test('getForSurah returns one record per ayah', () async {
    final ProgressLocalDataSource source = await openSource();
    await source.setStatus(1, 2, MemorizationStatus.memorized);

    final List<MemorizationProgress> all = await source.getForSurah(1, 7);

    expect(all, hasLength(7));
    expect(all.map((MemorizationProgress p) => p.ayahNumber), <int>[
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
    expect(all[1].status, MemorizationStatus.memorized);
    expect(all[0].status, MemorizationStatus.notStarted);
  });

  test('progress survives an app restart', () async {
    final DateTime at = DateTime.utc(2026, 9, 7, 9, 15);

    final ProgressLocalDataSource first = await openSource();
    await first.recordRepeats(1, 3, 12, at: at);
    await first.setStatus(1, 5, MemorizationStatus.memorized);

    // Tear the whole Hive instance down and bring it back up against the same
    // directory — the closest stand-in for the process being killed.
    await Hive.close();
    Hive.init(storageDir.path);

    final ProgressLocalDataSource second = await openSource();

    final MemorizationProgress ayah3 = await second.get(1, 3);
    expect(ayah3.status, MemorizationStatus.inProgress);
    expect(ayah3.cumulativeRepeats, 12);
    expect(ayah3.lastSessionAt, at);

    expect((await second.get(1, 5)).status, MemorizationStatus.memorized);
    expect((await second.get(1, 6)).status, MemorizationStatus.notStarted);
  });

  test('recordRepeats accumulates across sessions', () async {
    final ProgressLocalDataSource source = await openSource();

    await source.recordRepeats(1, 1, 3);
    await source.recordRepeats(1, 1, 3);
    await source.recordRepeats(1, 1, 6);

    expect((await source.get(1, 1)).cumulativeRepeats, 12);
  });

  test('recordRepeats moves notStarted to inProgress but never demotes a '
      'memorized ayah', () async {
    final ProgressLocalDataSource source = await openSource();

    await source.recordRepeats(1, 1, 3);
    expect((await source.get(1, 1)).status, MemorizationStatus.inProgress);

    await source.setStatus(1, 1, MemorizationStatus.memorized);
    await source.recordRepeats(1, 1, 3);
    expect((await source.get(1, 1)).status, MemorizationStatus.memorized);
    expect((await source.get(1, 1)).cumulativeRepeats, 6);
  });

  test('clearSurah removes only that surah', () async {
    final ProgressLocalDataSource source = await openSource();
    await source.setStatus(1, 1, MemorizationStatus.memorized);
    await source.setStatus(2, 1, MemorizationStatus.memorized);

    await source.clearSurah(1, 7);

    expect((await source.get(1, 1)).status, MemorizationStatus.notStarted);
    expect((await source.get(2, 1)).status, MemorizationStatus.memorized);
  });

  test('using the store before open() fails loudly', () async {
    final ProgressLocalDataSource source = ProgressLocalDataSourceImpl();

    await expectLater(source.get(1, 1), throwsA(isA<Exception>()));
  });

  group('repository', () {
    test('wraps reads and writes in Either', () async {
      final ProgressRepository repository = ProgressRepositoryImpl(
        await openSource(),
      );

      expect((await repository.recordRepeats(1, 2, 5)).isRight(), isTrue);

      final Either<Failure, MemorizationProgress> read = await repository
          .getAyah(1, 2);
      expect(
        read
            .getOrElse(
              () => const MemorizationProgress(surahNumber: 0, ayahNumber: 0),
            )
            .cumulativeRepeats,
        5,
      );
    });

    test('maps a negative repeat count onto a StorageFailure', () async {
      final ProgressRepository repository = ProgressRepositoryImpl(
        await openSource(),
      );

      final Either<Failure, Unit> result = await repository.recordRepeats(
        1,
        2,
        -1,
      );

      expect(result.isLeft(), isTrue);
      result.fold((Failure f) {
        expect(f, isA<StorageFailure>());
        expect(f.message, contains('must not be negative'));
      }, (_) => fail('expected a Left'));
    });
  });

  group('stumbles', () {
    test(
      'marking counts up and stamps the time; clearing keeps the rest',
      () async {
        final ProgressLocalDataSource source = await openSource();
        await source.recordRepeats(2, 5, 4);
        await source.markStumble(2, 5, at: DateTime(2026, 10, 1));
        await source.markStumble(2, 5, at: DateTime(2026, 10, 2));

        MemorizationProgress p = await source.get(2, 5);
        expect(p.stumbles, 2);
        expect(p.lastStumbleAt, DateTime(2026, 10, 2));
        expect(p.cumulativeRepeats, 4);

        await source.clearStumble(2, 5);
        p = await source.get(2, 5);
        expect(p.stumbles, 0);
        expect(p.lastStumbleAt, isNull);
        expect(p.cumulativeRepeats, 4, reason: 'only the mark comes off');
      },
    );

    test('lists the stumbled ayahs alone, the most recent first', () async {
      final ProgressLocalDataSource source = await openSource();
      await source.recordRepeats(1, 1, 3);
      await source.markStumble(1, 4, at: DateTime(2026, 10, 1));
      await source.markStumble(3, 2, at: DateTime(2026, 10, 5));
      await source.markStumble(2, 7, at: DateTime(2026, 10, 3));

      final List<MemorizationProgress> list = await source.stumbled();
      expect(list.map((MemorizationProgress p) => p.storageKey), <String>[
        '3:2',
        '2:7',
        '1:4',
      ]);
    });

    test('a malformed record costs that record, never the list', () async {
      final ProgressLocalDataSource source = await openSource();
      await source.markStumble(1, 2);
      final Box<Map<dynamic, dynamic>> box = Hive.box<Map<dynamic, dynamic>>(
        'memorization_progress',
      );
      await box.put('9:9', <String, dynamic>{'surahNumber': 'nine'});

      final List<MemorizationProgress> list = await source.stumbled();
      expect(list.single.storageKey, '1:2');
    });

    test('a record from before stumbles reads as having none', () {
      final MemorizationProgress p = MemorizationProgress.fromMap(
        <String, dynamic>{
          'surahNumber': 1,
          'ayahNumber': 2,
          'status': 'memorized',
          'cumulativeRepeats': 9,
        },
      );
      expect(p.stumbles, 0);
      expect(p.isStumbled, isFalse);
      expect(p.status, MemorizationStatus.memorized);
    });

    test('a stumble count of the wrong type reads as none', () {
      final MemorizationProgress p = MemorizationProgress.fromMap(
        <String, dynamic>{
          'surahNumber': 1,
          'ayahNumber': 2,
          'stumbles': 'three',
          'lastStumbleAt': 12,
        },
      );
      expect(p.stumbles, 0);
      expect(p.lastStumbleAt, isNull);
    });

    test('round-trips through the storage map', () {
      final MemorizationProgress p = MemorizationProgress(
        surahNumber: 4,
        ayahNumber: 11,
        stumbles: 2,
        lastStumbleAt: DateTime(2026, 10, 20, 8),
      );
      expect(MemorizationProgress.fromMap(p.toMap()), p);
    });

    test('undo takes back one stumble; the last one clears the mark', () async {
      final ProgressLocalDataSource source = await openSource();
      await source.markStumble(3, 4);
      await source.markStumble(3, 4);
      await source.undoStumble(3, 4);
      expect((await source.get(3, 4)).stumbles, 1);
      await source.undoStumble(3, 4);
      final MemorizationProgress p = await source.get(3, 4);
      expect(p.isStumbled, isFalse);
      expect(p.lastStumbleAt, isNull);
      await source.undoStumble(3, 4);
      expect((await source.get(3, 4)).stumbles, 0, reason: 'never below');
    });

    test('clearing a surah clears its stumbles too', () async {
      final ProgressLocalDataSource source = await openSource();
      await source.markStumble(1, 3);
      await source.clearSurah(1, 7);
      expect(await source.stumbled(), isEmpty);
    });

    test('the repository reports the same through Either', () async {
      final ProgressRepository repo = ProgressRepositoryImpl(
        await openSource(),
      );
      await repo.markStumble(2, 1);
      final Either<Failure, List<MemorizationProgress>> r = await repo
          .stumbled();
      expect(r.isRight(), isTrue);
      expect(
        r.getOrElse(() => const <MemorizationProgress>[]).single.storageKey,
        '2:1',
      );
    });
  });
}
