import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../core/error/exceptions.dart';
import '../config/admin_config.dart';

/// Uploads objects to Cloudflare R2, over its S3-compatible API.
///
/// **There is no delete here, and there must never be one.** The token this
/// tool is given is read/write, not delete, and the rule behind that is
/// editorial rather than technical: a published ayah is something people have
/// already downloaded, and replacing it under the same path would hand two
/// different recordings the same name. A recording that turns out wrong is
/// fixed by publishing a new path and bumping the reciter's `version`, which
/// is what marks existing installs stale (CLAUDE.md A.5).
///
/// Signing is SigV4 by hand: `crypto` and `http` are already on the approved
/// list, and an S3 SDK is not (CLAUDE.md A.4).
/// What the bucket already holds at a key.
class R2Object {
  const R2Object({required this.length, required this.etag});

  final int length;

  /// MD5 of the stored bytes for a single-part upload, unquoted.
  final String etag;
}

/// Whether a publish wrote anything.
enum UploadOutcome {
  uploaded,

  /// The same bytes were already there, so nothing was written.
  unchanged,
}

class UploadResult {
  const UploadResult({required this.url, required this.outcome});

  final Uri url;
  final UploadOutcome outcome;
}

class R2Client {
  R2Client({required AdminConfig adminConfig, http.Client? client})
    : _config = adminConfig,
      _client = client ?? http.Client();

  final AdminConfig _config;
  final http.Client _client;

  /// R2 ignores the region but SigV4 does not, and `auto` is what Cloudflare
  /// documents.
  static const String region = 'auto';
  static const String service = 's3';

  /// What is already at [key], or null when nothing is.
  ///
  /// Used to refuse a re-publish rather than to overwrite one: a path that is
  /// already there is a version bump waiting to happen.
  Future<R2Object?> head(String key) async {
    final http.Response response = await _retrying(
      () => _send('HEAD', key, const <int>[]),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw UploadException(key, 'HEAD returned ${response.statusCode}.');
    }
    return R2Object(
      length: int.tryParse(response.headers['content-length'] ?? '') ?? 0,
      // R2 returns the MD5 of a single-part upload as its ETag, quoted.
      etag: (response.headers['etag'] ?? '').replaceAll('"', ''),
    );
  }

  /// Uploads [bytes] to [key].
  ///
  /// Three outcomes, and the middle one is the point: a key that already holds
  /// **these same bytes** is left alone and reported as
  /// [UploadOutcome.unchanged]. Re-running a publish that half-finished — the
  /// ayahs went up, the pack did not — must not be a dead end, and re-sending
  /// bytes that are already there changes nothing anyone has downloaded.
  ///
  /// A key holding *different* bytes is refused: that is a new recording under
  /// an old name, which is what the version bump exists for.
  Future<UploadResult> putObject({
    required String key,
    required List<int> bytes,
    String contentType = 'application/octet-stream',
    bool replace = false,
  }) async {
    if (!replace) {
      final R2Object? existing = await head(key);
      if (existing != null) {
        if (existing.etag.isNotEmpty &&
            existing.etag == md5.convert(bytes).toString()) {
          return UploadResult(
            url: _config.publicUrlFor(key),
            outcome: UploadOutcome.unchanged,
          );
        }
        throw UploadException(
          key,
          'That path already holds different audio (${existing.length} '
          'bytes). Publish a new path and bump the reciter version instead of '
          'replacing it.',
        );
      }
    }

    final http.Response response = await _retrying(
      () => _send('PUT', key, bytes, contentType: contentType),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw UploadException(
        key,
        'PUT returned ${response.statusCode}: ${response.body}',
      );
    }
    return UploadResult(
      url: _config.publicUrlFor(key),
      outcome: UploadOutcome.uploaded,
    );
  }

