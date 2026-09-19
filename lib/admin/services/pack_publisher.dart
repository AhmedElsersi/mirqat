import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/error/exceptions.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../core/constants/cdn.dart';

/// Builds the pack a surah is downloaded as, and the manifest entry that makes
/// it visible to the app.
///
/// Uploading ayah files is not publishing. The app discovers a reciter only
/// through the manifest, and downloads a surah only as a pack — so a publish
/// that stops after the ayahs leaves audio in the bucket that nothing can
/// reach. This is the rest of the job (CLAUDE.md A.5).
class PackPublisher {
  PackPublisher({http.Client? client, this.manifestUrl = kManifestUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String manifestUrl;

  /// Zips [files] the way `tool/build_manifest.py` does, so a pack built here
  /// and one built there are the same bytes: stored (an mp3 does not
  /// compress), sorted, and with a fixed timestamp.
  List<int> buildPack(List<File> files) {
    final Archive archive = Archive();
    final List<File> sorted = <File>[...files]
      ..sort(
        (File a, File b) => p.basename(a.path).compareTo(p.basename(b.path)),
      );

    for (final File file in sorted) {
      final List<int> bytes = file.readAsBytesSync();
      archive.addFile(
        ArchiveFile(p.basename(file.path), bytes.length, bytes)
          // 1980-01-01, the zip epoch, and the same instant
          // `tool/build_manifest.py` writes. `archive` reads this as seconds
          // since the *Unix* epoch, so 0 would land on a date zip cannot hold
          // and the encoder writes something else entirely — a pack that the
          // generator could never reproduce byte for byte.
          ..lastModTime = _zipEpochSeconds
          ..mode = 0x1a4
          // Stored, because `tool/build_manifest.py` stores: the two sides of
          // the CDN must produce the same bytes, or the digest in the manifest
          // describes a pack nobody can rebuild. (An mp3 does not compress
          // anyway; deflating it costs CPU on both ends for nothing.)
          ..compression = CompressionType.none,
      );
    }
    return ZipEncoder().encode(archive);
  }

  /// The live manifest, or the empty one when it cannot be fetched.
  ///
  /// A failure here is not fatal: the operator gets a manifest built from
  /// scratch and a warning, which is better than a publish that stops because
  /// GitHub Pages was slow.
  Future<Map<String, dynamic>> fetchManifest() async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return _emptyManifest();
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : _emptyManifest();
    } on Object {
      return _emptyManifest();
    }
  }

  Map<String, dynamic> _emptyManifest() => <String, dynamic>{
    'schemaVersion': 1,
    'baseUrl': '',
    'mirrors': <String>[],
    'reciters': <Map<String, dynamic>>[],
  };

