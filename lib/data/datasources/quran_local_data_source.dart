import 'dart:convert';

import '../../core/constants/asset_paths.dart';
import '../../core/error/exceptions.dart';
import '../models/ayah.dart';
import '../models/ayah_timing.dart';
import '../models/reciter.dart';
import '../models/surah.dart';
import 'asset_reader.dart';

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

    _validateAyahSequence(ayahs, surah: surah, path: path);

    return _ayahsBySurah[surahNumber] = List<Ayah>.unmodifiable(ayahs);
  }

  /// The numbers must be a contiguous 1..`ayahCount` run — no duplicates, no
  /// gaps, nothing beyond the end, in ascending order — and the count must
  /// equal the catalog's.
  ///
  /// Checks run in the order that yields the most useful message: a file
  /// holding six ayahs where the catalog declares seven is more helpfully
  /// reported as "missing ayah 7" than as a bare count mismatch.
  void _validateAyahSequence(
    List<Ayah> ayahs, {
    required Surah surah,
    required String path,
  }) {
    final Set<int> seen = <int>{};
    for (final Ayah ayah in ayahs) {
      if (!seen.add(ayah.number)) {
        throw CatalogValidationException(
          path,
          'Surah ${surah.number} lists ayah ${ayah.number} more than once.',
        );
      }
    }

    for (final Ayah ayah in ayahs) {
      if (ayah.number > surah.ayahCount) {
        throw CatalogValidationException(
          path,
          'Surah ${surah.number} has ayah ${ayah.number}, beyond the '
          'ayahCount of ${surah.ayahCount} the catalog declares.',
        );
      }
    }

    for (int expected = 1; expected <= surah.ayahCount; expected++) {
      if (!seen.contains(expected)) {
        throw CatalogValidationException(
          path,
          'Surah ${surah.number} (${surah.nameEn}) is missing ayah $expected — '
          'the numbers must be a contiguous 1..${surah.ayahCount} sequence. '
          'Supply the missing text; it is never generated.',
        );
      }
    }

    // Implied by the three checks above, and kept as a net in case one of them
    // is ever loosened.
    if (ayahs.length != surah.ayahCount) {
      throw CatalogValidationException(
        path,
        'Surah ${surah.number} (${surah.nameEn}) declares ayahCount '
        '${surah.ayahCount} in the catalog, but the ayah file holds '
        '${ayahs.length}.',
      );
    }

    for (int i = 0; i < ayahs.length; i++) {
      if (ayahs[i].number != i + 1) {
        throw CatalogValidationException(
          path,
          'Surah ${surah.number} lists its ayahs out of order: position '
          '${i + 1} holds ayah ${ayahs[i].number}.',
        );
      }
    }

    for (final Ayah ayah in ayahs) {
      _assertArabicOnly(ayah, path);
    }
  }

  /// Guards the scope of the NFC normalizer, whose tables cover the Arabic
  /// blocks only. Text carrying a combining mark from another script would be
  /// silently mis-ordered rather than normalised, so it is rejected instead.
  void _assertArabicOnly(Ayah ayah, String path) {
    for (final int cp in ayah.text.runes) {
      if (_isArabicRange(cp) || _isAllowedNonArabic(cp)) continue;
      throw CatalogValidationException(
        path,
        'Ayah ${ayah.surahNumber}:${ayah.number} contains U+'
        '${cp.toRadixString(16).toUpperCase().padLeft(4, '0')}, which is '
        'outside the Arabic blocks. Normalization is Arabic-scoped, so this '
        'text cannot be safely compared — check the source encoding.',
      );
    }
  }

  static bool _isArabicRange(int cp) =>
      (cp >= 0x0600 && cp <= 0x06FF) ||
      (cp >= 0x0750 && cp <= 0x077F) ||
      (cp >= 0x0870 && cp <= 0x089F) ||
      (cp >= 0x08A0 && cp <= 0x08FF) ||
      (cp >= 0xFB50 && cp <= 0xFDFF) ||
      (cp >= 0xFE70 && cp <= 0xFEFF);

  /// Space, and the zero-width joiners that Arabic typography sometimes uses.
  static bool _isAllowedNonArabic(int cp) =>
      cp == 0x0020 || cp == 0x200C || cp == 0x200D;

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
