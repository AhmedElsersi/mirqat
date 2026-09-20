// ignore_for_file: experimental_member_use
//
// PlayerException is just_audio's, and naming it is the point: these tests
// pin what the listener is told when the platform refuses a source.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/session/cubit/session_state.dart';

void main() {
  group('SessionCubit.classifyFailure', () {
    test('a source that had to be fetched blames the network', () {
      expect(
        SessionCubit.classifyFailure(
          PlayerException(0, 'Source error', null),
          streamsAnyAyah: true,
        ),
        SessionFailure.audioUnreachable,
      );
    });

    test('a queue already on the device does not blame the network', () {
      // Sending someone to check their connection when every clip is on disk
      // sends them after the wrong thing.
      expect(
        SessionCubit.classifyFailure(
          PlayerException(0, 'Source error', null),
          streamsAnyAyah: false,
        ),
        SessionFailure.unknown,
      );
    });

    test('a catalog fault stays a catalog fault even while streaming', () {
      expect(
        SessionCubit.classifyFailure(
          const SessionConfigException('no timings'),
          streamsAnyAyah: true,
        ),
        SessionFailure.configuration,
      );
    });

    test('a socket failure mid-session reads as unreachable audio', () {
      expect(
        SessionCubit.classifyFailure(
          const SocketishError(),
          streamsAnyAyah: true,
        ),
        SessionFailure.audioUnreachable,
      );
    });
  });

  group('every failure has a sentence in both locales', () {
    // The whole point of SessionFailure is that no listener ever reads
    // "Source error (0)" again, so a kind with no Arabic line is the bug
    // this file exists to catch.
    const Map<SessionFailure, String> keys = <SessionFailure, String>{
      SessionFailure.audioUnreachable: 'error_offline',
      SessionFailure.configuration: 'error_config',
      SessionFailure.unknown: 'error_unknown',
    };

    test('the map covers the enum', () {
      expect(keys.keys, containsAll(SessionFailure.values));
    });

    for (final String locale in <String>['ar', 'en']) {
      test(locale, () {
        final Map<String, dynamic> player =
            (jsonDecode(
                      File(
                        'assets/translations/$locale.json',
                      ).readAsStringSync(),
                    )
                    as Map<String, dynamic>)['player']
                as Map<String, dynamic>;

        for (final String key in keys.values) {
          expect(player[key], isA<String>(), reason: 'player.$key missing');
          expect((player[key] as String).trim(), isNotEmpty);
        }
      });
    }

    test('the Arabic lines are Arabic', () {
      // An English fallback left in ar.json is the quiet way this regresses.
      final Map<String, dynamic> player =
          (jsonDecode(File('assets/translations/ar.json').readAsStringSync())
                  as Map<String, dynamic>)['player']
              as Map<String, dynamic>;

      for (final String key in keys.values) {
        expect(
          (player[key] as String).runes.any(
            (int r) => r >= 0x0600 && r <= 0x06FF,
          ),
          isTrue,
          reason: 'player.$key is not written in Arabic',
        );
      }
    });
  });
}

/// Stands in for the `SocketException` just_audio's fetch raises: the test
/// must not need a real socket to assert on how the error is read.
class SocketishError implements Exception {
  const SocketishError();
}
