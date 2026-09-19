import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/asset_paths.dart';
import '../../core/constants/cdn.dart';
import '../../data/datasources/asset_reader.dart';
import '../../data/models/audio_manifest.dart';


/// The audio manifest, from the best source available.
///
/// [load] answers straight away from the disk cache, or the bundled copy when
/// there is none, and refreshes from the network in the background. Nothing
/// here ever throws or waits on the network before answering: a failed fetch
/// just leaves the last good manifest in place (CLAUDE.md A.2 rule 3).
class ManifestService {
  ManifestService(
    this._assets, {
    http.Client? client,
    Future<Directory> Function()? storageDirectory,
    this.url = kManifestUrl,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  final AssetReader _assets;
  final http.Client _client;
  final Future<Directory> Function() _storageDirectory;
  final String url;
  final Duration timeout;

  static const String _cacheFileName = 'manifest.json';

  AudioManifest _current = AudioManifest.empty;
  Future<AudioManifest>? _loading;
  final StreamController<AudioManifest> _changes =
      StreamController<AudioManifest>.broadcast();

  /// The manifest in use right now.
  AudioManifest get current => _current;

  /// Emits whenever a newer manifest replaces [current].
  Stream<AudioManifest> get changes => _changes.stream;

  /// The local manifest, loaded once; kicks off a background refresh.
  Future<AudioManifest> load() =>
      _loading ??= _loadLocal().then((AudioManifest local) {
        _set(local);
        unawaited(refresh());
        return local;
      });

  /// Fetches the manifest, caches it and makes it current. On any failure the
  /// current manifest stays and is returned.
  Future<AudioManifest> refresh() async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(url))
          .timeout(timeout);
      if (response.statusCode != 200) return _current;

      final String body = utf8.decode(response.bodyBytes);
      final AudioManifest fetched = AudioManifest.fromJson(
        jsonDecode(body),
        url,
      );
      _set(fetched);
      // Made current first, cached second: the cache only saves the next cold
      // start a fetch, so a directory that cannot be written costs the cache
      // and not the manifest already in hand.
      await _tryWriteCache(body);
    } on Object {
      // Offline, timed out, unreachable, or not a manifest: keep what we have.
    }
    return _current;
  }

  Future<AudioManifest> _loadLocal() async {
    final AudioManifest? cached = await _readCache();
    if (cached != null) return cached;
    try {
      return AudioManifest.fromJson(
        jsonDecode(await _assets.loadString(AssetPaths.bundledManifest)),
        AssetPaths.bundledManifest,
      );
    } on Object {
      return AudioManifest.empty;
    }
  }

  Future<AudioManifest?> _readCache() async {
    try {
      final File file = await _cacheFile();
      if (!file.existsSync()) return null;
      return AudioManifest.fromJson(
        jsonDecode(await file.readAsString()),
        file.path,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _tryWriteCache(String body) async {
    try {
      await _writeCache(body);
    } on Object {
      // No writable storage: the manifest stays in memory for this run.
    }
  }

  Future<void> _writeCache(String body) async {
    final File file = await _cacheFile();
    await file.parent.create(recursive: true);
    // Beside the final name, then renamed: a half-written cache would be
    // unreadable on the next cold start.
    final File staging = File('${file.path}.part');
    await staging.writeAsString(body, flush: true);
    await staging.rename(file.path);
  }

  Future<File> _cacheFile() async =>
      File(p.join((await _storageDirectory()).path, _cacheFileName));

  void _set(AudioManifest manifest) {
    if (manifest == _current) return;
    _current = manifest;
    _changes.add(manifest);
  }

  Future<void> dispose() => _changes.close();
}