  /// Uploads a file's contents. The file is read in one go: an ayah is a few
  /// hundred kilobytes and a pack a few tens of megabytes, both well inside
  /// what a Mac can hold while it signs them.
  Future<UploadResult> putFile({
    required String key,
    required File file,
    String contentType = 'audio/mpeg',
    bool replace = false,
  }) => putObject(
    key: key,
    bytes: file.readAsBytesSync(),
    contentType: contentType,
    replace: replace,
  );

  Future<http.Response> _send(
    String method,
    String key,
    List<int> body, {
    String contentType = 'application/octet-stream',
  }) async {
    final Uri endpoint = Uri.parse(_config.endpoint);
    final Uri url = endpoint.replace(path: '/${_config.bucket}/$key');

    final DateTime now = DateTime.now().toUtc();
    final String amzDate = _amzDate(now);
    final String dateStamp = amzDate.substring(0, 8);
    final String payloadHash = sha256.convert(body).toString();

    final Map<String, String> headers = <String, String>{
      'host': url.host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      if (method == 'PUT') 'content-type': contentType,
    };

    final String signedHeaders = (headers.keys.toList()..sort()).join(';');
    final String canonicalHeaders = (headers.keys.toList()..sort())
        .map((String k) => '$k:${headers[k]!.trim()}\n')
        .join();

    final String canonicalRequest = <String>[
      method,
      _canonicalPath(url.path),
      '',
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');

    final String scope = '$dateStamp/$region/$service/aws4_request';
    final String stringToSign = <String>[
      'AWS4-HMAC-SHA256',
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    final List<int> signingKey = _signingKey(dateStamp);
    final String signature = Hmac(
      sha256,
      signingKey,
    ).convert(utf8.encode(stringToSign)).toString();

    final http.Request request = http.Request(method, url)
      ..headers.addAll(<String, String>{
        ...headers,
        'authorization':
            'AWS4-HMAC-SHA256 '
            'Credential=${_config.accessKey}/$scope, '
            'SignedHeaders=$signedHeaders, '
            'Signature=$signature',
      })
      ..bodyBytes = Uint8List.fromList(body);

    return http.Response.fromStream(await _client.send(request));
  }

  /// Retries a request that failed for a reason the network chose.
  ///
  /// A publish is hundreds of uploads over tens of minutes, and a reset
  /// connection partway through used to end the whole run — surah 21 uploaded
  /// all 113 of its ayahs and then lost the pack to one dropped socket. These
  /// are transport failures, not answers: the request never reached a verdict,
  /// so asking again is the correct response, not a workaround. A request that
  /// arrives and is refused still fails immediately, because retrying a 403
  /// only wastes time.
  ///
  /// Uploads are safe to repeat: the same key with the same bytes is the same
  /// object, so a PUT whose response was lost costs nothing to send again.
  Future<T> _retrying<T>(Future<T> Function() attempt) async {
    const int attempts = 4;
    for (int i = 1; ; i++) {
      try {
        return await attempt();
      } on http.ClientException catch (_) {
        if (i >= attempts) rethrow;
      } on SocketException catch (_) {
        if (i >= attempts) rethrow;
      } on TlsException catch (_) {
        if (i >= attempts) rethrow;
      }
      await Future<void>.delayed(Duration(seconds: 2 * i));
    }
  }

  /// The four-step derived key. Split out so a test can pin it against AWS's
  /// published vector — a signature that is wrong by one step fails with the
  /// same opaque 403 as a wrong secret.
  List<int> _signingKey(String dateStamp) {
    List<int> hmac(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;

    final List<int> kDate = hmac(
      utf8.encode('AWS4${_config.secretKey}'),
      dateStamp,
    );
    final List<int> kRegion = hmac(kDate, region);
    final List<int> kService = hmac(kRegion, service);
    return hmac(kService, 'aws4_request');
  }

  /// Every path segment percent-encoded the way SigV4 wants, and `/` left
  /// alone.
  static String _canonicalPath(String path) => path
      .split('/')
      .map((String segment) => Uri.encodeComponent(segment))
      .join('/');

  static String _amzDate(DateTime utc) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${utc.year}${two(utc.month)}${two(utc.day)}T'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  void close() => _client.close();
}
