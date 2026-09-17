import 'package:sqflite/sqflite.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../models/ayah.dart';
import '../models/ayah_timing.dart';
import '../models/reciter.dart';
import '../models/surah.dart';
import 'ayah_sequence_validator.dart';
import 'quran_database.dart';
import 'quran_local_data_source.dart';

/// `QuranLocalDataSource`, backed by `quran.db` instead of the per-surah
/// ayah JSON files.
///
/// `quran.db` is the single source of truth for every surah/ayah fact:
/// names, ayah count, revelation place, bismillah placement, ayah text.
/// [Surah.nameEn] is the transliteration, read from `name_translit`.
/// `surahs.json` only decides *which* surahs the app currently ships (its
/// entries are the scope). Every fact both sources carry is cross-checked on
/// load; a disagreement throws rather than picking a side silently
/// (CLAUDE.md A.2 rule 1).
///
/// Reciters and timings are unaffected by this migration — `quran.db` has no
/// audio data — so those three methods delegate straight to [_legacy].
class QuranDbLocalDataSource implements QuranLocalDataSource {
  QuranDbLocalDataSource({
    required QuranDatabase database,
    required QuranLocalDataSource legacyJsonSource,
  }) : _db = database,
       _legacy = legacyJsonSource;

  final QuranDatabase _db;
  final QuranLocalDataSource _legacy;

  List<Surah>? _surahs;
  final Map<int, List<Ayah>> _ayahsBySurah = <int, List<Ayah>>{};

  @override
  Future<List<Surah>> getSurahs() async {
    final List<Surah>? cached = _surahs;
    if (cached != null) return cached;

    final List<Surah> jsonSurahs = await _legacy.getSurahs();
    final Database db = await _db.open();

    final List<Surah> merged = <Surah>[];
    for (final Surah jsonSurah in jsonSurahs) {
      merged.add(await _reconcile(jsonSurah, db));
    }

    merged.sort((Surah a, Surah b) => a.number.compareTo(b.number));
    return _surahs = List<Surah>.unmodifiable(merged);
  }

  Future<Surah> _reconcile(Surah jsonSurah, Database db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'surahs',
      where: 'id = ?',
      whereArgs: <int>[jsonSurah.number],
    );
    if (rows.isEmpty) {
      throw CatalogValidationException(
        AssetPaths.quranDatabase,
        'surahs.json lists surah ${jsonSurah.number}, which is not present '
        'in quran.db.',
      );
    }
    final Map<String, Object?> row = rows.single;

    final int dbAyahCount = row['ayah_count']! as int;
    _agreeOrThrow(
      jsonSurah.number,
      field: 'ayahCount',
      json: jsonSurah.ayahCount,
      db: dbAyahCount,
    );

    final String dbNameAr = row['name_ar']! as String;
    _agreeOrThrow(
      jsonSurah.number,
      field: 'nameAr',
      json: jsonSurah.nameAr,
      db: dbNameAr,
    );

    final RevelationPlace dbRevelation = RevelationPlace.fromJson(
      row['revelation']! as String,
      AssetPaths.quranDatabase,
    );
    _agreeOrThrow(
      jsonSurah.number,
      field: 'revelationPlace',
      json: jsonSurah.revelationPlace,
      db: dbRevelation,
    );

    final BismillahMode dbMode = _bismillahModeFromDb(
      row['basmala_mode']! as String,
      surahNumber: jsonSurah.number,
    );
    _agreeOrThrow(
      jsonSurah.number,
      field: 'bismillahMode',
      json: jsonSurah.bismillahMode,
      db: dbMode,
    );

    return Surah(
      number: jsonSurah.number,
      nameAr: dbNameAr,
      // Deliberately not cross-checked: the stub's spellings follow a
      // different convention ("Al-Fatiha" vs "Al-Fatihah"), and the whole list
      // must use one.
      nameEn: row['name_translit']! as String,
      ayahCount: dbAyahCount,
      revelationPlace: dbRevelation,
      bismillahMode: dbMode,
    );
  }

  void _agreeOrThrow(
    int surahNumber, {
    required String field,
    required Object json,
    required Object db,
  }) {
    if (json == db) return;
    throw CatalogValidationException(
      AssetPaths.quranDatabase,
      'Surah $surahNumber disagrees between surahs.json and quran.db on '
      '"$field": surahs.json says $json, quran.db says $db.',
    );
  }

  static BismillahMode _bismillahModeFromDb(
    String value, {
    required int surahNumber,
  }) => switch (value) {
    'first_ayah' => BismillahMode.countedAsAyah1,
    'none' => BismillahMode.none,
    'separate' => BismillahMode.separatePreamble,
    _ => throw CatalogValidationException(
      AssetPaths.quranDatabase,
      'Surah $surahNumber has unknown basmala_mode "$value".',
    ),
  };

  @override
  Future<Surah> getSurah(int surahNumber) async {
    final List<Surah> surahs = await getSurahs();
    for (final Surah surah in surahs) {
      if (surah.number == surahNumber) return surah;
    }
    throw CatalogValidationException(
      AssetPaths.surahsCatalog,
      'Surah $surahNumber is not in the catalog. Available: '
      '${surahs.map((Surah s) => s.number).join(', ')}.',
    );
  }

  @override
  Future<List<Ayah>> getAyahs(int surahNumber) async {
    final List<Ayah>? cached = _ayahsBySurah[surahNumber];
    if (cached != null) return cached;

    final Surah surah = await getSurah(surahNumber);
    final Database db = await _db.open();
    final List<Map<String, Object?>> rows = await db.query(
      'ayahs',
      where: 'surah = ?',
      whereArgs: <int>[surahNumber],
      orderBy: 'ayah',
    );

    final List<Ayah> ayahs = rows.map(Ayah.fromDbRow).toList();
    validateAyahSequence(ayahs, surah: surah, path: AssetPaths.quranDatabase);

    return _ayahsBySurah[surahNumber] = List<Ayah>.unmodifiable(ayahs);
  }

  @override
  Future<List<Reciter>> getReciters() => _legacy.getReciters();

  @override
  Future<Reciter> getReciter(String reciterId) => _legacy.getReciter(reciterId);

  @override
  Future<SurahTimings> getTimings({
    required String reciterId,
    required int surahNumber,
  }) => _legacy.getTimings(reciterId: reciterId, surahNumber: surahNumber);
}
