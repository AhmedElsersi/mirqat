import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/features/mushaf/widgets/ayah_actions_sheet.dart';

import '../localized.dart';

const Surah mulk = Surah(
  number: 67,
  nameAr: 'الملك',
  nameEn: 'Al-Mulk',
  ayahCount: 30,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

void main() {
  setUpAll(ensureTestLocalization);

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = AppLocalization.arabic,
    bool isStumbled = false,
    bool hasSimilar = false,
    bool canPlay = true,
  }) async {
    Intl.defaultLocale = locale.toString();
    addTearDown(() => Intl.defaultLocale = null);
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      localized(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (BuildContext context, _) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Scaffold(
              body: AyahActionsSheet(
                ayah: const AyahRef(67, 3),
                surah: mulk,
                canPlay: canPlay,
                hasChosenRange: false,
                isStumbled: isStumbled,
                hasSimilar: hasSimilar,
              ),
            ),
          ),
        ),
        locale: locale,
      ),
    );
    await settleLocalization(tester);
  }

  Finder entry(IconData icon) => find.byIcon(icon);

  testWidgets('says where the surah was revealed and how long it is', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(find.text('سورة مكية · عدد آياتها ٣٠'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in English too', (WidgetTester tester) async {
    await pump(tester, locale: AppLocalization.english);
    expect(find.text('Makki surah · 30 ayahs'), findsOneWidget);
  });

  testWidgets('offers a stumble always; to clear one only where there is one', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(entry(Icons.flag_outlined), findsOneWidget);
    expect(entry(Icons.outlined_flag), findsNothing);
    await pump(tester, isStumbled: true);
    expect(entry(Icons.outlined_flag), findsOneWidget);
  });

  testWidgets('similar ayahs only where the data has some', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    expect(entry(Icons.compare_arrows), findsNothing);
    await pump(tester, hasSimilar: true);
    expect(entry(Icons.compare_arrows), findsOneWidget);
  });

  testWidgets(
    'listening is offered beside playing, and neither without audio',
    (WidgetTester tester) async {
      await pump(tester);
      expect(entry(Icons.headphones_outlined), findsOneWidget);
      await pump(tester, canPlay: false);
      expect(entry(Icons.headphones_outlined), findsNothing);
      expect(entry(Icons.play_arrow_outlined), findsNothing);
    },
  );

  testWidgets('a choice pops with its action', (WidgetTester tester) async {
    AyahAction? chosen;
    Intl.defaultLocale = 'ar';
    addTearDown(() => Intl.defaultLocale = null);
    await tester.pumpWidget(
      localized(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (BuildContext context, _) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () async {
                  chosen = await showModalBottomSheet<AyahAction>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const AyahActionsSheet(
                      ayah: AyahRef(67, 3),
                      surah: mulk,
                      canPlay: true,
                      hasChosenRange: false,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await settleLocalization(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(entry(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(chosen, AyahAction.stumble);
  });
}
