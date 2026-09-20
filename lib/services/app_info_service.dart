import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants/asset_paths.dart';
import '../core/constants/cdn.dart';
import '../data/datasources/asset_reader.dart';
import '../data/models/app_info.dart';

/// What the app says about itself — About us, Our goal, the developer's card —
/// and which versions of it the stores are on, from the best source available.
///
/// The same shape as `ManifestService`, for the same reasons. [load] answers
/// straight away from the copy cached on the device, or the one bundled with
/// the app when there is none, and refreshes from the network in the
/// background. Nothing here throws or waits on the network before answering:
/// a fetch that fails leaves the last good copy in place, and says nothing
/// (CLAUDE.md A.2 rule 3).
///
/// A fetched file that says *nothing* — not JSON, not an object, an empty
/// object — is not taken up. A hosting error page must not be able to blank
/// the About screen or lift an update rule.
class AppInfoService {
  AppInfoService(
    this._assets, {
    http.Client? client,
    Future<Directory> Function()? storageDirectory,
    this.url = kAppInfoUrl,
    this.timeout = const Duration(seconds: 5),
  }) : _client = client ?? http.Client(),
       _storageDirectory = storageDirectory ?? getApplicationSupportDirectory;

  final AssetReader _assets;
  final http.Client _client;
  final Future<Directory> Function() _storageDirectory;
  final String url;
  final Duration timeout;

  static const String _cacheFileName = 'app.json';

  AppInfo _current = AppInfo.empty;
  Future<AppInfo>? _loading;
  final StreamController<AppInfo> _changes =
      StreamController<AppInfo>.broadcast();

  AppInfo get current => _current;

  /// Emits whenever a newer copy replaces [current].
  Stream<AppInfo> get changes => _changes.stream;

  /// Where a path written in the file points: an address as it stands, a
  /// relative path against the file's own location.
  Uri? resolve(String reference) {
    final String trimmed = reference.trim();
    if (trimmed.isEmpty) return null;
    try {
      return Uri.parse(url).resolve(trimmed);
    } on FormatException {
      return null;
    }
  }

  /// The local copy, loaded once; kicks off a background refresh.
  Future<AppInfo> load() => _loading ??= _loadLocal().then((AppInfo local) {
    _set(local);
    unawaited(refresh());
    return local;
  });

  /// Fetches the file, caches it and makes it current. On any failure the
  /// current copy stays and is returned.
  Future<AppInfo> refresh() async {
    try {
      final http.Response response = await _client
          .get(Uri.parse(url))
          .timeout(timeout);
      if (response.statusCode != 200) return _current;

      final String body = utf8.decode(response.bodyBytes);
      final AppInfo fetched = AppInfo.parse(body);
      if (fetched == AppInfo.empty) return _current;

      _set(fetched);
      await _tryWriteCache(body);
    } on Object {
      // Offline, timed out, unreachable: keep what we have.
    }
    return _current;
  }

  Future<AppInfo> _loadLocal() async {
    final AppInfo? cached = await _readCache();
    if (cached != null) return cached;
    try {
      return AppInfo.parse(await _assets.loadString(AssetPaths.bundledAppInfo));
    } on Object {
      return AppInfo.empty;
    }
  }

  Future<AppInfo?> _readCache() async {
    try {
      final File file = await _cacheFile();
      if (!file.existsSync()) return null;
      final AppInfo cached = AppInfo.parse(await file.readAsString());
      return cached == AppInfo.empty ? null : cached;
    } on Object {
      return null;
    }
  }

  Future<void> _tryWriteCache(String body) async {
    try {
      final File file = await _cacheFile();
      await file.parent.create(recursive: true);
      // Beside the final name, then renamed: a half-written cache would be
      // unreadable on the next cold start.
      final File staging = File('${file.path}.part');
      await staging.writeAsString(body, flush: true);
      await staging.rename(file.path);
    } on Object {
      // No writable storage: the copy stays in memory for this run.
    }
  }

  Future<File> _cacheFile() async =>
      File(p.join((await _storageDirectory()).path, _cacheFileName));

  void _set(AppInfo info) {
    if (info == _current) return;
    _current = info;
    _changes.add(info);
  }

  Future<void> dispose() => _changes.close();
}
