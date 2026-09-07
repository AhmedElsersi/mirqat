import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahfiz/core/localization/app_localization.dart';
import 'package:tahfiz/features/session_setup/screen/session_setup_screen.dart';
import 'package:tahfiz/features/session_setup/widgets/setup_controls.dart';
import 'package:tahfiz/features/surah_list/widgets/surah_row.dart';

import '../app_harness.dart';

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  Future<void> openSetup(WidgetTester tester) async {
    await AppHarness.tapAndSettle(tester, find.byType(SurahRow));
  }

  group('localisation and direction', () {
    testWidgets('launches in Arabic, laid out right to left', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context).languageCode, 'ar');
      expect(Directionality.of(context), TextDirection.rtl);
    });

    testWidgets('mirrors to left-to-right when forced to English', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester, locale: AppLocalization.english);

      final BuildContext context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context).languageCode, 'en');
      expect(Directionality.of(context), TextDirection.ltr);
      expect(find.text('Tahfiz'), findsOneWidget);
    });

    testWidgets('no user-facing string is a raw translation key', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      for (final Text widget in tester.widgetList<Text>(find.byType(Text))) {
        final String? data = widget.data;
        if (data == null) continue;
        expect(
          data.contains('.') && !data.contains(' ') && data.length > 6,
          isFalse,
          reason: 'looks like an untranslated key: "$data"',
        );
      }
    });
  });

  group('surah list', () {
    testWidgets('shows exactly the catalog, with no placeholder rows', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      expect(find.byType(SurahRow), findsOneWidget);
      expect(find.text('الفاتحة'), findsOneWidget);
    });

    testWidgets('opens session setup when a surah is tapped', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSetup(tester);

      expect(find.byType(SessionSetupScreen), findsOneWidget);
      expect(find.byType(SessionSummary), findsOneWidget);
    });
  });

  group('session setup', () {
    testWidgets('summarises the default full-surah session', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSetup(tester);

      // Full Al-Fatiha, N=3, cumulative: 13 steps, 102 recitations.
      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      expect(summary.stepCount, 13);
      expect(summary.unitCount, 102);
      expect(summary.duration, isNotEmpty);
    });

    testWidgets('the summary tracks the repeat count live', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSetup(tester);

      // Steppers in order: range from, range to, then the repeat count.
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).at(2));

      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      // N=4 over 7 ayahs: still 13 steps, 4 * 34 = 136 recitations.
      expect(summary.stepCount, 13);
      expect(summary.unitCount, 136);
    });
  });

  group('layout resilience', () {
    testWidgets('does not overflow at 320 dp wide', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await harness.pumpApp(tester);
      expect(tester.takeException(), isNull);

      await openSetup(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow at the largest system font scale', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await harness.pumpApp(tester);
      expect(tester.takeException(), isNull);

      await openSetup(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
