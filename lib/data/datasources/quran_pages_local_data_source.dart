import 'package:sqflite_common/sqlite_api.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../models/juz_info.dart';
import '../models/page_info.dart';
import '../models/ayah.dart';
import '../models/mushaf_line.dart';
import '../models/word.dart';
import 'quran_database_opener.dart';

/// The mushaf page/line/word queries over `quran.db`.
abstract class QuranPagesLocalDataSource {
  /// The ayahs that start, continue or end on [page], in ayah order. An ayah
  /// that spans a page boundary appears in full on every page it touches.
  Future<List<Ayah>> ayahsForPage(int page);

  /// Every printed line of [page], in top-to-bottom order.
  Future<List<MushafLine>> linesForPage(int page);

  /// The words that make up one line, in reading order.
  Future<List<Word>> wordsForLine(int page, int line);

  /// Words [firstId]..[lastId] inclusive, ordered by id — the reading order.
  /// A mushaf line is exactly such a range.
  Future<List<Word>> wordsInRange(int firstId, int lastId);

  /// Every word of one ayah, its ayah-number marker included, ordered by id.
  Future<List<Word>> wordsForAyah(int surahNumber, int ayahNumber);

  /// How many pages the layout has.
  /// The surah, juz and hizb the page opens in, or null for a page with no
  /// words on it.
  Future<PageInfo?> pageInfo(int page, {int? fromWordId});

  /// Every juz and where it begins, in order.
  Future<List<JuzInfo>> juzList();

  Future<int> pageCount();

  /// The most lines any page holds — the height a full page is laid out for.
  Future<int> linesPerFullPage();

  /// The page [surahNumber]:[ayahNumber] is printed on.
  Future<int> pageForAyah(int surahNumber, int ayahNumber);

  /// The page [surahNumber]'s heading is printed on, or null if the layout
  /// gives it none. Not always the page of its first ayah: a heading can be
  /// the last line of the page before.
  Future<int?> surahHeadingPage(int surahNumber);

  /// How many ayahs [surahNumber] has, read straight from `quran.db`.
  Future<int> ayahCount(int surahNumber);
}

class QuranPagesLocalDataSourceImpl implements QuranPagesLocalDataSource {
  QuranPagesLocalDataSourceImpl(this._database);

  final QuranDatabaseOpener _database;

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
      // By id, not position: position counts within an ayah, and most lines
      // carry the end of one ayah and the start of the next.
      orderBy: 'id',
    );
    return rows.map(Word.fromRow).toList(growable: false);
  }

  @override
  Future<List<Word>> wordsInRange(int firstId, int lastId) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'words',
      where: 'id BETWEEN ? AND ?',
      whereArgs: <int>[firstId, lastId],
      orderBy: 'id',
    );
    return rows.map(Word.fromRow).toList(growable: false);
  }

  @override
  Future<List<Word>> wordsForAyah(int surahNumber, int ayahNumber) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'words',
      where: 'surah = ? AND ayah = ?',
      whereArgs: <int>[surahNumber, ayahNumber],
      orderBy: 'id',
    );
    if (rows.isEmpty) {
      throw CatalogValidationException(
        AssetPaths.quranDatabase,
        'quran.db has no words for ayah $surahNumber:$ayahNumber.',
      );
    }
    return rows.map(Word.fromRow).toList(growable: false);
  }

  @override
  Future<PageInfo?> pageInfo(int page, {int? fromWordId}) async {
    final Database db = await _database.open();
    // The first word on the page, not the first ayah to *start* on it: a page
    // usually opens in the middle of an ayah that began on the one before.
    // [fromWordId] moves "first" down the page, for a page shown from part-way
    // — a surah that begins mid-page is labelled with its own juz, not with
    // that of the lines above it.
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT a.surah AS surah, a.juz AS juz, a.hizb AS hizb '
      'FROM words w JOIN ayahs a ON a.surah = w.surah AND a.ayah = w.ayah '
      'WHERE w.page = ? AND w.id >= ? ORDER BY w.id LIMIT 1',
      <Object>[page, fromWordId ?? 0],
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.single;
    return PageInfo(
      surahNumber: row['surah']! as int,
      juz: row['juz']! as int,
      hizb: row['hizb']! as int,
    );
  }

  /// Thirty rows out of a read-only database: read once, kept for good.
  Future<List<JuzInfo>>? _juzList;

  @override
  Future<List<JuzInfo>> juzList() => _juzList ??= _readJuzList();

  Future<List<JuzInfo>> _readJuzList() async {
    final Database db = await _database.open();
    // The first ayah of each juz is the one with the lowest id in it.
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT a.juz AS juz, a.surah AS surah, a.ayah AS ayah, a.page AS page '
      'FROM ayahs a JOIN (SELECT juz, MIN(id) AS first FROM ayahs GROUP BY juz) '
      'f ON f.first = a.id ORDER BY a.juz',
    );
    return <JuzInfo>[
      for (final Map<String, Object?> row in rows)
        JuzInfo(
          number: row['juz']! as int,
          surahNumber: row['surah']! as int,
          ayahNumber: row['ayah']! as int,
          page: row['page']! as int,
        ),
    ];
  }

  @override
  Future<int> pageCount() async {
    final Database db = await _database.open();
    return (await db.rawQuery('SELECT MAX(page) AS n FROM lines')).single['n']!
        as int;
  }

  @override
  Future<int> linesPerFullPage() async {
    final Database db = await _database.open();
    return (await db.rawQuery(
          'SELECT MAX(c) AS n FROM '
          '(SELECT COUNT(*) AS c FROM lines GROUP BY page)',
        )).single['n']!
        as int;
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
  Future<int?> surahHeadingPage(int surahNumber) async {
    final Database db = await _database.open();
    final List<Map<String, Object?>> rows = await db.query(
      'lines',
      columns: <String>['page'],
      where: "line_type = 'surah_name' AND surah_number = ?",
      whereArgs: <int>[surahNumber],
      orderBy: 'page',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['page']! as int;
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
