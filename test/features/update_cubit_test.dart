import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/features/update/cubit/update_cubit.dart';
import 'package:mirqat/services/app_info_service.dart';
import 'package:mirqat/services/app_version_service.dart';
import 'package:mirqat/services/update_policy.dart';

class _Bundle implements AssetReader {
  const _Bundle(this.contents);

  final String contents;

  @override
  Future<String> loadString(String path) async => contents;
}

class _Version implements AppVersionService {
  _Version(this.version, {this.build = '1'});

  final String? version;
  final String build;

  @override
  Future<InstalledVersion?> read() async => version == null
      ? null
      : InstalledVersion(version: version!, buildNumber: build);
}

String rules({
  String androidMin = '',
  String androidLatest = '',
  String iosMin = '',
  String iosLatest = '',
  String notesAr = '',
}) => jsonEncode(<String, dynamic>{
  'schemaVersion': 1,
  'update': <String, dynamic>{
    'android': <String, String>{
      'min': androidMin,
      'latest': androidLatest,
      'storeUrl': 'https://play.example/app',
    },
    'ios': <String, String>{
      'min': iosMin,
      'latest': iosLatest,
      'storeUrl': 'https://apps.example/app',
    },
    'notes': <String, String>{'ar': notesAr, 'en': ''},
  },
});

