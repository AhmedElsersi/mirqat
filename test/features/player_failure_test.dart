// ignore_for_file: experimental_member_use
//
// PlayerException is just_audio's, and naming it is the point: these tests
// pin what the listener is told when the platform refuses a source.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/exceptions.dart';
import 'package:mirqat/features/player/cubit/player_cubit.dart';
import 'package:mirqat/features/player/cubit/player_state.dart';

void main() {
  group('PlayerCubit.classifyFailure', () {
    test('a source that had to be fetched blames the network', () {
      expect(
        PlayerCubit.classifyFailure(
          PlayerException(0, 'Source error', null),
          streamsAnyAyah: true,
        ),
        PlayerFailure.audioUnreachable,
      );
    });

    test('a queue already on the device does not blame the network', () {
      // Sending someone to check their connection when every clip is on disk
      // sends them after the wrong thing.
      expect(
        PlayerCubit.classifyFailure(
          PlayerException(0, 'Source error', null),
          streamsAnyAyah: false,
        ),
        PlayerFailure.unknown,
      );
    });

    test('a catalog fault stays a catalog fault even while streaming', () {
      expect(
        PlayerCubit.classifyFailure(
          const SessionConfigException('no timings'),
          streamsAnyAyah: true,
        ),
        PlayerFailure.configuration,
      );
    });

    test('a socket failure mid-session reads as unreachable audio', () {
      expect(
        PlayerCubit.classifyFailure(
          const SocketishError(),
          streamsAnyAyah: true,
        ),
        PlayerFailure.audioUnreachable,
      );
    });
  });

  group('every failure has a sentence in both locales', () {
    // The whole point of PlayerFailure is that no listener ever reads
    // "Source error (0)" again, so a kind with no Arabic line is the bug
    // this file exists to catch.
    const Map<PlayerFailure, String> keys = <PlayerFailure, String>{
      PlayerFailure.audioUnreachable: 'error_offline',
      PlayerFailure.configuration: 'error_config',
      PlayerFailure.unknown: 'error_unknown',
    };

    test('the map covers the enum', () {
      expect(keys.keys, containsAll(PlayerFailure.values));
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
