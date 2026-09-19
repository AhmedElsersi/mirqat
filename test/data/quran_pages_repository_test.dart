import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/mushaf_line.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../quran_db_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory storageDir;
  late QuranPagesRepository repository;

  setUp(() {
    storageDir = Directory.systemTemp.createTempSync('quran_pages_test');
    repository = QuranPagesRepositoryImpl(
      QuranPagesLocalDataSourceImpl(
        QuranDatabase(
          factory: databaseFactoryFfi,
          resolveStorageDirectory: () async => storageDir,
        ),
      ),
    );
  });

  tearDown(() {
    if (storageDir.existsSync()) storageDir.deleteSync(recursive: true);
  });

  test(
    'page 1 opens with the surah_name line, then Al-Fatiha ayah 1',
    () async {
      final List<MushafLine> lines = (await repository.linesForPage(
        1,
      )).getOrElse(() => <MushafLine>[]);

      expect(lines.first.lineType, LineType.surahName);
      expect(lines.first.surahNumber, 1);
      expect(lines.first.firstWordId, isNull);

      expect(lines[1].lineType, LineType.ayah);
      expect(lines[1].surahNumber, isNull);
      expect(lines[1].firstWordId, isNotNull);
    },
  );

  test(
    'words on the surah-name line are empty; the first ayah line is not',
    () async {
      final List<Word> headerWords = (await repository.wordsForLine(
        1,
        1,
      )).getOrElse(() => <Word>[]);
      expect(headerWords, isEmpty);

      final List<Word> ayahWords = (await repository.wordsForLine(
        1,
        2,
      )).getOrElse(() => <Word>[]);
      expect(ayahWords, isNotEmpty);
      expect(ayahWords.first.text, 'بِسۡمِ');
    },
  );

  test('ayahsForPage(1) starts with Al-Fatiha 1:1', () async {
    final List<Ayah> ayahs = (await repository.ayahsForPage(
      1,
    )).getOrElse(() => <Ayah>[]);
    expect(ayahs.first.surahNumber, 1);
    expect(ayahs.first.number, 1);
  });

  test('pageForAyah and ayahCount agree with the mushaf', () async {
    expect((await repository.pageForAyah(1, 1)).getOrElse(() => -1), 1);
    expect((await repository.ayahCount(1)).getOrElse(() => -1), 7);
    expect((await repository.ayahCount(2)).getOrElse(() => -1), 286);
  });

  test('a line spanning two ayahs reads in word-id order', () async {
    // Position counts within an ayah; ordering by it put the next ayah's
    // opening words in front of the previous ayah's closing ones.
    final Database db = await RepoQuranDatabase().open();
    final Map<String, Object?> line = (await db.rawQuery(
      "SELECT page, line FROM lines l WHERE line_type = 'ayah' AND "
      '(SELECT COUNT(DISTINCT surah * 1000 + ayah) FROM words w '
      'WHERE w.id BETWEEN l.first_word_id AND l.last_word_id) > 1 '
      'ORDER BY page, line LIMIT 1',
    )).single;

    final List<Word> words = (await repository.wordsForLine(
      line['page']! as int,
      line['line']! as int,
    )).getOrElse(() => <Word>[]);
    final List<int> ids = words.map((Word w) => w.id).toList();

    expect(ids, orderedEquals(List<int>.of(ids)..sort()));
    expect(
      words.map((Word w) => '${w.surahNumber}:${w.ayahNumber}').toSet(),
      hasLength(greaterThan(1)),
    );
  });

  test('wordsInRange returns exactly the range, by id', () async {
    final List<Word> words = (await repository.wordsInRange(
      1,
      5,
    )).getOrElse(() => <Word>[]);
    expect(words.map((Word w) => w.id), <int>[1, 2, 3, 4, 5]);
  });

  test('page count and full-page line count come from the layout', () async {
    final Database db = await RepoQuranDatabase().open();
    Future<int> scalar(String sql) async =>
        (await db.rawQuery(sql)).single.values.single! as int;

    expect(
      (await repository.pageCount()).getOrElse(() => -1),
      await scalar('SELECT MAX(page) FROM lines'),
    );
    expect(
      (await repository.linesPerFullPage()).getOrElse(() => -1),
      await scalar(
        'SELECT MAX(c) FROM (SELECT COUNT(*) c FROM lines GROUP BY page)',
      ),
    );
  });
}
