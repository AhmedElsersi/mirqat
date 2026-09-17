import 'dart:convert';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../models/ayah.dart';
import '../models/ayah_timing.dart';
import '../models/reciter.dart';
import '../models/surah.dart';
import 'asset_reader.dart';
import 'ayah_sequence_validator.dart';

/// Loads the JSON catalog — the single source of truth for surahs, ayah text,
/// reciters and timings.
///
/// Every load is validated against the catalog and fails loudly on any
/// disagreement. Nothing is padded, trimmed or repaired
/// (CLAUDE.md A.2 rule 1).
abstract class QuranLocalDataSource {
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
  QuranLocalDataSourceImpl(this._assets);

  final AssetReader _assets;

  List<Surah>? _surahs;
  List<Reciter>? _reciters;
  final Map<int, List<Ayah>> _ayahsBySurah = <int, List<Ayah>>{};
  final Map<String, SurahTimings> _timings = <String, SurahTimings>{};

  @override
  Future<List<Surah>> getSurahs() async {
    final List<Surah>? cached = _surahs;
    if (cached != null) return cached;

    const String path = AssetPaths.surahsCatalog;
    final List<dynamic> raw = _decodeList(await _assets.loadString(path), path);

    final List<Surah> surahs = <Surah>[];
    final Set<int> seen = <int>{};
    for (final Object? entry in raw) {
      if (entry is! Map<String, dynamic>) {
        throw CatalogValidationException(
          path,
          'Surah catalog contains a non-object entry: $entry.',
        );
      }
      final Surah surah = Surah.fromJson(entry, path);
      if (!seen.add(surah.number)) {
        throw CatalogValidationException(
          path,
          'Surah catalog lists surah ${surah.number} more than once.',
        );
      }
      surahs.add(surah);
    }

    if (surahs.isEmpty) {
      throw CatalogValidationException(path, 'Surah catalog is empty.');
    }

    surahs.sort((Surah a, Surah b) => a.number.compareTo(b.number));
    return _surahs = List<Surah>.unmodifiable(surahs);
  }

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
    final String path = AssetPaths.ayahsForSurah(surahNumber);
    final Map<String, dynamic> doc = _decodeObject(
      await _assets.loadString(path),
      path,
    );

    final Object? declaredSurah = doc['surah'];
    if (declaredSurah != surahNumber) {
      throw CatalogValidationException(
        path,
        'Ayah file declares surah $declaredSurah but was loaded for surah '
        '$surahNumber.',
      );
    }

    final Object? rawAyahs = doc['ayahs'];
    if (rawAyahs is! List) {
      throw CatalogValidationException(
        path,
        'Ayah file for surah $surahNumber is missing an "ayahs" list.',
      );
    }

    final List<Ayah> ayahs = <Ayah>[];
    for (final Object? entry in rawAyahs) {
      if (entry is! Map<String, dynamic>) {
        throw CatalogValidationException(
          path,
          'Ayah file for surah $surahNumber has a non-object entry in "ayahs".',
        );
      }
      ayahs.add(
        Ayah.fromJson(entry, surahNumber: surahNumber, assetPath: path),
      );
    }

    validateAyahSequence(ayahs, surah: surah, path: path);

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
