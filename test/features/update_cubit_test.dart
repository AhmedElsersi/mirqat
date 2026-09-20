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
  _Version(this.version);

  final String? version;

  @override
  Future<InstalledVersion?> read() async => version == null
      ? null
      : InstalledVersion(version: version!, buildNumber: '1');
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
    TargetPlatform platform = TargetPlatform.android,
  }) {
    final UpdateCubit cubit = UpdateCubit(
      appInfoService: service,
      appVersionService: _Version(installed),
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
}
