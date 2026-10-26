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
    List<SimilarRef> similar = const <SimilarRef>[],
    int? juzFirst,
    int? juzLast,
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
                similar: similar,
                juzFirst: juzFirst,
                juzLast: juzLast,
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
    expect(find.text('سورة مكية، عدد آياتها ٣٠'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in English too', (WidgetTester tester) async {
    await pump(tester, locale: AppLocalization.english);
    expect(find.text('Makki surah, 30 ayahs'), findsOneWidget);
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
    await pump(
      tester,
      similar: <SimilarRef>[(ref: const AyahRef(67, 1), surah: mulk)],
    );
    expect(entry(Icons.compare_arrows), findsOneWidget);
  });

  testWidgets('the entry names the most alike two, and counts the rest', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      similar: <SimilarRef>[
        (ref: const AyahRef(67, 1), surah: mulk),
        (ref: const AyahRef(67, 12), surah: mulk),
        (ref: const AyahRef(67, 20), surah: mulk),
        (ref: const AyahRef(67, 29), surah: mulk),
      ],
    );
    expect(find.text('تشبه: الملك ١، الملك ١٢، و٢ غيرها'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in English, the same', (WidgetTester tester) async {
    await pump(
      tester,
      locale: AppLocalization.english,
      similar: <SimilarRef>[(ref: const AyahRef(67, 1), surah: mulk)],
    );
    expect(find.text('Resembles: ${mulk.nameEn} 1'), findsOneWidget);
  });

  testWidgets('one way on to the end of the surah, listening; nothing to play '
      'without audio', (WidgetTester tester) async {
    await pump(tester);
    expect(entry(Icons.headphones_outlined), findsOneWidget);
    expect(
      find.byTooltip('استمع من هنا إلى آخر السورة، مرة واحدة'),
      findsOneWidget,
    );
    await pump(tester, canPlay: false);
    expect(entry(Icons.headphones_outlined), findsNothing);
    expect(entry(Icons.repeat_one), findsNothing);
  });

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

  testWidgets('the surah line says which juz it is in, or which it spans', (
    WidgetTester tester,
  ) async {
    await pump(tester, juzFirst: 29, juzLast: 29);
    expect(find.text('سورة مكية، عدد آياتها ٣٠، الجزء ٢٩'), findsOneWidget);
    await pump(tester, juzFirst: 1, juzLast: 3);
    expect(find.textContaining('الأجزاء ١–٣'), findsOneWidget);
    await pump(tester);
    expect(find.text('سورة مكية، عدد آياتها ٣٠'), findsOneWidget);
  });
}
