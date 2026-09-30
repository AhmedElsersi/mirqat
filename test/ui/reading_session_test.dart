import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/reciter_avatar.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/core/widgets/ayah_text.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/features/home/widgets/juz_widgets.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_page.dart';
import 'package:mirqat/features/mushaf/reading_section.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/mushaf/widgets/ayah_actions_sheet.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/session/cubit/session_state.dart';
import 'package:mirqat/features/session/widgets/session_bar.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/services/audio/memorization_player_service.dart';

import '../app_harness.dart';
import '../fake_session_player.dart';

/// The session, played over the text it is memorising: there is no player
/// screen any more, so everything that screen did is checked here, on the
/// reading view. Al-Fatiha throughout — the one surah the tests' CDN offers.
void main() {
  late AppHarness harness;
  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  FakeSessionPlayer player() =>
      sl<MemorizationPlayerService>() as FakeSessionPlayer;

  SessionCubit sessionOf(WidgetTester tester) =>
      BlocProvider.of<SessionCubit>(tester.element(find.byType(MushafView)));

  Future<MushafCubit> openFatiha(WidgetTester tester) async {
    await harness.pumpApp(tester);
    final MushafCubit cubit = await AppHarness.openReading(
      tester,
      find.byType(SurahRow).first,
    );
    await AppHarness.showReadingBar(tester);
    return cubit;
  }

  Future<void> pressStart(WidgetTester tester) => AppHarness.tapAndRun(
    tester,
    find.descendant(
      of: find.byType(SessionBar),
      matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
    ),
  );

  /// The player reaching [unit], and the frames it takes the page to react.
  Future<void> reach(WidgetTester tester, PlaybackUnit unit) async {
    await tester.runAsync(() async {
      player().reach(unit);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await AppHarness.frames(tester, 300);
  }

  List<AyahText> tinted(WidgetTester tester, WordTint tint) => tester
      .widgetList<AyahText>(find.byType(AyahText))
      .where((AyahText w) => w.tint == tint)
      .toList();

  group('playing over the text', () {
    testWidgets('start turns the bar into the session\'s controls, with no '
        'other screen in the way', (WidgetTester tester) async {
      await openFatiha(tester);
      await pressStart(tester);

      expect(find.byType(MushafScreen), findsOneWidget);
      expect(player().loads, hasLength(1));
      expect(player().loads.single.plan.config.surahNumber, 1);
      expect(player().loads.single.plan.config.endAyah, 7);
      expect(player().playCalls, 1);

      expect(find.byIcon(Icons.pause), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('the ayah being recited is marked on the page, and the bar '
        'counts its repeats', (WidgetTester tester) async {
      final MushafCubit cubit = await openFatiha(tester);
      await pressStart(tester);
      final SessionPlan plan = player().loads.single.plan;

      // The second time through ayah 3.
      final PlaybackUnit unit = plan.units.firstWhere(
        (PlaybackUnit u) => u.ayahNumber == 3 && u.repeatIndex == 2,
      );
      await reach(tester, unit);

      expect(cubit.state.highlighted, const AyahRef(1, 3));
      expect(tinted(tester, WordTint.highlighted), isNotEmpty);
      // And nothing else: a page washed end to end says nothing.
      expect(tinted(tester, WordTint.ranged), isEmpty);
      expect(find.textContaining('التكرار ٢ من ٣'), findsOneWidget);
      expect(find.text('سورة الفاتحة · الآية ٣'), findsOneWidget);
    });

    testWidgets('the step buttons and pause reach the player', (
      WidgetTester tester,
    ) async {
      await openFatiha(tester);
      await pressStart(tester);

      // In Arabic "next" is the glyph that points left.
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.skip_previous));
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.skip_next));
      expect(player().skips, <int>[1, -1]);

      await AppHarness.tapAndRun(tester, find.byIcon(Icons.pause));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('stop ends the session and the bar offers a start again', (
      WidgetTester tester,
    ) async {
      final MushafCubit cubit = await openFatiha(tester);
      await pressStart(tester);
      await reach(tester, player().loads.single.plan.units.first);

      await AppHarness.tapAndRun(tester, find.byIcon(Icons.stop));

      expect(player().ended, 1);
      expect(sessionOf(tester).state.phase, SessionPhase.idle);
      expect(cubit.state.highlighted, isNull);
      expect(find.text('ابدأ'), findsOneWidget);
    });

    testWidgets('a source that will not open says so in the bar, in Arabic, '
        'and offers to try again', (WidgetTester tester) async {
      await openFatiha(tester);
      player().failOnPlay = true;
      await pressStart(tester);

      expect(sessionOf(tester).state.phase, SessionPhase.failed);
      expect(find.textContaining('Source error'), findsNothing);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('the reciter field', () {
    testWidgets('is a dropdown that shows the portrait and both names, and '
        'lists everyone the same way', (WidgetTester tester) async {
      await openFatiha(tester);
      await AppHarness.openSessionSheet(tester);

      final Finder field = find.byType(DropdownButton<String>);
      expect(field, findsOneWidget);
      // The field writes the Arabic name over the English one.
      expect(
        find.descendant(of: field, matching: find.text('أحمد خليل شاهين')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.text('Ahmed Khalil Shaheen')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: field, matching: find.byType(ReciterAvatar)),
        findsOneWidget,
      );
      // No list of radio rows to scroll past any more.
      expect(find.byType(RadioListTile<String>), findsNothing);

      await tester.tap(field);
      await AppHarness.frames(tester, 400);
      // The menu draws the entry the same way: both names, once more.
      expect(find.text('Ahmed Khalil Shaheen'), findsNWidgets(2));
      expect(find.text('أحمد خليل شاهين'), findsNWidgets(2));
      await tester.tap(find.text('أحمد خليل شاهين').last);
      await AppHarness.frames(tester, 400);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('choosing from the page', () {
    Future<void> longPressFirstWord(WidgetTester tester) async {
      final AyahText word = tester
          .widgetList<AyahText>(find.byType(AyahText))
          .firstWhere((AyahText w) => !w.isMarker);
      await tester.longPress(find.byWidget(word));
      await AppHarness.frames(tester, 400);
    }

    testWidgets('a long press offers to listen, to memorize, and to mark the '
        'range — and nothing is "coming soon"', (WidgetTester tester) async {
      await openFatiha(tester);
      await longPressFirstWord(tester);

      final AyahActionsSheet sheet = tester.widget(
        find.byType(AyahActionsSheet),
      );
      expect(sheet.ayah, const AyahRef(1, 1));
      expect(sheet.canPlay, isTrue);
      // Mark, listen, memorize, range start, range end.
      expect(find.byType(ListTile), findsNWidgets(5));
      expect(
        tester
            .widgetList<ListTile>(find.byType(ListTile))
            .every((ListTile t) => t.enabled && t.onTap != null),
        isTrue,
      );
      expect(find.text('قريبًا'), findsNothing);
    });

    testWidgets('"this ayah alone" starts a session over exactly that ayah', (
      WidgetTester tester,
    ) async {
      await openFatiha(tester);
      await longPressFirstWord(tester);
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.repeat_one));

      expect(find.byType(AyahActionsSheet), findsNothing);
      final SessionPlan plan = player().loads.single.plan;
      expect(plan.config.start, const AyahRef(1, 1));
      expect(plan.config.end, const AyahRef(1, 1));
    });

    testWidgets('marking the end of the range starts nothing, tints the range '
        'and tells the bar', (WidgetTester tester) async {
      await openFatiha(tester);
      await longPressFirstWord(tester);
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.last_page));

      expect(player().loads, isEmpty);
      final SessionState state = sessionOf(tester).state;
      expect(state.rangeChosen, isTrue);
      expect(state.config!.end, const AyahRef(1, 1));
      expect(tinted(tester, WordTint.ranged), isNotEmpty);
      expect(find.text('سورة الفاتحة · الآية ١'), findsOneWidget);

      // And a chosen range can be given back to the page.
      await longPressFirstWord(tester);
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.clear));
      expect(sessionOf(tester).state.rangeChosen, isFalse);
      expect(find.text('سورة الفاتحة كاملة'), findsOneWidget);
    });
  });

  group('settings changed under a running session', () {
    testWidgets('are not left hanging: putting the sheet away asks what to do '
        'with them', (WidgetTester tester) async {
      await openFatiha(tester);
      await pressStart(tester);
      final SessionPlan before = player().loads.single.plan;
      await reach(
        tester,
        before.units.firstWhere((PlaybackUnit u) => u.ayahNumber == 4),
      );

      await AppHarness.openSessionSheet(tester);
      // Steppers, in order: from ayah, to ayah, repeat count.
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.add).at(2));
      expect(player().loads, hasLength(1), reason: 'nothing happens unasked');
      expect(find.text('أكمل من الآية الحالية'), findsOneWidget);

      await AppHarness.tapAndRun(tester, find.text('أكمل من الآية الحالية'));

      expect(player().loads, hasLength(2));
      final SessionLoad resumed = player().loads.last;
      expect(resumed.plan.config.repeatCount, before.config.repeatCount + 1);
      expect(resumed.plan.units[resumed.startAtUnit].ayahNumber, 4);
      expect(sessionOf(tester).state.hasPendingChange, isFalse);
      // Answered once is answered: the question is not asked again behind
      // the sheet as it closes.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    });

    testWidgets('closing the sheet without choosing brings the question up, '
        'and the changes can be dropped', (WidgetTester tester) async {
      await openFatiha(tester);
      await pressStart(tester);
      final int repeats = player().loads.single.plan.config.repeatCount;

      await AppHarness.openSessionSheet(tester);
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.add).at(2));
      await AppHarness.tapAndRun(tester, find.byIcon(Icons.close));

      expect(find.byType(AlertDialog), findsOneWidget);
      await AppHarness.tapAndRun(tester, find.text('تجاهل التغييرات'));

      expect(find.byType(AlertDialog), findsNothing);
      expect(player().loads, hasLength(1));
      expect(sessionOf(tester).state.config!.repeatCount, repeats);
    });

    testWidgets('speed needs no question', (WidgetTester tester) async {
      await openFatiha(tester);
      await pressStart(tester);

      sessionOf(tester).setPlaybackSpeed(1.25);
      await AppHarness.frames(tester, 100);

      expect(player().speeds, <double>[1.25]);
      expect(sessionOf(tester).state.hasPendingChange, isFalse);
    });
  });

  group('following the recitation', () {
    testWidgets('turning the page away offers the way back, and taking it '
        'returns to the ayah', (WidgetTester tester) async {
      // The first juz, so that there is a second page to turn to.
      await harness.pumpApp(tester);
      await AppHarness.swipeToAjzaa(tester);
      final MushafCubit cubit = await AppHarness.openReading(
        tester,
        find.byType(JuzRow).first,
      );
      expect(cubit.state.section?.request, const SectionRequest.juz(1));
      // Every page the turn can show, built where real I/O completes.
      await tester.runAsync(() async {
        await cubit.ensurePage(2);
        await cubit.ensurePage(3);
      });

      await AppHarness.showReadingBar(tester);
      await pressStart(tester);
      await reach(tester, player().loads.single.plan.units.first);
      expect(find.text('العودة إلى الآية'), findsNothing);

      await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
      await AppHarness.frames(tester);
      expect(cubit.state.currentPage, 2);
      expect(find.text('العودة إلى الآية'), findsOneWidget);

      // The recitation moving on does not drag the reader back …
      await reach(tester, player().loads.single.plan.units[1]);
      expect(cubit.state.currentPage, 2);

      // … the chip does.
      await AppHarness.tapAndRun(tester, find.text('العودة إلى الآية'));
      await AppHarness.frames(tester);
      expect(cubit.state.currentPage, 1);
      expect(find.text('العودة إلى الآية'), findsNothing);
    });
  });

  group('one surah at a time', () {
    testWidgets('ends on a leaf that leads to the next surah and the one '
        'before', (WidgetTester tester) async {
      final MushafCubit cubit = await openFatiha(tester);
      expect(cubit.state.visiblePageCount, 1);
      expect(find.byType(MushafPageView), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(300, 0), 1500);
      // Long enough for the turn to come to rest: a pager takes no taps
      // while it is still moving.
      await AppHarness.frames(tester, 2000);

      // First surah: a next, and no previous. By their words, not their
      // arrows — the bar's back button is an arrow too.
      expect(find.textContaining('التالي'), findsOneWidget);
      expect(find.textContaining('السابق'), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.textContaining('التالي'));
        await tester.pump();
        for (int i = 0; i < 300; i++) {
          if (cubit.state.section?.number == 2 &&
              cubit.state.pages.containsKey(cubit.state.currentPage)) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await AppHarness.frames(tester);

      expect(cubit.state.section?.request, const SectionRequest.surah(2));
      expect(cubit.state.currentPage, cubit.state.firstPage);
      expect(tester.takeException(), isNull);
    });
  });
}