  /// [manifest] with this reciter in it, created or updated.
  ///
  /// This is what makes a reciter addable without an app release: the app's
  /// own catalog (`reciters.json`) ships with a build, but every reciter in
  /// the manifest is merged into it at runtime (CLAUDE.md A.5). A reciter
  /// added here appears, portrait and all, the next time the manifest is
  /// fetched.
  ///
  /// Their `version` and their surahs are left exactly as they are: this edits
  /// who the reciter is, never what they have recorded.
  Map<String, dynamic> mergeReciter({
    required Map<String, dynamic> manifest,
    required String id,
    required String nameAr,
    required String nameEn,
    required int bitrate,
    required String baseUrl,
    String riwayah = '',
    String? imagePath,
  }) {
    final Map<String, dynamic> next = <String, dynamic>{
      ...manifest,
      'schemaVersion': manifest['schemaVersion'] ?? 1,
      'baseUrl': baseUrl,
      'mirrors': manifest['mirrors'] ?? <String>[],
    };

    final List<Map<String, dynamic>> reciters = <Map<String, dynamic>>[
      for (final Object? entry
          in (manifest['reciters'] as List<dynamic>? ?? <dynamic>[]))
        if (entry is Map<String, dynamic>) Map<String, dynamic>.from(entry),
    ];

    Map<String, dynamic>? row = reciters
        .where((Map<String, dynamic> r) => r['id'] == id)
        .firstOrNull;
    if (row == null) {
      row = <String, dynamic>{
        'id': id,
        'version': '1',
        'audioPath': 'audio/{id}/{bitrate}/{s3}{a3}.mp3',
        'packPath': 'packs/{id}/{bitrate}/{s3}.zip',
        'totalBytes': 0,
        'surahs': <Map<String, dynamic>>[],
      };
      reciters.add(row);
    }

    row['nameAr'] = nameAr;
    row['nameEn'] = nameEn;
    row['riwayah'] = riwayah;
    row['bitrate'] = bitrate;
    if (imagePath != null) row['imagePath'] = imagePath;

    reciters.sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          '${a['id']}'.compareTo('${b['id']}'),
    );
    next['reciters'] = reciters;
    return next;
  }

  /// Where a reciter's portrait goes on the CDN.
  static String imageKeyFor(String reciterId, String extension) =>
      'images/$reciterId${extension.startsWith('.') ? extension : '.$extension'}';

  /// [manifest] with this surah recorded against this reciter.
  ///
  /// The reciter's row is created if it is new and left otherwise alone — its
  /// `version` in particular. Bumping a version invalidates every install of
  /// every surah that reciter has, so it is the operator's decision, not a
  /// side effect of publishing one surah.
  Map<String, dynamic> mergeSurah({
    required Map<String, dynamic> manifest,
    required Reciter reciter,
    required Surah surah,
    required int bitrate,
    required String baseUrl,
    required int packBytes,
    required String packSha256,
    required bool hasBasmala,
  }) {
    final Map<String, dynamic> next = <String, dynamic>{
      ...manifest,
      'schemaVersion': manifest['schemaVersion'] ?? 1,
      // The bucket the tool just uploaded to is the one the manifest should
      // point at; an empty or stale baseUrl is how audio goes missing.
      'baseUrl': baseUrl,
      'mirrors': manifest['mirrors'] ?? <String>[],
    };

    final List<Map<String, dynamic>> reciters = <Map<String, dynamic>>[
      for (final Object? entry
          in (manifest['reciters'] as List<dynamic>? ?? <dynamic>[]))
        if (entry is Map<String, dynamic>) Map<String, dynamic>.from(entry),
    ];

    Map<String, dynamic>? row = reciters
        .where((Map<String, dynamic> r) => r['id'] == reciter.id)
        .firstOrNull;

    if (row == null) {
      row = <String, dynamic>{
        'id': reciter.id,
        // Names come from the bundled catalog where the id matches one, so a
        // manifest reciter and the app's own list never disagree.
        'nameAr': reciter.nameAr,
        'nameEn': reciter.nameEn,
        'riwayah': '',
        'bitrate': bitrate,
        'version': '1',
        'audioPath': 'audio/{id}/{bitrate}/{s3}{a3}.mp3',
        'packPath': 'packs/{id}/{bitrate}/{s3}.zip',
        'totalBytes': 0,
        'surahs': <Map<String, dynamic>>[],
      };
      reciters.add(row);
    }

    final List<Map<String, dynamic>> surahs = <Map<String, dynamic>>[
      for (final Object? entry
          in (row['surahs'] as List<dynamic>? ?? <dynamic>[]))
        if (entry is Map<String, dynamic>) Map<String, dynamic>.from(entry),
    ]..removeWhere((Map<String, dynamic> s) => s['n'] == surah.number);

    surahs.add(<String, dynamic>{
      'n': surah.number,
      'ayahs': surah.ayahCount,
      'bytes': packBytes,
      'sha256': packSha256,
      'hasBasmala': hasBasmala,
    });
    surahs.sort(
      (Map<String, dynamic> a, Map<String, dynamic> b) =>
          (a['n'] as int).compareTo(b['n'] as int),
    );

    row['surahs'] = surahs;
    row['totalBytes'] = surahs.fold<int>(
      0,
      (int sum, Map<String, dynamic> s) => sum + (s['bytes'] as int? ?? 0),
    );

    next['reciters'] = reciters;
    return next;
  }

  /// Writes [manifest] where the operator can find it, and answers the file.
  ///
  /// Written beside the recording rather than into the app's bundle: this file
  /// has to be published to the Pages site by hand, and a path the operator
  /// just browsed to is one they can find again.
  File writeManifest({
    required Map<String, dynamic> manifest,
    required Directory directory,
  }) {
    final File file = File(p.join(directory.path, 'manifest.json'));
    try {
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
    } on FileSystemException catch (e) {
      throw ProcessingException(
        file.path,
        'Could not write the manifest: ${e.message}',
      );
    }
    return file;
  }

  /// 1980-01-01T00:00:00 local, which is what a DOS timestamp of zero means
  /// and what Python's `ZipInfo(date_time=(1980, 1, 1, 0, 0, 0))` writes. The
  /// encoder converts through the local zone, so the local midnight is the
  /// value that round-trips to the same stored field.
  static final int _zipEpochSeconds =
      DateTime(1980).millisecondsSinceEpoch ~/ 1000;

  static String digestOf(List<int> bytes) => sha256.convert(bytes).toString();

  void close() => _client.close();
}
