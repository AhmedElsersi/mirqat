import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/localization/app_localization.dart';

import 'app_harness.dart' show FileTranslationLoader;

bool _ready = false;

/// easy_localization, readied for a widget test that does not boot the app:
/// its locale store is shared_preferences, a platform channel with no host
/// under `flutter test`, so the channel is answered with nothing.
Future<void> ensureTestLocalization() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (MethodCall call) async =>
            call.method == 'getAll' ? <String, Object>{} : null,
      );
  if (_ready) return;
  await EasyLocalization.ensureInitialized();
  _ready = true;
}

/// [child] under the app's translations, read off disk.
Widget localized(Widget child, {Locale locale = AppLocalization.arabic}) =>
    EasyLocalization(
      supportedLocales: AppLocalization.supportedLocales,
      path: AppLocalization.translationsPath,
      startLocale: locale,
      fallbackLocale: AppLocalization.fallbackLocale,
      assetLoader: const FileTranslationLoader(),
      saveLocale: false,
      child: child,
    );

/// Lets the translations finish loading off the fake clock.
Future<void> settleLocalization(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
}
