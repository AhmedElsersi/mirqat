import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/reciter_avatar.dart';
import 'package:mirqat/core/widgets/session_controls.dart';
import 'package:mirqat/features/progress/screen/progress_screen.dart';
import 'package:mirqat/features/settings/screen/settings_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';

import '../app_harness.dart';

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  Future<void> openSettings(WidgetTester tester) async {
    await AppHarness.tapAndSettle(tester, find.byIcon(Icons.settings_outlined));
  }

  /// Scrolls the settings list until [finder] is on screen.
  ///
  /// The screen is three groups deep now — عام, القارئ, then the collapsed
  /// session group — so the lower two are below the fold on a test-sized
  /// viewport and a ListView has not built them yet. Scrolling is how the
  /// reader reaches them, so it is how the test does.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('settings', () {
    testWidgets('lists the reciter rather than hardcoding a label', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
      await reveal(tester, find.byType(RadioListTile<String>));

      // A radio list even with one entry, so a second reciter needs no UI
      // change.
      expect(find.byType(RadioListTile<String>), findsOneWidget);
      expect(find.text('أحمد خليل شاهين'), findsOneWidget);
      // With the reciter's photo beside the name.
      expect(find.byType(ReciterAvatar), findsOneWidget);
    });

    testWidgets('the session group is collapsed on first open', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('إعدادات الجلسة'));

      // The heading is there...
      expect(find.text('إعدادات الجلسة'), findsOneWidget);
      // ...but its contents are not built until it is expanded.
      expect(find.byType(SessionTuningControls), findsNothing);
      expect(find.text('طريقة الوصل'), findsNothing);

      await AppHarness.tapAndSettle(tester, find.text('إعدادات الجلسة'));

      expect(find.byType(SessionTuningControls), findsOneWidget);
      expect(find.text('طريقة الوصل'), findsOneWidget);
      // The retired mode is gone from the picker.
      expect(find.text('ثنائي'), findsNothing);
      // And the new one is there.
      expect(find.text('متصل'), findsOneWidget);
    });

    testWidgets('the home view toggle mirrors the app bar', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);

      // Same stored value as the app-bar toggle, so switching here shows up
      // there.
      await AppHarness.tapAndSettle(tester, find.text('شبكة'));
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));

      expect(find.byIcon(Icons.view_list_outlined), findsOneWidget);
      expect(find.byType(SurahRow), findsNothing);
    });

    testWidgets('the default repeat count pre-fills the next session', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('إعدادات الجلسة'));
      await AppHarness.tapAndSettle(tester, find.text('إعدادات الجلسة'));
      await reveal(tester, find.byIcon(Icons.add).first);

      // The first stepper inside the session group is the repeat count.
      // Pumped between taps: the button's callback closes over the value from
      // the frame it was built in, so two taps in one frame both send 4.
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);

      // Restart the app rather than navigating back: this asserts the choice
      // was persisted, not just held in memory.
      await harness.pumpApp(tester);

      await AppHarness.tapAndSettle(tester, find.byType(SurahRow).first);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.tune));

      // N=5 over all 7 ayahs, continuous: one step, 35 recitations.
      final SessionSummary summary = tester.widget<SessionSummary>(
        find.byType(SessionSummary),
      );
      expect(summary.stepCount, 1);
      expect(summary.unitCount, 35);
    });
  });

  group('progress', () {
    /// Every row carries the progress button, so the first one — Al-Fatiha,
    /// whose seven ayahs the assertions below count.
    Future<void> openProgress(WidgetTester tester) async {
      await AppHarness.tapAndSettle(
        tester,
        find.byIcon(Icons.insights_outlined).first,
      );
    }

    testWidgets('shows one tile per ayah and marks one memorized', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openProgress(tester);

      expect(find.byType(ProgressScreen), findsOneWidget);
      expect(find.text('لم يبدأ'), findsNWidgets(7));

      await AppHarness.tapAndSettle(tester, find.text('الآية ٣'));

      expect(find.text('محفوظة'), findsOneWidget);
      expect(find.text('لم يبدأ'), findsNWidgets(6));
    });

    testWidgets('a memorized ayah survives a restart', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openProgress(tester);

      await AppHarness.tapAndSettle(tester, find.text('الآية ١'));

      // Restarting proves the mark was written, not just shown. It does NOT
      // prove the home row updates while the app is running — a restart
      // rebuilds everything, so the cubit reloads no matter what. The test
      // below is the one that covers that, and this one passed happily while
      // the bar was stuck.
      await harness.pumpApp(tester);

      expect(find.text('١ من ٧ محفوظة'), findsOneWidget);
    });

    testWidgets('the home row updates on the way back, with no restart', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      expect(find.text('لم يبدأ بعد'), findsWidgets);
      expect(_fractionOfFirstRow(tester), 0);

      await openProgress(tester);
      await AppHarness.tapAndSettle(tester, find.text('الآية ١'));
      await AppHarness.tapAndSettle(tester, find.text('الآية ٢'));

      // Back to the home screen. `pushNamed` left it mounted underneath, so
      // nothing rebuilds it and nothing re-runs its loader — the count has to
      // arrive through the progress store's change stream instead.
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));
      await _awaitProgressRefresh(tester);

      expect(find.text('٢ من ٧ محفوظة'), findsOneWidget);
      // And the bar itself moved, not just the caption.
      expect(_fractionOfFirstRow(tester), closeTo(2 / 7, 0.0001));
    });

    testWidgets('un-marking an ayah takes the home row back down', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openProgress(tester);
      await AppHarness.tapAndSettle(tester, find.text('الآية ١'));
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));
      await _awaitProgressRefresh(tester);
      expect(find.text('١ من ٧ محفوظة'), findsOneWidget);

      // Toggle it back off and return again: the stream has to carry the
      // decrease as readily as the increase.
      await openProgress(tester);
      await AppHarness.tapAndSettle(tester, find.text('الآية ١'));
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));
      await _awaitProgressRefresh(tester);

      expect(find.text('لم يبدأ بعد'), findsWidgets);
      expect(_fractionOfFirstRow(tester), 0);
    });

    testWidgets('the refresh does not flash a spinner over the rows', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openProgress(tester);
      await AppHarness.tapAndSettle(tester, find.text('الآية ١'));
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));

      // Mid-refresh the rows must still be on screen. A background re-read
      // that flips to LoadStatus.loading would replace the whole list with a
      // spinner for a one-number change.
      expect(find.byType(SurahRow), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await _awaitProgressRefresh(tester);
      expect(find.byType(SurahRow), findsWidgets);
      expect(find.text('١ من ٧ محفوظة'), findsOneWidget);
    });
  });
}

/// The first home row's progress-bar value.
double? _fractionOfFirstRow(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byType(SurahRow).first,
        matching: find.byType(LinearProgressIndicator),
      ),
    )
    .value;

/// Waits out the cubit's coalesce window, then settles.
///
/// Progress writes arrive as a burst, so the reload is debounced rather than
/// run once per record. Real time has to pass for that timer, hence the
/// `runAsync`; the pump afterwards is what lets the new state reach the tree.
Future<void> _awaitProgressRefresh(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 500)),
  );
  await AppHarness.settle(tester);
}
