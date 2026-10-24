import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/constants/asset_paths.dart';
import '../core/theme/app_text_styles.dart';
import '../data/datasources/asset_reader.dart';
import 'audio/audio_storage.dart';
import 'audio/manifest_service.dart';

/// Hands a font's bytes to the engine under [family].
typedef FontRegistrar = Future<void> Function(String family, Uint8List bytes);

Future<void> _registerWithEngine(String family, Uint8List bytes) => (FontLoader(
  family,
)..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)))).load();

/// One packed page font, as `assets/data/qpc_v2_fonts.json` lists it.
class QpcPageFont {
  const QpcPageFont({
    required this.page,
    required this.bytes,
    required this.sha256,
  });

  final int page;

  /// The size and digest of the packed (gzip) file on the CDN.
  final int bytes;
  final String sha256;
}

/// The QPC V2 mushaf's page fonts: one font for each of the 604 pages, each
/// drawing that page's words from the glyph codes in `words.glyph_v2`.
///
/// Together they are about 136 MB packed, so none ships. A page's font is
/// fetched from the CDN the first time the page is drawn in this face —
/// a few hundred kilobytes — kept beside the audio, and read from disk ever
/// after; or every page's at once, when the reader asks for the whole set.
/// Every download is held to the size and digest the app ships for it
/// before it is used, as an audio pack is.
///
/// Quiet, like everything that fetches (CLAUDE.md A.2 rule 3): a page whose
/// font cannot be had is drawn in the bundled face, in the same layout,
/// until it can.
class QpcFontService {
  QpcFontService({
    required AssetReader assets,
    required ManifestService manifestService,
    required AudioStorage audioStorage,
    http.Client? client,
    FontRegistrar? registrar,
  }) : _reader = assets,
       _manifest = manifestService,
       _storage = audioStorage,
       _client = client ?? http.Client(),
       _register = registrar ?? _registerWithEngine;

  final AssetReader _reader;
  final ManifestService _manifest;
  final AudioStorage _storage;
  final http.Client _client;
  final FontRegistrar _register;

  static const String directoryName = 'fonts/qpc_v2';

  /// The pages whose fonts are registered and can be drawn with now. A new
  /// set each time one arrives, so a listener can tell.
  final ValueNotifier<Set<int>> loaded = ValueNotifier<Set<int>>(const <int>{});

  final Map<int, Future<bool>> _ensuring = <int, Future<bool>>{};

  /// When a page's font last failed to arrive. A page drawn again and again
  /// offline — every rebuild asks — is not fetched again until a while has
  /// passed.
  final Map<int, DateTime> _failedAt = <int, DateTime>{};
  static const Duration retryAfter = Duration(minutes: 1);
  Future<({String template, Map<int, QpcPageFont> pages})>? _list;

  Future<({String template, Map<int, QpcPageFont> pages})> _readList() =>
      _list ??= () async {
        final Map<String, dynamic> json =
            jsonDecode(await _reader.loadString(AssetPaths.qpcV2Fonts))
                as Map<String, dynamic>;
        return (
          template: json['path'] as String,
          pages: <int, QpcPageFont>{
            for (final dynamic raw in json['pages'] as List<dynamic>)
              (raw as Map<String, dynamic>)['n'] as int: QpcPageFont(
                page: raw['n'] as int,
                bytes: raw['bytes'] as int,
                sha256: raw['sha256'] as String,
              ),
          },
        );
      }();

  /// How many pages there are fonts for, and their packed size together.
  Future<({int pages, int bytes})> totals() async {
    final Map<int, QpcPageFont> pages = (await _readList()).pages;
    return (
      pages: pages.length,
      bytes: pages.values.fold(0, (int a, QpcPageFont f) => a + f.bytes),
    );
  }