void main() {
  /// A service whose bundled copy is [bundled] and whose network answers with
  /// [published], when given — after [UpdateCubit.check] has looked once.
  AppInfoService serviceWith(String bundled, {String? published}) {
    final AppInfoService s = AppInfoService(
      _Bundle(bundled),
      client: MockClient(
        (_) async => published == null
            ? http.Response('', 404)
            : http.Response.bytes(utf8.encode(published), 200),
      ),
      storageDirectory: () => throw UnsupportedError('no cache'),
    );
    addTearDown(s.dispose);
    return s;
  }

  UpdateCubit cubitFor(
    AppInfoService service, {
    String? installed = '1.0.0',
    String build = '1',
    TargetPlatform platform = TargetPlatform.android,
  }) {
    final UpdateCubit cubit = UpdateCubit(
      appInfoService: service,
      appVersionService: _Version(installed, build: build),
      platformOverride: platform,
      clock: () => DateTime(2026, 9, 20, 12),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  test(
    'each store is told apart: an iOS rule says nothing to Android',
    () async {
      final AppInfoService service = serviceWith(rules(iosMin: '2.0.0'));

      final UpdateCubit android = cubitFor(service);
      await android.check(lastPrompted: null);
      expect(android.state.kind, UpdateKind.none);

      final UpdateCubit ios = cubitFor(service, platform: TargetPlatform.iOS);
      await ios.check(lastPrompted: null);
      expect(ios.state.kind, UpdateKind.required);
      expect(ios.state.storeUrl, 'https://apps.example/app');
    },
  );

  test('the admin tool, on macOS, is never asked to update', () async {
    final UpdateCubit mac = cubitFor(
      serviceWith(rules(androidMin: '9.0.0', iosMin: '9.0.0')),
      platform: TargetPlatform.macOS,
    );
    await mac.check(lastPrompted: null);
    expect(mac.state.kind, UpdateKind.none);
  });

  test('carries the store page and what is new', () async {
    final UpdateCubit cubit = cubitFor(
      serviceWith(rules(androidLatest: '1.1.0', notesAr: 'سور جديدة')),
    );
    await cubit.check(lastPrompted: null);

    expect(cubit.state.kind, UpdateKind.optional);
    expect(cubit.state.storeUrl, 'https://play.example/app');
    expect(cubit.state.latest, '1.1.0');
    expect(cubit.state.notes.ar, 'سور جديدة');
  });

  test(
    '"later" puts an optional update away for the rest of the run',
    () async {
      final AppInfoService service = serviceWith(
        rules(androidLatest: '1.1.0'),
        published: rules(androidLatest: '1.2.0'),
      );
      final UpdateCubit cubit = cubitFor(service);
      await cubit.check(lastPrompted: null);
      cubit.dismiss();
      expect(cubit.state.kind, UpdateKind.none);

      // A newer app.json arriving does not bring it straight back.
      await service.refresh();
      await settle();
      expect(cubit.state.kind, UpdateKind.none);
    },
  );

  test('a rule published while the app is open is heard in that same run — '
      'and a required one overrides "later"', () async {
    final AppInfoService service = serviceWith(
      rules(androidLatest: '1.1.0'),
      published: rules(androidMin: '1.1.0', androidLatest: '1.1.0'),
    );
    final UpdateCubit cubit = cubitFor(service);
    await cubit.check(lastPrompted: null);
    cubit.dismiss();

    await service.refresh();
    await settle();
    expect(cubit.state.kind, UpdateKind.required);

    cubit.dismiss();
    expect(cubit.state.kind, UpdateKind.required, reason: 'cannot be put off');
  });

  test('mentioned earlier today: says nothing', () async {
    final UpdateCubit cubit = cubitFor(
      serviceWith(rules(androidLatest: '1.1.0')),
    );
    await cubit.check(lastPrompted: DateTime(2026, 9, 20, 8));
    expect(cubit.state.kind, UpdateKind.none);
  });

  test('a platform that will not give its version is left alone', () async {
    final UpdateCubit cubit = cubitFor(
      serviceWith(rules(androidMin: '9.0.0')),
      installed: null,
    );
    await cubit.check(lastPrompted: null);
    expect(cubit.state.kind, UpdateKind.none);
  });

  group('builds, force and the closed sign', () {
    String withAndroid(
      Map<String, dynamic> android, {
      Map<String, dynamic>? maintenance,
    }) => jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'update': <String, dynamic>{
        'android': <String, dynamic>{
          'storeUrl': 'https://play.example/app',
          ...android,
        },
      },
      'maintenance': ?maintenance,
    });

    test('the install\'s own build number is weighed', () async {
      final UpdateCubit old = cubitFor(
        serviceWith(
          withAndroid(<String, dynamic>{'min': '1.0.0', 'minBuild': 20}),
        ),
        build: '19',
      );
      await old.check(lastPrompted: null);
      expect(old.state.kind, UpdateKind.required);
      expect(old.state.target, '1.0.0 (20)');

      final UpdateCubit current = cubitFor(
        serviceWith(
          withAndroid(<String, dynamic>{'min': '1.0.0', 'minBuild': 20}),
        ),
        build: '20',
      );
      await current.check(lastPrompted: null);
      expect(current.state.kind, UpdateKind.none);
    });

    test('a forced latest is required', () async {
      final UpdateCubit cubit = cubitFor(
        serviceWith(
          withAndroid(<String, dynamic>{'latest': '1.1.0', 'force': true}),
        ),
      );
      await cubit.check(lastPrompted: DateTime(2026, 9, 20, 11));
      expect(cubit.state.kind, UpdateKind.required);
      cubit.dismiss();
      expect(cubit.state.kind, UpdateKind.required, reason: 'no "later"');
    });

    test('the closed sign is shown ahead of everything, for its platforms, '
        'and comes down on retry when the site says so', () async {
      const Map<String, dynamic> up = <String, dynamic>{
        'enabled': true,
        'title': <String, String>{'ar': 'صيانة', 'en': 'Maintenance'},
        'message': <String, String>{'ar': 'نعود قريبًا', 'en': 'Back soon'},
        'platforms': <String>['android'],
        'until': '',
      };
      final String bundled = withAndroid(<String, dynamic>{
        'min': '9.0.0',
        'latest': '9.0.0',
      }, maintenance: up);
      // The network answers with the sign taken down.
      final String published = withAndroid(
        <String, dynamic>{'min': '9.0.0', 'latest': '9.0.0'},
        maintenance: <String, dynamic>{...up, 'enabled': false},
      );
      final AppInfoService service = AppInfoService(
        _Bundle(bundled),
        client: MockClient(
          (_) async => http.Response.bytes(utf8.encode(published), 200),
        ),
        storageDirectory: () => throw UnsupportedError('no cache'),
      );
      addTearDown(service.dispose);

      final UpdateCubit ios = cubitFor(service, platform: TargetPlatform.iOS);
      await ios.check(lastPrompted: null);
      expect(ios.state.underMaintenance, isFalse, reason: 'Android only');
      expect(ios.state.kind, UpdateKind.none, reason: 'no iOS rule here');

      final UpdateCubit android = cubitFor(
        AppInfoService(
          _Bundle(bundled),
          client: MockClient((_) async => http.Response('', 404)),
          storageDirectory: () => throw UnsupportedError('no cache'),
        ),
      );
      await android.check(lastPrompted: null);
      expect(android.state.underMaintenance, isTrue);
      expect(android.state.maintenance!.message.en, 'Back soon');
      expect(
        android.state.kind,
        UpdateKind.none,
        reason: 'the sign, not the prompt',
      );

      final UpdateCubit reopened = cubitFor(service);
      await reopened.check(lastPrompted: null);
      await settle();
      // The refresh that check kicked off has already brought the sign down;
      // retry is what the page offers, and it lands on the same answer.
      await reopened.retry();
      expect(reopened.state.underMaintenance, isFalse);
      expect(reopened.state.kind, UpdateKind.required);
    });
  });
}
