import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahfiz/features/progress/screen/progress_screen.dart';
import 'package:tahfiz/features/session_setup/widgets/setup_controls.dart';
import 'package:tahfiz/features/settings/screen/settings_screen.dart';
import 'package:tahfiz/features/surah_list/widgets/surah_row.dart';

import '../app_harness.dart';

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  group('settings', () {
    testWidgets('lists the reciter rather than hardcoding a label', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.settings_outlined),
      );

      expect(find.byType(SettingsScreen), findsOneWidget);
      // A radio list even with one entry, so a second reciter needs no UI
      // change.
      expect(find.byType(RadioListTile<String>), findsOneWidget);
      expect(find.text('أحمد خليل شاهين'), findsOneWidget);
    });

    testWidgets('the default repeat count pre-fills the next session', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);

      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.settings_outlined),
      );

      // First stepper on the settings screen is the default repeat count.
      // Pumped between taps: the button's callback closes over the value from
      // the frame it was built in, so two taps in one frame both send 4.
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);

      // Restart the app rather than navigating back: this asserts the choice
      // was persisted, not just held in memory.
      await harness.pumpApp(tester);

      await AppHarness.tapAndSettle(tester, find.byType(SurahRow));

      // N=5 over all 7 ayahs: 13 steps, 5 * 34 = 170 recitations.
      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      expect(summary.stepCount, 13);
      expect(summary.unitCount, 170);
    });
  });

  group('progress', () {
    testWidgets('shows one tile per ayah and marks one memorized', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.grid_view_outlined),
      );

      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(find.text('لم يبدأ'), findsNWidgets(7));

      await AppHarness.tapAndSettle(tester, find.text('الآية 3'));

      expect(find.text('محفوظة'), findsOneWidget);
      expect(find.text('لم يبدأ'), findsNWidgets(6));
    });

    testWidgets('a memorized ayah shows on the home row', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.grid_view_outlined),
      );

      await AppHarness.tapAndSettle(tester, find.text('الآية 1'));

      // Restarting proves the mark was written, not just shown.
      await harness.pumpApp(tester);

      expect(find.text('1 من 7 محفوظة'), findsOneWidget);
    });
  });
}
