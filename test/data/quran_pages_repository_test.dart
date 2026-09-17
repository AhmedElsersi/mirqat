import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_database.dart';
import 'package:mirqat/data/datasources/quran_pages_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/mushaf_line.dart';
import 'package:mirqat/data/models/word.dart';
import 'package:mirqat/data/repositories/quran_pages_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('page 1 opens with the surah_name line, then Al-Fatiha ayah 1', () async {
    final List<MushafLine> lines =
        (await repository.linesForPage(1)).getOrElse(() => <MushafLine>[]);

    expect(lines.first.lineType, LineType.surahName);
    expect(lines.first.surahNumber, 1);
    expect(lines.first.firstWordId, isNull);

    expect(lines[1].lineType, LineType.ayah);
    expect(lines[1].surahNumber, isNull);
    expect(lines[1].firstWordId, isNotNull);
  });

  test('words on the surah-name line are empty; the first ayah line is not', () async {
    final List<Word> headerWords =
        (await repository.wordsForLine(1, 1)).getOrElse(() => <Word>[]);
    expect(headerWords, isEmpty);

    final List<Word> ayahWords =
        (await repository.wordsForLine(1, 2)).getOrElse(() => <Word>[]);
    expect(ayahWords, isNotEmpty);
    expect(ayahWords.first.text, 'بِسۡمِ');
  });

  test('ayahsForPage(1) starts with Al-Fatiha 1:1', () async {
    final List<Ayah> ayahs =
        (await repository.ayahsForPage(1)).getOrElse(() => <Ayah>[]);
    expect(ayahs.first.surahNumber, 1);
    expect(ayahs.first.number, 1);
  });

  test('pageForAyah and ayahCount agree with the mushaf', () async {
    expect((await repository.pageForAyah(1, 1)).getOrElse(() => -1), 1);
    expect((await repository.ayahCount(1)).getOrElse(() => -1), 7);
    expect((await repository.ayahCount(2)).getOrElse(() => -1), 286);
  });
}
