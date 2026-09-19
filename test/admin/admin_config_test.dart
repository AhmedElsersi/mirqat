import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/config/admin_config.dart';

void main() {
  test('a build with no --dart-defines refuses to start, and says which keys '
      'are missing', () {
    // `flutter test` passes none of them, which is exactly the shape of a
    // build that forgot run_admin.sh.
    final List<String> missing = AdminConfig.missingKeys;

    expect(missing, <String>[
      'R2_ACCOUNT_ID',
      'R2_ACCESS_KEY',
      'R2_SECRET_KEY',
      'R2_BUCKET',
      'R2_ENDPOINT',
      'R2_PUBLIC_BASE',
      'AUDIO_BITRATE',
    ]);

    final String message = AdminConfig.missingMessage(missing);
    expect(message, contains('cannot start'));
    expect(message, contains('run_admin.sh'));
    expect(message, contains('never commit'));
    // And it never suggests a value: a guessed bucket is an upload into
    // someone else's namespace.
    expect(message, isNot(contains('r2.cloudflarestorage.com/')));
  });

  test('the message names one key in the singular', () {
    expect(
      AdminConfig.missingMessage(<String>['R2_BUCKET']),
      contains('R2_BUCKET is missing'),
    );
    expect(
      AdminConfig.missingMessage(<String>['R2_BUCKET', 'R2_ENDPOINT']),
      contains('R2_BUCKET, R2_ENDPOINT are missing'),
    );
  });

  test('a public base with or without a trailing slash resolves the same', () {
    const AdminConfig withSlash = AdminConfig(
      accountId: 'a',
      accessKey: 'k',
      secretKey: 's',
      bucket: 'b',
      endpoint: 'https://a.r2.cloudflarestorage.com',
      publicBase: 'https://pub-example.r2.dev/',
      bitrate: 64,
    );
    const AdminConfig withoutSlash = AdminConfig(
      accountId: 'a',
      accessKey: 'k',
      secretKey: 's',
      bucket: 'b',
      endpoint: 'https://a.r2.cloudflarestorage.com',
      publicBase: 'https://pub-example.r2.dev',
      bitrate: 64,
    );

    expect(
      withSlash.publicUrlFor('audio/a/64/001001.mp3').toString(),
      withoutSlash.publicUrlFor('audio/a/64/001001.mp3').toString(),
    );
  });
}
