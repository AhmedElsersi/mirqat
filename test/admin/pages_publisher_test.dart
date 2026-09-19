import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/services/pages_publisher.dart';
import 'package:mirqat/core/error/exceptions.dart';

const AdminConfig configured = AdminConfig(
  accountId: 'acc',
  accessKey: 'key',
  secretKey: 'secret',
  bucket: 'iqra-audio',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
  githubToken: 'ghp_example',
  githubRepo: 'someone/iqra-cdn',
);

const AdminConfig unconfigured = AdminConfig(
  accountId: 'acc',
  accessKey: 'key',
  secretKey: 'secret',
  bucket: 'iqra-audio',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
);

Map<String, dynamic> manifestWith(int reciters, int surahs) =>
    <String, dynamic>{
      'schemaVersion': 1,
      'baseUrl': 'https://pub-example.r2.dev',
      'reciters': <Map<String, dynamic>>[
        for (int i = 0; i < reciters; i++)
          <String, dynamic>{
            'id': 'r$i',
            'surahs': <Map<String, dynamic>>[
              for (int s = 0; s < surahs; s++) <String, dynamic>{'n': s + 1},
            ],
          },
      ],
    };

void main() {
  test('a manifest is committed over the one already there', () async {
    final List<http.Request> sent = <http.Request>[];
    final PagesPublisher publisher = PagesPublisher(
      adminConfig: configured,
      client: MockClient((http.Request request) async {
        sent.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode(<String, String>{'sha': 'abc123'}),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'commit': <String, String>{'sha': 'def4567890'},
          }),
          200,
        );
      }),
    );

    final String commit = await publisher.publish(manifestWith(2, 3));

    expect(commit, 'def4567890');
    final http.Request put = sent.last;
    expect(put.method, 'PUT');
    expect(
      put.url.toString(),
      'https://api.github.com/repos/someone/iqra-cdn/contents/manifest.json',
    );

    final Map<String, dynamic> body =
        jsonDecode(put.body) as Map<String, dynamic>;
    // The sha of what is being replaced: GitHub refuses a blind overwrite,
    // which is what stops two operators clobbering each other.
    expect(body['sha'], 'abc123');
    expect(body['message'], contains('2 reciter(s)'));
    expect(body['message'], contains('6 surah(s)'));
    expect(
      jsonDecode(utf8.decode(base64Decode(body['content'] as String))),
      manifestWith(2, 3),
    );
  });

  test('the first publish carries no sha', () async {
    late http.Request put;
    final PagesPublisher publisher = PagesPublisher(
      adminConfig: configured,
      client: MockClient((http.Request request) async {
        if (request.method == 'GET') return http.Response('', 404);
        put = request;
        return http.Response('{}', 201);
      }),
    );

    await publisher.publish(manifestWith(1, 1));

    expect(
      (jsonDecode(put.body) as Map<String, dynamic>).containsKey('sha'),
      isFalse,
    );
  });

  test('the token never appears in what is reported', () async {
    final PagesPublisher publisher = PagesPublisher(
      adminConfig: configured,
      client: MockClient(
        (http.Request request) async => request.method == 'GET'
            ? http.Response('', 404)
            : http.Response(
                jsonEncode(<String, String>{'message': 'Bad credentials'}),
                401,
              ),
      ),
    );

    await expectLater(
      () => publisher.publish(manifestWith(1, 1)),
      throwsA(
        isA<UploadException>()
            .having(
              (UploadException e) => e.message,
              'message',
              contains('401'),
            )
            .having(
              (UploadException e) => e.message,
              'message',
              isNot(contains('ghp_example')),
            ),
      ),
    );
  });

  test(
    'a build with no token refuses clearly rather than half-publishing',
    () async {
      final PagesPublisher publisher = PagesPublisher(
        adminConfig: unconfigured,
        client: MockClient((_) async => fail('nothing should be sent')),
      );

      expect(unconfigured.canPublishManifest, isFalse);
      await expectLater(
        () => publisher.publish(manifestWith(1, 1)),
        throwsA(
          isA<UploadException>().having(
            (UploadException e) => e.message,
            'message',
            allOf(contains('GITHUB_TOKEN'), contains('by hand')),
          ),
        ),
      );
    },
  );
}
