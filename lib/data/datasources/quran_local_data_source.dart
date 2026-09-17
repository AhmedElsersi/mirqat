import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../models/ayah.dart';
import '../models/ayah_timing.dart';
import '../models/reciter.dart';
import '../models/surah.dart';
import 'asset_reader.dart';
import 'ayah_sequence_validator.dart';
import 'quran_database_opener.dart';

/// Loads the catalog: every surah and its ayah text from `quran.db`, reciters
/// and timings from the JSON under `assets/data/`.
///
/// The surah list is the whole mushaf. It knows nothing about audio — whether
/// a reciter has a surah is `AudioAvailability`'s question, never a filter
/// here, because reading does not depend on audio.
///
/// Every load is validated and fails loudly on any disagreement. Nothing is
/// padded, trimmed or repaired (CLAUDE.md A.2 rule 1).
abstract class QuranLocalDataSource {
  /// Every surah in `quran.db`, ordered by number.
  Future<List<Surah>> getSurahs();

  Future<Surah> getSurah(int surahNumber);

  /// Ayahs for a surah, NFC-normalised, ordered 1..ayahCount.
  Future<List<Ayah>> getAyahs(int surahNumber);

  Future<List<Reciter>> getReciters();

  Future<Reciter> getReciter(String reciterId);

  Future<SurahTimings> getTimings({
    required String reciterId,
    required int surahNumber,
  });
}

class QuranLocalDataSourceImpl implements QuranLocalDataSource {
  QuranLocalDataSourceImpl(this._assets, this._database);

  final AssetReader _assets;
  final QuranDatabaseOpener _database;

  List<Surah>? _surahs;
  Map<int, Surah>? _surahsByNumber;
  List<Reciter>? _reciters;
  final Map<int, List<Ayah>> _ayahsBySurah = <int, List<Ayah>>{};
  final Map<String, SurahTimings> _timings = <String, SurahTimings>{};

  @override
  Future<List<Surah>> getSurahs() async {
    final List<Surah>? cached = _surahs;
    if (cached != null) return cached;

    final Database db = await _database.open();
    final List<Surah> surahs = (await db.query(
      'surahs',
      orderBy: 'id',
    )).map(Surah.fromDbRow).toList();

    if (surahs.isEmpty) {
      throw const CatalogValidationException(
        AssetPaths.quranDatabase,
        'quran.db holds no surahs.',
      );
    }

    _surahsByNumber = <int, Surah>{
      for (final Surah surah in surahs) surah.number: surah,
    };
    return _surahs = List<Surah>.unmodifiable(surahs);
  }

  @override
  Future<Surah> getSurah(int surahNumber) async {
    await getSurahs();
    final Surah? surah = _surahsByNumber![surahNumber];
    if (surah != null) return surah;
    throw CatalogValidationException(
      AssetPaths.quranDatabase,
      'Surah $surahNumber is not in quran.db.',
    );
  }

  @override
  Future<List<Ayah>> getAyahs(int surahNumber) async {
    final List<Ayah>? cached = _ayahsBySurah[surahNumber];
    if (cached != null) return cached;

    final Surah surah = await getSurah(surahNumber);
    final Database db = await _database.open();
    final List<Ayah> ayahs = (await db.query(
      'ayahs',
      where: 'surah = ?',
      whereArgs: <int>[surahNumber],
      orderBy: 'ayah',
    )).map(Ayah.fromDbRow).toList();

    validateAyahSequence(ayahs, surah: surah, path: AssetPaths.quranDatabase);

    return _ayahsBySurah[surahNumber] = List<Ayah>.unmodifiable(ayahs);
  }

  @override
  Future<List<Reciter>> getReciters() async {
    final List<Reciter>? cached = _reciters;
    if (cached != null) return cached;

    const String path = AssetPaths.recitersCatalog;
    final List<dynamic> raw = _decodeList(await _assets.loadString(path), path);

    final List<Reciter> reciters = <Reciter>[];
    final Set<String> seen = <String>{};
    for (final Object? entry in raw) {
      if (entry is! Map<String, dynamic>) {
        throw CatalogValidationException(
          path,
          'Reciter catalog contains a non-object entry: $entry.',
        );
      }
      final Reciter reciter = Reciter.fromJson(entry, path);
      if (!seen.add(reciter.id)) {
        throw CatalogValidationException(
          path,
          'Reciter catalog lists id "${reciter.id}" more than once.',
        );
      }
      reciters.add(reciter);
    }

    if (reciters.isEmpty) {
      throw CatalogValidationException(path, 'Reciter catalog is empty.');
    }

    return _reciters = List<Reciter>.unmodifiable(reciters);
  }

  @override
  Future<Reciter> getReciter(String reciterId) async {
    final List<Reciter> reciters = await getReciters();
    for (final Reciter reciter in reciters) {
      if (reciter.id == reciterId) return reciter;
    }
    throw CatalogValidationException(
      AssetPaths.recitersCatalog,
      'Reciter "$reciterId" is not in the catalog. Available: '
      '${reciters.map((Reciter r) => r.id).join(', ')}.',
    );
  }

  @override
  Future<SurahTimings> getTimings({
    required String reciterId,
    required int surahNumber,
  }) async {
    final String cacheKey = '$reciterId/$surahNumber';
    final SurahTimings? cached = _timings[cacheKey];
    if (cached != null) return cached;

    final Surah surah = await getSurah(surahNumber);
    final String path = AssetPaths.timingsForSurah(reciterId, surahNumber);
    final SurahTimings timings = SurahTimings.fromJson(
      _decodeObject(await _assets.loadString(path), path),
      expectedSurahNumber: surahNumber,
      assetPath: path,
    );

    for (int number = 1; number <= surah.ayahCount; number++) {
      if (!timings.ayahs.containsKey(number)) {
        throw CatalogValidationException(
          path,
          'Timings for "$reciterId" surah $surahNumber are missing ayah '
          '$number of ${surah.ayahCount}.',
        );
      }
    }
    if (timings.ayahs.length != surah.ayahCount) {
      throw CatalogValidationException(
        path,
        'Timings for "$reciterId" surah $surahNumber hold '
        '${timings.ayahs.length} entries but the catalog declares '
        '${surah.ayahCount} ayahs.',
      );
    }

    return _timings[cacheKey] = timings;
  }

  List<dynamic> _decodeList(String source, String path) {
    final Object? decoded = _decode(source, path);
    if (decoded is! List) {
      throw AssetParseException(
        path,
        'Expected a JSON array at the top level, got ${decoded.runtimeType}.',
      );
    }
    return decoded;
  }

  Map<String, dynamic> _decodeObject(String source, String path) {
    final Object? decoded = _decode(source, path);
    if (decoded is! Map<String, dynamic>) {
      throw AssetParseException(
        path,
        'Expected a JSON object at the top level, got ${decoded.runtimeType}.',
      );
    }
    return decoded;
  }

  Object? _decode(String source, String path) {
    try {
      return jsonDecode(source);
    } on FormatException catch (e) {
      throw AssetParseException(path, 'Invalid JSON: ${e.message}');
    }
  }
}
