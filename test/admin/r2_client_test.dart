import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:mirqat/core/error/exceptions.dart';

const AdminConfig config = AdminConfig(
  accountId: 'acc',
  accessKey: 'AKIAIOSFODNN7EXAMPLE',
  secretKey: 'wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY',
  bucket: 'iqra-cdn',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
);

void main() {
  test('object keys match the manifest templates, padded to three digits', () {
    expect(
      config.audioKey(reciterId: 'shaheen', surah: 2, ayah: 0),
      'audio/shaheen/64/002000.mp3',
    );
    expect(
      config.audioKey(reciterId: 'shaheen', surah: 114, ayah: 6),
      'audio/shaheen/64/114006.mp3',
    );
    expect(
      config.packKey(reciterId: 'shaheen', surah: 1),
      'packs/shaheen/64/001.zip',
    );
    expect(
      config.publicUrlFor('audio/shaheen/64/002000.mp3').toString(),
      'https://pub-example.r2.dev/audio/shaheen/64/002000.mp3',
    );
  });

  test(
    'a PUT is signed with SigV4 over the bucket path and the body hash',
    () async {
      late http.Request captured;
      final R2Client client = R2Client(
        adminConfig: config,
        client: MockClient((http.Request request) async {
          captured = request;
          return http.Response('', request.method == 'HEAD' ? 404 : 200);
        }),
      );

      final UploadResult result = await client.putObject(
        key: 'audio/shaheen/64/001001.mp3',
        bytes: utf8.encode('mp3'),
        contentType: 'audio/mpeg',
      );

      expect(
        captured.url.toString(),
        'https://acc.r2.cloudflarestorage.com/iqra-cdn/audio/shaheen/64/001001.mp3',
      );
      final String auth = captured.headers['authorization']!;
      expect(
        auth,
        startsWith('AWS4-HMAC-SHA256 Credential=${config.accessKey}/'),
      );
      expect(auth, contains('/auto/s3/aws4_request'));
      // The signed headers, and the body hash the CDN will check the payload
      // against.
      expect(
        auth,
        contains(
          'SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date',
        ),
      );
      expect(
        captured.headers['x-amz-content-sha256'],
        sha256.convert(utf8.encode('mp3')).toString(),
      );
      expect(result.url.toString(), endsWith('/audio/shaheen/64/001001.mp3'));
      expect(result.outcome, UploadOutcome.uploaded);
    },
  );

  test('a path already holding the same bytes is left alone, so a '
      'half-finished publish can simply be re-run', () async {
    final List<int> bytes = utf8.encode('the same mp3');
    final List<String> methods = <String>[];
    final R2Client client = R2Client(
      adminConfig: config,
      client: MockClient((http.Request request) async {
        methods.add(request.method);
        return http.Response(
          '',
          200,
          headers: <String, String>{
            'content-length': '${bytes.length}',
            'etag': '"${md5.convert(bytes).toString()}"',
          },
        );
      }),
    );

    final UploadResult result = await client.putObject(
      key: 'audio/a/64/001001.mp3',
      bytes: bytes,
    );

    expect(result.outcome, UploadOutcome.unchanged);
    expect(methods, <String>['HEAD'], reason: 'nothing was re-sent');
  });

  test('a path holding different audio is refused, not overwritten', () async {
    final List<String> methods = <String>[];
    final R2Client client = R2Client(
      adminConfig: config,
      client: MockClient((http.Request request) async {
        methods.add(request.method);
        return http.Response(
          '',
          200,
          headers: <String, String>{
            'content-length': '4096',
            'etag':
                '"${md5.convert(utf8.encode('something else')).toString()}"',
          },
        );
      }),
    );

    // A published ayah is something people have already downloaded; the fix
    // for a bad take is a new path and a version bump, never a silent
    // replacement.
    await expectLater(
      () => client.putObject(key: 'audio/a/64/001001.mp3', bytes: <int>[1]),
      throwsA(
        isA<UploadException>().having(
          (UploadException e) => e.message,
          'message',
          allOf(contains('different audio'), contains('version')),
        ),
      ),
    );
    expect(methods, <String>['HEAD'], reason: 'nothing was written');
  });

  test('an explicit replace skips the existence check', () async {
    final List<String> methods = <String>[];
    final R2Client client = R2Client(
      adminConfig: config,
      client: MockClient((http.Request request) async {
        methods.add(request.method);
        return http.Response('', 200);
      }),
    );

    await client.putObject(
      key: 'audio/a/64/001001.mp3',
      bytes: <int>[1],
      replace: true,
    );

    expect(methods, <String>['PUT']);
  });

  test('a failed PUT is reported with its status, not swallowed', () async {
    final R2Client client = R2Client(
      adminConfig: config,
      client: MockClient(
        (http.Request request) async =>
            http.Response('nope', request.method == 'HEAD' ? 404 : 403),
      ),
    );

    await expectLater(
      () => client.putObject(key: 'audio/a/64/001001.mp3', bytes: <int>[1]),
      throwsA(isA<UploadException>()),
    );
  });

  test('the client offers no way to delete anything', () {
    // The R2 token is read/write, and the tool is not allowed to issue a
    // delete even if the token were widened. This is a source-level check
    // because the absence of a method is exactly what has to be kept.
    final String source = File(
      'lib/admin/services/r2_client.dart',
    ).readAsStringSync();

    expect(source.contains("'DELETE'"), isFalse);
    expect(source.contains('deleteObject'), isFalse);
    expect(RegExp(r'\bdelete\w*\s*\(').hasMatch(source), isFalse);
  });
}
