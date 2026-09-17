import 'package:sqflite/sqflite.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../models/ayah.dart';
import '../models/mushaf_line.dart';
import '../models/word.dart';
import 'quran_database.dart';

/// The mushaf page/line/word queries `quran.db` exists for, independent of
/// the surah-scoped catalog `QuranRepository` serves.
///
/// Unlike `QuranRepository` — whose surah list is scoped to whatever
/// `surahs.json` currently ships audio for — every method here works for any
/// of the 114 surahs `quran.db` carries, since none of it depends on audio
/// being available.
abstract class QuranPagesLocalDataSource {
  /// The ayahs that start, continue or end on [page], in ayah order. An ayah
  /// that spans a page boundary appears in full on every page it touches.
  Future<List<Ayah>> ayahsForPage(int page);

  /// Every printed line of [page], in top-to-bottom order.
  Future<List<MushafLine>> linesForPage(int page);

  /// The words that make up one line, in reading order.
  Future<List<Word>> wordsForLine(int page, int line);

  /// The page [surahNumber]:[ayahNumber] is printed on.
  Future<int> pageForAyah(int surahNumber, int ayahNumber);

  /// How many ayahs [surahNumber] has, read straight from `quran.db` — valid
  /// for any of the 114 surahs, not just the ones `surahs.json` currently
  /// scopes into the app.
  Future<int> ayahCount(int surahNumber);
}

class QuranPagesLocalDataSourceImpl implements QuranPagesLocalDataSource {
  QuranPagesLocalDataSourceImpl(this._database);

  final QuranDatabase _database;

  @override
  Future<List<Ayah>> ayahsForPage(int page) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'ayahs',
      where: 'page = ?',
      whereArgs: <int>[page],
      orderBy: 'surah, ayah',
    );
    if (rows.isEmpty) {
      throw CatalogValidationException(
        AssetPaths.quranDatabase,
        'Page $page has no ayahs in quran.db.',
      );
    }
    return rows.map(Ayah.fromDbRow).toList(growable: false);
  }

  @override
  Future<List<MushafLine>> linesForPage(int page) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'lines',
      where: 'page = ?',
      whereArgs: <int>[page],
      orderBy: 'line',
    );
    if (rows.isEmpty) {
      throw CatalogValidationException(
        AssetPaths.quranDatabase,
        'Page $page has no lines in quran.db.',
      );
    }
    return rows.map(MushafLine.fromRow).toList(growable: false);
  }

  @override
  Future<List<Word>> wordsForLine(int page, int line) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'words',
      where: 'page = ? AND line = ?',
      whereArgs: <int>[page, line],
      orderBy: 'position',
    );
    return rows.map(Word.fromRow).toList(growable: false);
  }

  @override
  Future<int> pageForAyah(int surahNumber, int ayahNumber) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'ayahs',
      columns: <String>['page'],
      where: 'surah = ? AND ayah = ?',
      whereArgs: <int>[surahNumber, ayahNumber],
    );
    if (rows.isEmpty) {
      throw CatalogValidationException(
        AssetPaths.quranDatabase,
        'quran.db has no ayah $surahNumber:$ayahNumber.',
      );
    }
    return rows.single['page']! as int;
  }

  @override
  Future<int> ayahCount(int surahNumber) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'surahs',
      columns: <String>['ayah_count'],
      where: 'id = ?',
      whereArgs: <int>[surahNumber],
    );
    if (rows.isEmpty) {
      throw CatalogValidationException(
        AssetPaths.quranDatabase,
        'quran.db has no surah $surahNumber.',
      );
    }
    return rows.single['ayah_count']! as int;
  }
}
