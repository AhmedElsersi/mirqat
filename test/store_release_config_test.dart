import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the stores check before a human ever sees the app. Each of these was a
/// real gap found while preparing the first release, and each is the kind of
/// thing that disappears in a merge without anyone noticing — until an upload
/// is bounced or a session goes silent when the phone locks.
void main() {
  final String plist = File('ios/Runner/Info.plist').readAsStringSync();
  final String podfile = File('ios/Podfile').readAsStringSync();
  final String pbxproj = File(
    'ios/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final String manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  String after(String key) => plist.substring(plist.indexOf('<key>$key</key>'));

  group('iOS', () {
    test('a session keeps reciting when the phone locks', () {
      // Without the audio background mode iOS suspends the app, and with it
      // the recitation, a few seconds after the screen goes dark.
      expect(plist, contains('<key>UIBackgroundModes</key>'));
      final String modes = after('UIBackgroundModes');
      expect(modes.substring(0, modes.indexOf('</array>')), contains('audio'));
    });

    test('pack downloads may finish in the background', () {
      final String modes = after('UIBackgroundModes');
      expect(modes.substring(0, modes.indexOf('</array>')), contains('fetch'));
    });

    test('export compliance is answered once, not at every upload', () {
      // HTTPS only, which is exempt.
      expect(
        after('ITSAppUsesNonExemptEncryption').substring(0, 80),
        contains('<false/>'),
      );
    });

    test('no App Transport Security exception', () {
      // Tried and not needed: ATS does not apply to IP addresses, so
      // just_audio's caching proxy on 127.0.0.1 streams without one
      // (tool/stream_probe.dart proves it on a device). An exception nobody
      // needs is a question in review and a hole for nothing.
      expect(plist, isNot(contains('NSAllowsArbitraryLoads')));
      expect(plist, isNot(contains('NSAppTransportSecurity')));
    });

    test('the privacy manifest exists, is in the target, and collects '
        'nothing', () {
      final File privacy = File('ios/Runner/PrivacyInfo.xcprivacy');
      expect(privacy.existsSync(), isTrue);
      expect(pbxproj, contains('PrivacyInfo.xcprivacy in Resources'));

      final String text = privacy.readAsStringSync();
      expect(text, contains('<key>NSPrivacyTracking</key>\n\t<false/>'));
      expect(
        text,
        contains('<key>NSPrivacyCollectedDataTypes</key>\n\t<array/>'),
      );
    });

    test('the Photos permission can never be requested, and the scan that '
        'looks for it is answered', () {
      for (final String flag in <String>[
        'BYPASS_PERMISSION_NOTIFICATIONS',
        'BYPASS_PERMISSION_IOSADDTOPHOTOLIBRARY',
        'BYPASS_PERMISSION_IOSCHANGEPHOTOLIBRARY',
      ]) {
        expect(podfile, contains("'-D $flag'"), reason: flag);
      }
      // The plugin still names the Photos classes, so Apple asks for these.
      for (final String key in <String>[
        'NSPhotoLibraryAddUsageDescription',
        'NSPhotoLibraryUsageDescription',
      ]) {
        expect(plist, contains('<key>$key</key>'), reason: key);
        for (final String locale in <String>['ar', 'en']) {
          expect(
            File(
              'ios/Runner/$locale.lproj/InfoPlist.strings',
            ).readAsStringSync(),
            contains('"$key"'),
            reason: '$key in $locale',
          );
        }
      }
    });

    test('nothing asks for a permission the app has no use for', () {
      for (final String key in <String>[
        'NSMicrophoneUsageDescription',
        'NSCameraUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSUserTrackingUsageDescription',
        'NSContactsUsageDescription',
      ]) {
        expect(plist, isNot(contains(key)), reason: key);
      }
    });

    test('the deployment target is pinned in the Podfile', () {
      expect(
        podfile,
        contains(RegExp(r"^platform :ios, '\d+\.\d+'", multiLine: true)),
      );
    });
  });

  group('Android', () {
    test('the permissions are the network and the media session, and '
        'nothing that needs asking for', () {
      final Iterable<String> permissions = RegExp(
        r'uses-permission android:name="([^"]+)"',
      ).allMatches(manifest).map((RegExpMatch m) => m.group(1)!);
      // All four are granted at install. None shows the user a prompt.
      expect(permissions, <String>[
        'android.permission.INTERNET',
        'android.permission.WAKE_LOCK',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK',
      ]);
    });

    test('the lock-screen controls have their service and receiver', () {
      expect(manifest, contains('com.ryanheise.audioservice.AudioService'));
      expect(
        manifest,
        contains('android:foregroundServiceType="mediaPlayback"'),
      );
      expect(
        manifest,
        contains('com.ryanheise.audioservice.MediaButtonReceiver'),
      );
      // The activity has to share audio_service's engine, or the lock
      // screen's pause reaches an isolate nothing is playing in.
      expect(
        File(
          'android/app/src/main/kotlin/com/mirqat/app/MainActivity.kt',
        ).readAsStringSync(),
        contains(': AudioServiceActivity()'),
      );
    });

    test('downloaded audio stays out of backups', () {
      // Auto Backup fails outright past 25 MB, and would take the
      // memorization progress down with it.
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      for (final String file in <String>[
        'backup_rules.xml',
        'data_extraction_rules.xml',
      ]) {
        expect(
          File('android/app/src/main/res/xml/$file').readAsStringSync(),
          contains('path="audio/"'),
          reason: file,
        );
      }
    });

    test('cleartext is allowed to the loopback proxy and nowhere else', () {
      final String network = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();
      expect(network, contains('127.0.0.1'));
      expect(
        network,
        isNot(contains('<base-config cleartextTrafficPermitted="true"')),
      );
    });

    test('signing secrets are not in git', () {
      final String ignore = File('android/.gitignore').existsSync()
          ? File('android/.gitignore').readAsStringSync()
          : '';
      final String rootIgnore = File('.gitignore').readAsStringSync();
      expect('$ignore\n$rootIgnore', contains('key.properties'));
    });
  });
}
