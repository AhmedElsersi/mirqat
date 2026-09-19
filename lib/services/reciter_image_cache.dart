import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../data/models/reciter.dart';
import 'audio/audio_storage.dart';

/// Reciter portraits fetched once and kept on disk.
///
/// A reciter who is not in `reciters.json` has no bundled portrait, and the
/// only picture of them is on the CDN. `Image.network` would fetch it again on
/// every cold start and show nothing at all offline, so it is written next to
/// the audio instead — one small file per reciter, fetched the first time they
/// are shown and read from disk forever after.
///
/// Every failure here is quiet by design (CLAUDE.md A.2 rule 3): no portrait
/// is a portrait's worth of loss, and `ReciterAvatar` already has an initial
/// to fall back to.
class ReciterImageCache {
  ReciterImageCache({required AudioStorage audioStorage, http.Client? client})
    : _storage = audioStorage,
      _client = client ?? http.Client();

  final AudioStorage _storage;
  final http.Client _client;

  /// In-flight and completed lookups, so a list of rows showing the same
  /// reciter fetches once rather than once per row.
  final Map<String, Future<File?>> _lookups = <String, Future<File?>>{};

  static const String directoryName = 'images';

  /// The portrait for [reciter], or null when there is nothing to fetch, no
  /// storage to keep it in, or the fetch failed.
  Future<File?> imageFor(Reciter reciter) {
    final String? url = reciter.imageUrl;
    if (url == null || url.isEmpty) return Future<File?>.value();
    return _lookups[reciter.id] ??= _fetch(reciter.id, url);
  }

  Future<File?> _fetch(String reciterId, String url) async {
    await _storage.prepare();
    final Directory? root = _storage.root;
    if (root == null) return null;

    final File file = File(
      p.join(root.path, directoryName, '$reciterId${_extensionOf(url)}'),
    );
    if (file.existsSync() && file.lengthSync() > 0) return file;

    try {
      final http.Response response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;

      file.parent.createSync(recursive: true);
      // Written beside the final name and renamed, so a half-written portrait
      // is never mistaken for a cached one on the next start.
      final File staging = File('${file.path}.part');
      staging.writeAsBytesSync(response.bodyBytes, flush: true);
      staging.renameSync(file.path);
      return file;
    } on Object {
      // Offline, timed out, or not an image: the initial stands in.
      return null;
    }
  }

  /// The url's extension, defaulting to `.jpg` — the file name only has to be
  /// stable, not descriptive.
  static String _extensionOf(String url) {
    final String extension = p.extension(Uri.parse(url).path);
    return extension.isEmpty || extension.length > 5 ? '.jpg' : extension;
  }

  void close() => _client.close();
}
