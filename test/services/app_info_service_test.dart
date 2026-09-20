import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/models/app_info.dart';
import 'package:mirqat/services/app_info_service.dart';

class _Bundle implements AssetReader {
  const _Bundle(this.contents);

  final String contents;

  @override
  Future<String> loadString(String path) async => contents;
}

String fileSaying(String about, {String min = ''}) =>
    jsonEncode(<String, dynamic>{
      'schemaVersion': 1,
      'about': <String, String>{'ar': about, 'en': about},
      'update': <String, dynamic>{
        'android': <String, String>{'min': min, 'latest': '', 'storeUrl': 'x'},
      },
    });

/// `app.json`, fetched like the manifest: answer at once from the device,
/// refresh behind, and never let the network be the reason a screen is empty.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('app_info'));
  tearDown(() => dir.deleteSync(recursive: true));

  AppInfoService service({
    required String bundled,
    required Future<http.Response> Function(http.Request) network,
  }) {
    final AppInfoService s = AppInfoService(
      _Bundle(bundled),
      client: MockClient(network),
      storageDirectory: () async => dir,
      url: 'https://cdn.example/site/app.json',
    );
    addTearDown(s.dispose);
    return s;
  }

  test(
    'answers from the bundled copy without waiting for the network',
    () async {
      final AppInfoService s = service(
        bundled: fileSaying('bundled'),
        network: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return http.Response.bytes(utf8.encode(fileSaying('fetched')), 200);
        },
      );
      expect((await s.load()).about.ar, 'bundled');
    },
  );

  test(
    'a fetched copy replaces it, is announced, and is kept for next time',
    () async {
      final AppInfoService first = service(
        bundled: fileSaying('bundled'),
        network: (_) async =>
            http.Response.bytes(utf8.encode(fileSaying('fetched')), 200),
      );
      final Future<AppInfo> announced = first.changes.firstWhere(
        (AppInfo i) => i.about.ar == 'fetched',
      );
      await first.load();
      expect((await announced).about.ar, 'fetched');
      expect(first.current.about.ar, 'fetched');
      await first.refresh();

      // A cold start with no network: the cached copy, not the bundled one.
      final AppInfoService second = service(
        bundled: fileSaying('bundled'),
        network: (_) async => throw const SocketException('offline'),
      );
      expect((await second.load()).about.ar, 'fetched');
    },
  );

  test(
    'offline, timed out or refused: what is on the device stays, quietly',
    () async {
      for (final Future<http.Response> Function(http.Request) network
          in <Future<http.Response> Function(http.Request)>[
            (_) async => throw const SocketException('offline'),
            (_) async => http.Response('nope', 500),
            (_) async => http.Response('', 404),
          ]) {
        final AppInfoService s = service(
          bundled: fileSaying('bundled'),
          network: network,
        );
        await s.load();
        expect((await s.refresh()).about.ar, 'bundled');
      }
    },
  );

  test('a page that is not app.json is not taken up — it must not be able to '
      'blank the About screen or lift an update rule', () async {
    for (final String body in <String>[
      '<html>404</html>',
      '{}',
      '[]',
      'null',
      '',
    ]) {
      final AppInfoService s = service(
        bundled: fileSaying('bundled', min: '1.2.0'),
        network: (_) async => http.Response(body, 200),
      );
      await s.load();
      final AppInfo after = await s.refresh();
      expect(after.about.ar, 'bundled', reason: body);
      expect(after.update.android.min, '1.2.0', reason: body);
      expect(
        File('${dir.path}/app.json').existsSync(),
        isFalse,
        reason: 'and it is not cached either: $body',
      );
    }
  });

  test('Arabic survives the trip whatever charset the host claims', () async {
    final AppInfoService s = service(
      bundled: fileSaying('bundled'),
      // GitHub Pages serves JSON without a charset; http would read it Latin-1.
      network: (_) async => http.Response.bytes(
        utf8.encode(fileSaying('من نحن')),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      ),
    );
    await s.load();
    expect((await s.refresh()).about.ar, 'من نحن');
  });

  test('a path in the file is read against where the file lives', () {
    final AppInfoService s = service(
      bundled: '{}',
      network: (_) async => http.Response('', 404),
    );
    expect(
      s.resolve('images/developer.jpg'),
      Uri.parse('https://cdn.example/site/images/developer.jpg'),
    );
    expect(
      s.resolve('https://elsewhere.example/me.png'),
      Uri.parse('https://elsewhere.example/me.png'),
    );
    expect(s.resolve('  '), isNull);
  });

  test('round-trips: what the admin tool writes is what the app reads', () {
    const AppInfo info = AppInfo(
      about: LocalizedText(ar: 'من نحن', en: 'About'),
      goal: LocalizedText(ar: 'هدف', en: 'Goal'),
      developer: DeveloperInfo(
        name: LocalizedText(ar: 'اسم', en: 'Name'),
        photo: 'images/me.jpg',
        links: <DeveloperLink, String>{DeveloperLink.email: 'a@b.co'},
      ),
      update: UpdateRules(
        android: PlatformUpdate(min: '1.0.0', latest: '1.2.0', storeUrl: 'x'),
        notes: LocalizedText(ar: 'جديد', en: 'New'),
      ),
    );
    expect(AppInfo.parse(jsonEncode(info.toJson())), info);
    expect(info.toJson()['schemaVersion'], 1);
  });
}
