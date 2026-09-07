import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahfiz/core/localization/app_localization.dart';
import 'package:tahfiz/main.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // easy_localization persists the chosen locale through shared_preferences,
    // which has no plugin implementation under `flutter test`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : null,
        );
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('app launches in Arabic with right-to-left layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: AppLocalization.supportedLocales,
        path: AppLocalization.translationsPath,
        startLocale: AppLocalization.startLocale,
        fallbackLocale: AppLocalization.fallbackLocale,
        assetLoader: const RootBundleAssetLoader(),
        child: const TahfizApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);

    final BuildContext context = tester.element(find.byType(Scaffold));
    expect(Localizations.localeOf(context).languageCode, 'ar');
    expect(Directionality.of(context), TextDirection.rtl);
  });
}
