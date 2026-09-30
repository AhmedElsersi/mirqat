import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mirqat/core/widgets/reciter_avatar.dart';
import 'package:mirqat/core/widgets/session_controls.dart';
import 'package:mirqat/features/progress/screen/progress_screen.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/features/settings/screen/downloads_screen.dart';
import 'package:mirqat/core/widgets/settings_card.dart';
import 'package:mirqat/features/about/screen/developer_screen.dart';
import 'package:mirqat/features/about/screen/how_to_use_screen.dart';
import 'package:mirqat/features/about/screen/info_page_screen.dart';
import 'package:mirqat/features/settings/screen/session_settings_screen.dart';
import 'package:mirqat/features/settings/screen/settings_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/features/surah_list/widgets/surah_tile.dart';

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
      await reveal(tester, find.byType(DropdownButton<String>));

      // The same dropdown as the session sheet's, fed from the catalogue,
      // so a second reciter needs no UI change.
      final Finder field = find.byType(DropdownButton<String>);
      expect(field, findsOneWidget);
      expect(
        find.descendant(of: field, matching: find.text('أحمد خليل شاهين')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('Ahmed Khalil Shaheen')),
        findsOneWidget,
      );
      // With the reciter's photo beside the name.
      expect(find.byType(ReciterAvatar), findsOneWidget);
    });

    testWidgets('the interface language is switched from the appearance card, '
        'and the app follows at once', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      expect(find.text('الإعدادات'), findsOneWidget);

      await reveal(tester, find.text('English'));
      await AppHarness.tapAndSettle(tester, find.text('English'));
      expect(find.text('Settings'), findsOneWidget);
      expect(
        EasyLocalization.of(
          tester.element(find.byType(SettingsScreen)),
        )!.locale.languageCode,
        'en',
      );

      await reveal(tester, find.text('العربية'));
      await AppHarness.tapAndSettle(tester, find.text('العربية'));
      expect(find.text('الإعدادات'), findsOneWidget);
    });

    testWidgets('opens the saved-recitations list, which starts empty', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('التسجيلات المحفوظة'));

      await AppHarness.tapAndSettle(
        tester,
        find.text('التسجيلات المحفوظة').last,
      );

      expect(find.byType(DownloadsScreen), findsOneWidget);
      // A fresh install has downloaded nothing: the screen says so and
      // explains where a download comes from, rather than showing an empty
      // list.
      expect(find.textContaining('لا توجد تسجيلات محفوظة'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('the storage group offers a quality and a Wi-Fi-only rule', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('جودة الصوت'));

      // Three qualities, standard chosen on a fresh install.
      expect(find.byType(RadioListTile<AudioQuality>), findsNWidgets(3));
      final RadioGroup<AudioQuality> group = tester
          .widget<RadioGroup<AudioQuality>>(
            find.byType(RadioGroup<AudioQuality>),
          );
      expect(group.groupValue, AudioQuality.standard);

      // And the metered-data guard is on by default.
      await reveal(tester, find.text('التنزيل عبر الواي فاي فقط'));
      final SwitchListTile wifi = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('التنزيل عبر الواي فاي فقط'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(wifi.value, isTrue);
    });

    testWidgets('choosing a quality persists it', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('عالية — ١٢٨ ك.ب/ث'));

      await AppHarness.tapAndSettle(tester, find.text('عالية — ١٢٨ ك.ب/ث'));

      // Read back through a fresh app, which is what a restart does.
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('جودة الصوت'));
      expect(
        tester
            .widget<RadioGroup<AudioQuality>>(
              find.byType(RadioGroup<AudioQuality>),
            )
            .groupValue,
        AudioQuality.high,
      );
    });

    testWidgets('the session\'s settings are a page of their own, built from '
        'the same form as the session sheet', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('إعدادات الجلسة'));

      // A row on the settings page, and none of the form itself.
      expect(find.text('إعدادات الجلسة'), findsOneWidget);
      expect(find.byType(SessionTuningControls), findsNothing);

      await AppHarness.tapAndSettle(tester, find.text('إعدادات الجلسة'));

      expect(find.byType(SessionSettingsScreen), findsOneWidget);
      expect(find.byType(SessionTuningControls), findsOneWidget);
      expect(find.text('طريقة الوصل'), findsOneWidget);
      // The retired mode is gone from the picker.
      expect(find.text('ثنائي'), findsNothing);
      // And the new one is there.
      expect(find.text('متصل'), findsOneWidget);

      // Back returns to Settings, not to the home page.
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('the text size is set on a real ayah, and the choice reaches '
        'the page', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.byType(Slider));

      // The sample is scripture in the mushaf face, not interface text.
      expect(
        find.descendant(
          of: find.byType(SettingsCard).first,
          matching: find.byType(AyahText),
        ),
        findsOneWidget,
      );

      final SettingsCubit cubit = BlocProvider.of<SettingsCubit>(
        tester.element(find.byType(SettingsScreen)),
      );
      await tester.runAsync(() async {
        await cubit.setArabicFontSize(36);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await AppHarness.settle(tester);
      expect(tester.widget<Slider>(find.byType(Slider)).value, 36);

      // A restart, then a page: it is drawn at one and a half times the size
      // that fits a printed line.
      await harness.pumpApp(tester);
      await AppHarness.openReading(tester, find.byType(SurahRow).first);
      expect(
        tester.widget<MushafPageView>(find.byType(MushafPageView)).textScale,
        36 / AppSettings.defaultArabicFontSize,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('every group sits in a container of its own', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);

      final Set<String> seen = <String>{};
      for (final String title in <String>[
        'المظهر والعرض',
        'القارئ',
        'الصوت والتخزين',
        'الجلسة',
        'عن التطبيق',
      ]) {
        // By its heading: a card further down is not built until it is
        // scrolled to, and `.first` of nothing throws instead of scrolling.
        await reveal(tester, find.text(title));
        expect(find.widgetWithText(SettingsCard, title), findsWidgets);
        seen.add(title);
        expect(tester.takeException(), isNull, reason: title);
      }
      expect(seen, hasLength(5));
    });

    testWidgets('the about card leads to how to use, our goal, about us and '
        'the developer', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      await openSettings(tester);

      Future<void> visit(String row, Type screen) async {
        await reveal(tester, find.text(row));
        await AppHarness.tapAndSettle(tester, find.text(row));
        expect(find.byType(screen), findsOneWidget, reason: row);
        expect(tester.takeException(), isNull, reason: row);
        await AppHarness.tapAndSettle(tester, find.byType(BackButton));
        expect(find.byType(SettingsScreen), findsOneWidget);
      }

      await visit('طريقة الاستخدام', HowToUseScreen);
      await visit('هدفنا', InfoPageScreen);
      await visit('من نحن', InfoPageScreen);
      await visit('عن المطوّر', DeveloperScreen);
    });

    testWidgets('the home view toggle mirrors the app bar', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);

      // Settings is the only place this is chosen now; the home screen just
      // follows it.
      await AppHarness.tapAndSettle(tester, find.text('شبكة'));
      await AppHarness.tapAndSettle(tester, find.byType(BackButton));

      expect(find.byType(SurahTile), findsWidgets);
      expect(find.byType(SurahRow), findsNothing);
    });

    testWidgets('the default repeat count pre-fills the next session', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await openSettings(tester);
      await reveal(tester, find.text('إعدادات الجلسة'));
      await AppHarness.tapAndSettle(tester, find.text('إعدادات الجلسة'));
      // On its own page now; the repeat count is the first stepper on it.
      expect(find.byType(SessionSettingsScreen), findsOneWidget);

      // The first stepper inside the session group is the repeat count.
      // Pumped between taps: the button's callback closes over the value from
      // the frame it was built in, so two taps in one frame both send 4.
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.add).first);

      // Restart the app rather than navigating back: this asserts the choice
      // was persisted, not just held in memory.
      await harness.pumpApp(tester);

      await AppHarness.openReading(tester, find.byType(SurahRow).first);
      await AppHarness.showReadingBar(tester);
      await AppHarness.openSessionSheet(tester);

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
