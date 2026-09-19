import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/error/exceptions.dart';
import '../config/admin_config.dart';

/// Publishes the manifest to the GitHub Pages site the app reads it from.
///
/// This is the step that makes a reciter or a surah appear without an app
/// release. The audio lives in R2; the manifest that names it lives here, in a
/// repo holding nothing else, and the app fetches it on every launch
/// (CLAUDE.md A.5).
///
/// The token never leaves this class — not into a log line, not into the
/// on-screen log, not into an error message.
class PagesPublisher {
  PagesPublisher({required AdminConfig adminConfig, http.Client? client})
    : _config = adminConfig,
      _client = client ?? http.Client();

  final AdminConfig _config;
  final http.Client _client;

  static const String _api = 'https://api.github.com';

  /// Commits [manifest] over whatever is there, and answers the commit sha.
  ///
  /// An overwrite, deliberately: the manifest is one file describing the whole
  /// CDN, and it is rebuilt from the published one every time — so what is
  /// written already contains everything that was there.
  Future<String> publish(Map<String, dynamic> manifest) async {
    if (!_config.canPublishManifest) {
      throw const UploadException(
        'manifest.json',
        'No GitHub token or repo is configured, so the manifest cannot be '
            'published from here. Add GITHUB_TOKEN and GITHUB_REPO to '
            'admin.env, or publish the written file by hand.',
      );
    }

    final Uri url = Uri.parse(
      '$_api/repos/${_config.githubRepo}/contents/${_config.manifestPath}',
    );
    final String body =
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';

    final http.Response result = await _client.put(
      url,
      headers: _headers,
      body: jsonEncode(<String, Object?>{
        'message': _messageFor(manifest),
        'content': base64Encode(utf8.encode(body)),
        // Absent on the first publish, required after: GitHub refuses a blind
        // overwrite, which is what stops two operators clobbering each other.
        if (await _currentSha() case final String sha) 'sha': sha,
      }),
    );

    if (result.statusCode != 200 && result.statusCode != 201) {
      throw UploadException(
        _config.manifestPath,
        'GitHub returned ${result.statusCode}. '
        '${_reasonFrom(result.body)}',
      );
    }

    final Object? decoded = jsonDecode(result.body);
    return decoded is Map<String, dynamic>
        ? '${(decoded['commit'] as Map<String, dynamic>?)?['sha'] ?? ''}'
        : '';
  }

  /// The sha of the file being replaced, or null when there is none yet.
  Future<String?> _currentSha() async {
    final http.Response response = await _client.get(
      Uri.parse(
        '$_api/repos/${_config.githubRepo}/contents/${_config.manifestPath}',
      ),
      headers: _headers,
    );
    if (response.statusCode != 200) return null;
    final Object? decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded['sha'] as String? : null;
  }

  Map<String, String> get _headers => <String, String>{
    'authorization': 'Bearer ${_config.githubToken}',
    'accept': 'application/vnd.github+json',
    'content-type': 'application/json',
    'user-agent': 'mirqat-admin',
  };

  /// A commit message that says what changed, read from the manifest itself.
  static String _messageFor(Map<String, dynamic> manifest) {
    final List<dynamic> reciters =
        manifest['reciters'] as List<dynamic>? ?? <dynamic>[];
    final int surahs = reciters.fold<int>(
      0,
      (int sum, dynamic r) =>
          sum +
          (((r as Map<String, dynamic>)['surahs'] as List<dynamic>?)?.length ??
              0),
    );
    return 'Publish manifest: ${reciters.length} reciter(s), $surahs surah(s)';
  }

  /// GitHub's own message, without echoing anything that could carry a token.
  static String _reasonFrom(String body) {
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } on FormatException {
      // Not JSON; say nothing rather than paste an HTML error page.
    }
    return '';
  }

  void close() => _client.close();
}
