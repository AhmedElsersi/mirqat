import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/models/app_info.dart';
import 'package:mirqat/services/app_info_service.dart';

class _Reader implements AssetReader {
  _Reader(this.contents);

  final String? contents;

  @override
  Future<String> loadString(String path) async =>
      contents ?? (throw assetMissing(path, 'not there'));
}

bool _isArabic(String s) => s.runes.any((int r) => r >= 0x0600 && r <= 0x06FF);

/// `app.json`: what the app says about itself. Edited by hand, and soon
/// fetched over a network, so what matters most is that nothing written in it
/// can take a screen down.
void main() {
  group('the copy that ships', () {
    late AppInfo info;

    setUpAll(
      () => info = AppInfo.parse(
        File(AssetPaths.bundledAppInfo).readAsStringSync(),
      ),
    );

    test('says who we are and what we are for, in both languages', () {
      for (final LocalizedText text in <LocalizedText>[info.about, info.goal]) {
        expect(text.ar.trim(), isNotEmpty);
        expect(text.en.trim(), isNotEmpty);
        expect(_isArabic(text.ar), isTrue, reason: 'the Arabic is Arabic');
      }
    });

    test('names the developer, with an email that opens a mail app', () {
      expect(info.developer.name.of('en'), isNotEmpty);
      final Uri? mail = info.developer.uriFor(DeveloperLink.email);
      expect(mail?.scheme, 'mailto');
      expect(mail?.path, contains('@'));
    });

    test('every link that is filled in can be opened; the rest are absent', () {
      for (final DeveloperLink link in DeveloperLink.values) {
        final bool filled = info.developer.links.containsKey(link);
        expect(info.developer.uriFor(link) != null, filled, reason: link.name);
      }
    });

    test('promises nothing the app does not do', () {
      // The copy says no ads, no accounts, nothing collected. If any of that
      // stops being true, this line is the first thing that has to change.
      expect(info.about.ar, contains('بلا إعلانات'));
      expect(info.about.en.toLowerCase(), contains('no ads'));
    });
  });

  group('read forgivingly', () {
    test(
      'not JSON, not an object, or empty: an empty AppInfo, never a throw',
      () {
        for (final String bad in <String>['', 'not json', '[]', '42', 'null']) {
          expect(AppInfo.parse(bad), AppInfo.empty, reason: '"$bad"');
        }
      },
    );

    test('a field of the wrong type reads as empty and spares the others', () {
      final AppInfo info = AppInfo.parse(
        jsonEncode(<String, dynamic>{
          'about': 7,
          'goal': <String, dynamic>{'ar': 'هدف', 'en': 12},
          'developer': <String, dynamic>{
            'name': 'a string, not a map',
            'email': <int>[1],
            'github': 'github.com/someone',
          },
        }),
      );
      expect(info.about, LocalizedText.empty);
      expect(info.goal.ar, 'هدف');
      expect(info.goal.en, isEmpty);
      expect(info.developer.name, LocalizedText.empty);
      expect(info.developer.links.keys, <DeveloperLink>[DeveloperLink.github]);
    });

    test(
      'builds, force, the remind interval and the sign are read forgivingly, '
      'and written back',
      () {
        final AppInfo info = AppInfo.parse(
          jsonEncode(<String, dynamic>{
            'update': <String, dynamic>{
              'android': <String, dynamic>{
                'min': '1.2.0',
                'minBuild': '25',
                'latest': '1.3.0',
                'latestBuild': 0,
                'force': 'yes',
                'storeUrl': 'https://play.example/app',
              },
              'remindAfterDays': 3,
            },
            'maintenance': <String, dynamic>{
              'enabled': true,
              'message': <String, String>{'ar': 'صيانة', 'en': 'Maintenance'},
              'platforms': <Object?>['iOS', 'web', 7],
              'until': '2026-10-01T02:00:00Z',
            },
          }),
        );
        final PlatformUpdate android = info.update.android;
        expect(android.minBuild, 25, reason: 'digits in a string still count');
        expect(android.latestBuild, isNull, reason: 'zero is no build');
        expect(android.force, isFalse, reason: 'only true is true');
        expect(android.target, '1.3.0');
        expect(info.update.remindAfterDays, 3);
        expect(info.maintenance.enabled, isTrue);
        expect(info.maintenance.platforms, <String>{'ios'});
        expect(info.maintenance.until, DateTime.utc(2026, 10, 1, 2));
        expect(AppInfo.empty.maintenance, Maintenance.off);
        expect(AppInfo.empty.update.remindAfterDays, 1);

        final AppInfo again = AppInfo.parse(jsonEncode(info.toJson()));
        expect(again, info, reason: 'what is written is what is read');
      },
    );

    test('a language left blank falls back to the other one', () {
      const LocalizedText onlyArabic = LocalizedText(ar: 'نص', en: '  ');
      expect(onlyArabic.of('en'), 'نص');
      expect(onlyArabic.of('ar'), 'نص');
      expect(LocalizedText.empty.of('ar'), isEmpty);
    });

    test('a missing file is an empty AppInfo', () async {
      expect(await AppInfoService(_Reader(null)).load(), AppInfo.empty);
    });
  });

  group('links typed by hand', () {
    DeveloperInfo withLink(DeveloperLink link, String value) =>
        DeveloperInfo(links: <DeveloperLink, String>{link: value});

    test('an email with or without mailto:', () {
      for (final String typed in <String>['a@b.co', 'mailto:a@b.co']) {
        expect(
          withLink(DeveloperLink.email, typed).uriFor(DeveloperLink.email),
          Uri(scheme: 'mailto', path: 'a@b.co'),
        );
      }
      expect(
        withLink(
          DeveloperLink.email,
          'not an address',
        ).uriFor(DeveloperLink.email),
        isNull,
      );
    });

    test('a WhatsApp number however it was written', () {
      for (final String typed in <String>[
        '+20 100 123 4567',
        '201001234567',
        '0020-100-123-4567',
      ]) {
        final Uri? uri = withLink(
          DeveloperLink.whatsapp,
          typed,
        ).uriFor(DeveloperLink.whatsapp);
        expect(uri?.host, 'wa.me', reason: typed);
        expect(uri?.path, matches(RegExp(r'^/\d+$')), reason: typed);
      }
      expect(
        withLink(
          DeveloperLink.whatsapp,
          'https://wa.me/2010',
        ).uriFor(DeveloperLink.whatsapp),
        Uri.parse('https://wa.me/2010'),
      );
    });

    test('a profile with or without https://', () {
      for (final DeveloperLink link in <DeveloperLink>[
        DeveloperLink.github,
        DeveloperLink.linkedin,
        DeveloperLink.facebook,
      ]) {
        expect(
          withLink(link, 'example.com/me').uriFor(link),
          Uri.parse('https://example.com/me'),
        );
        expect(
          withLink(link, 'https://example.com/me').uriFor(link),
          Uri.parse('https://example.com/me'),
        );
      }
    });

    test('round-trips through JSON, empty links and all', () {
      const DeveloperInfo dev = DeveloperInfo(
        name: LocalizedText(ar: 'اسم', en: 'Name'),
        links: <DeveloperLink, String>{DeveloperLink.email: 'a@b.co'},
      );
      expect(DeveloperInfo.fromJson(dev.toJson()), dev);
      expect(dev.toJson()['facebook'], '');
    });
  });
}