  /// [page]'s font, registered: from disk, or fetched first. True once it
  /// can be drawn with. Concurrent calls for one page share one fetch.
  Future<bool> ensure(int page) {
    if (loaded.value.contains(page)) return Future<bool>.value(true);
    final DateTime? failed = _failedAt[page];
    if (failed != null && DateTime.now().difference(failed) < retryAfter) {
      return Future<bool>.value(false);
    }
    return _ensuring[page] ??= _ensure(page)
        .then((bool ok) {
          if (ok) {
            _failedAt.remove(page);
          } else {
            _failedAt[page] = DateTime.now();
          }
          return ok;
        })
        .whenComplete(() {
          // A block, not an arrow: `remove` returns this very future, and
          // whenComplete would wait on it — forever.
          _ensuring.remove(page);
        });
  }

  Future<bool> _ensure(int page) async {
    final File? file = await _fetched(page);
    if (file == null) return false;
    try {
      await _register(
        AppTextStyles.qpcPageFamily(page),
        file.readAsBytesSync(),
      );
    } on Object {
      // A file the engine will not take is no font: gone, to be fetched
      // afresh next time.
      _delete(file);
      return false;
    }
    loaded.value = <int>{...loaded.value, page};
    return true;
  }

  /// [page]'s font on disk, fetched if it is not there yet. Null when it
  /// could not be had.
  Future<File?> _fetched(int page) async {
    final File? file = await _fileFor(page);
    if (file == null) return null;
    if (file.existsSync() && file.lengthSync() > 0) return file;

    try {
      final ({String template, Map<int, QpcPageFont> pages}) list =
          await _readList();
      final QpcPageFont? expected = list.pages[page];
      if (expected == null) return null;
      // The fonts sit beside the audio: wherever the manifest says that is.
      await _manifest.load();
      final Uri url = _manifest.current.urlFor(
        list.template.replaceAll('{n3}', page.toString().padLeft(3, '0')),
      );
      final http.Response response = await _client
          .get(url)
          .timeout(const Duration(seconds: 30));
      final Uint8List packed = response.bodyBytes;
      // Length first, the cheap check a cut-off download fails; then the
      // digest the app shipped for this very file.
      if (response.statusCode != 200 ||
          packed.length != expected.bytes ||
          sha256.convert(packed).toString() != expected.sha256) {
        return null;
      }
      final List<int> font = const GZipDecoder().decodeBytes(packed);
      file.parent.createSync(recursive: true);
      // Beside the final name and renamed, so a half-written font is never
      // taken for a whole one.
      final File staging = File('${file.path}.part');
      staging.writeAsBytesSync(font, flush: true);
      staging.renameSync(file.path);
      return file;
    } on Object {
      return null;
    }
  }

  Future<File?> _fileFor(int page) async {
    await _storage.prepare();
    final Directory? root = _storage.root;
    if (root == null) return null;
    return File(
      p.join(
        root.path,
        directoryName,
        'p${page.toString().padLeft(3, '0')}.ttf',
      ),
    );
  }

  /// How many pages' fonts are on the device.
  Future<int> downloadedCount() async {
    final Directory? dir = await _directory();
    if (dir == null || !dir.existsSync()) return 0;
    return dir
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.ttf'))
        .length;
  }

  /// Fetches every page's font not yet on the device, one after another,
  /// telling [onProgress] how many of them are there. Stops early when
  /// [cancelled] says so. Answers how many could not be fetched.
  Future<int> downloadAll({
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final List<int> pages = (await _readList()).pages.keys.toList()..sort();
    int done = 0;
    int failed = 0;
    for (final int page in pages) {
      if (cancelled?.call() ?? false) break;
      if (await _fetched(page) == null) failed++;
      onProgress?.call(++done, pages.length);
    }
    return failed;
  }

  /// Removes every page font from the device. Those already in use stay
  /// drawable until the app is next started.
  Future<void> deleteAll() async {
    final Directory? dir = await _directory();
    if (dir != null && dir.existsSync()) dir.deleteSync(recursive: true);
  }

  Future<Directory?> _directory() async {
    await _storage.prepare();
    final Directory? root = _storage.root;
    return root == null ? null : Directory(p.join(root.path, directoryName));
  }

  static void _delete(File file) {
    try {
      file.deleteSync();
    } on Object {
      // Already gone.
    }
  }

  void close() {
    _client.close();
    loaded.dispose();
  }
}
