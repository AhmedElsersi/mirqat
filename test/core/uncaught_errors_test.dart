import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `main` runs inside a guarded zone so that a connection lost inside
/// just_audio's own fetch is not reported as a crash. These pin the shape of
/// that decision, which is easy to widen by accident into "swallow
/// everything".
void main() {
  final String source = File('lib/main.dart').readAsStringSync();

  test('main runs inside a guarded zone', () {
    expect(source, contains('runZonedGuarded(_run, _onUncaught)'));
  });

  test('only network failures are quieted', () {
    // A zone handler with no type check swallows real faults silently, which
    // is worse than the crash it was added to hide.
    expect(source, contains('error is SocketException'));
    expect(source, contains('error is HttpException'));
    expect(source, contains('error is TlsException'));
  });

  test('everything else still reaches Flutter\'s reporter', () {
    expect(source, contains('FlutterError.reportError'));
  });

  test('nothing is sent anywhere — A.2 rule 3 allows no crash reporting', () {
    for (final String forbidden in <String>[
      'Sentry',
      'FirebaseCrashlytics',
      'Crashlytics',
      'http.post',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}
