import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/app_info.dart';
import 'package:mirqat/services/update_policy.dart';

const String kStore = 'https://play.google.com/store/apps/details?id=x';

UpdateKind decide(
  String installed, {
  String min = '',
  String latest = '',
  String storeUrl = kStore,
  DateTime? lastPrompted,
  DateTime? now,
}) => decideUpdate(
  installed: installed,
  rules: PlatformUpdate(min: min, latest: latest, storeUrl: storeUrl),
  lastPrompted: lastPrompted,
  now: now ?? DateTime(2026, 9, 20, 12),
);

void main() {
  group('versions', () {
    test('are compared number by number, not letter by letter', () {
      AppVersion v(String s) => AppVersion.tryParse(s)!;
      expect(v('1.9.0') < v('1.10.0'), isTrue);
      expect(v('2.0.0') < v('1.99.99'), isFalse);
      expect(v('1.2') < v('1.2.1'), isTrue);
      expect(v('1.2').compareTo(v('1.2.0')), 0);
    });

    test('ignore a build number or a pre-release tag', () {
      expect(AppVersion.tryParse('1.4.0+17'), AppVersion.tryParse('1.4.0'));
      expect(AppVersion.tryParse('1.4.0-beta'), AppVersion.tryParse('1.4.0'));
    });

    test('that are not versions are not read as one', () {
      for (final String bad in <String>[
        '',
        '  ',
        'latest',
        '1.x',
        '1..2',
        '-1',
      ]) {
        expect(AppVersion.tryParse(bad), isNull, reason: '"$bad"');
      }
      expect(AppVersion.tryParse(null), isNull);
    });
  });

  group('what to say', () {
    test('nothing, when no rule is published', () {
      expect(decide('1.0.0'), UpdateKind.none);
    });

    test('below the minimum: the update is required', () {
      expect(
        decide('1.0.0', min: '1.2.0', latest: '1.5.0'),
        UpdateKind.required,
      );
    });

    test('at the minimum, below the latest: the update is mentioned', () {
      expect(
        decide('1.2.0', min: '1.2.0', latest: '1.5.0'),
        UpdateKind.optional,
      );
    });

    test('at or past the latest: nothing', () {
      expect(decide('1.5.0', min: '1.2.0', latest: '1.5.0'), UpdateKind.none);
      // A build ahead of the store — a tester's, a reviewer's.
      expect(decide('1.6.0', min: '1.2.0', latest: '1.5.0'), UpdateKind.none);
    });
  });

  group('an optional update is not nagged about', () {
    final DateTime now = DateTime(2026, 9, 20, 12);

    test('mentioned within the last day: not again', () {
      expect(
        decide(
          '1.0.0',
          latest: '1.1.0',
          now: now,
          lastPrompted: now.subtract(const Duration(hours: 23)),
        ),
        UpdateKind.none,
      );
    });

    test('a day on: mentioned again', () {
      expect(
        decide(
          '1.0.0',
          latest: '1.1.0',
          now: now,
          lastPrompted: now.subtract(const Duration(hours: 25)),
        ),
        UpdateKind.optional,
      );
    });

    test('a clock set back does not silence it for ever', () {
      // "Last mentioned" a year in the future is further than a day away.
      expect(
        decide(
          '1.0.0',
          latest: '1.1.0',
          now: now,
          lastPrompted: now.add(const Duration(days: 365)),
        ),
        UpdateKind.optional,
      );
    });

    test('a required update is never put off by "later"', () {
      expect(
        decide('1.0.0', min: '1.1.0', now: now, lastPrompted: now),
        UpdateKind.required,
      );
    });
  });

  group('every doubt is resolved towards saying nothing', () {
    test('no store page: no prompt, and above all no blocking one', () {
      // A required update with no way to get it would lock people out.
      expect(decide('1.0.0', min: '9.0.0', storeUrl: ''), UpdateKind.none);
      expect(decide('1.0.0', latest: '9.0.0', storeUrl: '  '), UpdateKind.none);
    });

    test('a typo in the published minimum cannot stop the app', () {
      for (final String typo in <String>['1.o.0', 'v2', 'two', '2,0,0']) {
        expect(decide('1.0.0', min: typo), UpdateKind.none, reason: typo);
      }
    });

    test('an installed version that cannot be read: nothing', () {
      expect(decide('', min: '9.0.0'), UpdateKind.none);
      expect(decide('dev', min: '9.0.0'), UpdateKind.none);
    });

    test('a bad minimum does not hide a good latest', () {
      expect(
        decide('1.0.0', min: 'oops', latest: '1.1.0'),
        UpdateKind.optional,
      );
    });
  });

  group('a release is a version and a build', () {
    UpdateKind decideBuild(
      String installed,
      String build, {
      String min = '',
      int? minBuild,
      String latest = '',
      int? latestBuild,
      bool force = false,
    }) => decideUpdate(
      installed: installed,
      installedBuild: build,
      rules: PlatformUpdate(
        min: min,
        minBuild: minBuild,
        latest: latest,
        latestBuild: latestBuild,
        force: force,
        storeUrl: kStore,
      ),
      lastPrompted: null,
      now: DateTime(2026, 9, 20, 12),
    );

    test('versions decide first; the build only tells two uploads of one '
        'version apart', () {
      expect(
        decideBuild('1.2.0', '24', min: '1.2.0', minBuild: 25),
        UpdateKind.required,
      );
      expect(
        decideBuild('1.2.0', '25', min: '1.2.0', minBuild: 25),
        UpdateKind.none,
      );
      expect(
        decideBuild('1.3.0', '1', min: '1.2.0', minBuild: 25),
        UpdateKind.none,
        reason: 'a newer version, whatever its build',
      );
      expect(
        decideBuild('1.2.0', '24', latest: '1.2.0', latestBuild: 25),
        UpdateKind.optional,
      );
    });

    test('an install whose build is unknown compares by version alone', () {
      expect(
        decideBuild('1.2.0', '', min: '1.2.0', minBuild: 25),
        UpdateKind.none,
      );
      expect(
        decideBuild('1.2.0', 'x', min: '1.2.0', minBuild: 25),
        UpdateKind.none,
      );
    });

    test('a forced latest is required, with no "later"', () {
      expect(
        decideBuild('1.2.0', '1', latest: '1.3.0', force: true),
        UpdateKind.required,
      );
      expect(
        decideUpdate(
          installed: '1.2.0',
          rules: const PlatformUpdate(
            latest: '1.3.0',
            force: true,
            storeUrl: kStore,
          ),
          lastPrompted: DateTime(2026, 9, 20, 11),
          now: DateTime(2026, 9, 20, 12),
        ),
        UpdateKind.required,
        reason: '"later" an hour ago does not silence a forced update',
      );
      expect(
        decideBuild('1.3.0', '1', latest: '1.3.0', force: true),
        UpdateKind.none,
        reason: 'at the latest there is nothing to force',
      );
    });

    test('"later" holds for as long as the rules say', () {
      UpdateKind after(Duration ago, Duration remindAfter) => decideUpdate(
        installed: '1.0.0',
        rules: const PlatformUpdate(latest: '1.1.0', storeUrl: kStore),
        lastPrompted: DateTime(2026, 9, 20, 12).subtract(ago),
        now: DateTime(2026, 9, 20, 12),
        remindAfter: remindAfter,
      );
      expect(
        after(const Duration(days: 2), const Duration(days: 7)),
        UpdateKind.none,
      );
      expect(
        after(const Duration(days: 8), const Duration(days: 7)),
        UpdateKind.optional,
      );
    });
  });

  group('the closed sign', () {
    test('is up for the platforms it names, or all, until its time', () {
      const Maintenance all = Maintenance(enabled: true);
      final DateTime now = DateTime.utc(2026, 9, 29, 12);
      expect(all.isActive(platform: 'android', now: now), isTrue);
      expect(all.isActive(platform: 'windows', now: now), isTrue);

      const Maintenance iosOnly = Maintenance(
        enabled: true,
        platforms: <String>{'ios'},
      );
      expect(iosOnly.isActive(platform: 'ios', now: now), isTrue);
      expect(iosOnly.isActive(platform: 'android', now: now), isFalse);

      final Maintenance timed = Maintenance(
        enabled: true,
        until: DateTime.utc(2026, 9, 29, 14),
      );
      expect(timed.isActive(platform: 'android', now: now), isTrue);
      expect(
        timed.isActive(platform: 'android', now: DateTime.utc(2026, 9, 29, 14)),
        isFalse,
        reason: 'comes down by itself at "until"',
      );
      expect(Maintenance.off.isActive(platform: 'android', now: now), isFalse);
    });
  });
}
