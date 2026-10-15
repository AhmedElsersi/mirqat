/// The batch's two pure parts: matching a folder's files to surahs, and the
/// README that tells the operator what still needs them.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/batch_split.dart';

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('mirqat_batch_pure');
  });

  tearDown(() {
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  });

  group('recordingsIn', () {
    test('the leading digits of the name are the surah, whatever follows', () {
      File('${folder.path}/001.mp3').createSync();
      File('${folder.path}/014 Ibrahim.wav').createSync();
      File('${folder.path}/114-an-nas.m4a').createSync();

      final List<BatchEntry> entries = recordingsIn(folder);

      expect(entries.map((BatchEntry e) => e.surahNumber), <int>[1, 14, 114]);
      expect(
        entries.map((BatchEntry e) => e.status),
        everyElement(BatchStatus.pending),
      );
    });

    test('what cannot be placed is reported, never silently skipped', () {
      File('${folder.path}/surah.mp3').createSync();
      File('${folder.path}/115.mp3').createSync();
      File('${folder.path}/000.mp3').createSync();

      final List<BatchEntry> entries = recordingsIn(folder);

      expect(entries, hasLength(3));
      expect(
        entries.map((BatchEntry e) => e.status),
        everyElement(BatchStatus.failed),
      );
      expect(entries.map((BatchEntry e) => e.surahNumber), everyElement(0));
    });

    test('hidden files and non-audio are not recordings at all', () {
      File('${folder.path}/.DS_Store').createSync();
      File('${folder.path}/notes.txt').createSync();
      File('${folder.path}/README.md').createSync();
      Directory('${folder.path}/002').createSync();

      expect(recordingsIn(folder), isEmpty);
    });

    test('two files claiming one surah both fail — the tool never guesses '
        'which take was meant', () {
      File('${folder.path}/002.mp3').createSync();
      File('${folder.path}/002 retake.mp3').createSync();
      File('${folder.path}/003.mp3').createSync();

      final List<BatchEntry> entries = recordingsIn(folder);

      expect(
        entries
            .where((BatchEntry e) => e.surahNumber == 2)
            .map((BatchEntry e) => e.status),
        everyElement(BatchStatus.failed),
      );
      expect(
        entries.firstWhere((BatchEntry e) => e.surahNumber == 3).status,
        BatchStatus.pending,
      );
    });
  });

  group('batchReadme', () {
    BatchEntry entry(int surah, BatchStatus status, [String detail = '']) =>
        BatchEntry(
          path: '/takes/${surah.toString().padLeft(3, '0')}.mp3',
          surahNumber: surah,
          status: status,
          detail: detail,
        );

    test('what needs attention is spelled out; what is clean is a count', () {
      final String readme = batchReadme(
        reciterId: 'ahmed_elajami',
        entries: <BatchEntry>[
          entry(1, BatchStatus.clean),
          entry(2, BatchStatus.suspect, 'ayah 2 (1.0 s) does not fit'),
          entry(3, BatchStatus.mismatch, '3 segments found, 4 expected.'),
        ],
        at: DateTime(2026, 10, 14, 12, 30),
      );

      expect(readme, contains('ahmed_elajami'));
      expect(readme, contains('1 clean'));
      expect(readme, contains('2 needing attention'));
      expect(readme, contains('002.mp3'));
      expect(readme, contains('ayah 2 (1.0 s) does not fit'));
      expect(readme, contains('003.mp3'));
      expect(readme, isNot(contains('001.mp3')));
      expect(readme, contains('2026-10-14 12:30'));
    });

    test('a batch with nothing wrong says so in words', () {
      final String readme = batchReadme(
        reciterId: 'r',
        entries: <BatchEntry>[entry(1, BatchStatus.clean)],
        at: DateTime(2026),
      );

      expect(readme, contains('Nothing needs attention'));
    });

    test('a stopped batch owns up to the files it never reached', () {
      final String readme = batchReadme(
        reciterId: 'r',
        entries: <BatchEntry>[
          entry(1, BatchStatus.clean),
          entry(2, BatchStatus.pending),
        ],
        at: DateTime(2026),
      );

      expect(readme, contains('1 not reached (the batch was stopped)'));
    });
  });
}
