import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/features/surah_list/screen/surah_list_screen.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';
import 'package:mirqat/core/localization/locale_keys.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/reading_position.dart';
import 'package:mirqat/data/repositories/reading_history_repository.dart';
import 'package:mirqat/features/history/screen/history_screen.dart';
import 'package:mirqat/features/home/widgets/juz_widgets.dart';
import 'package:mirqat/features/mushaf/cubit/mushaf_cubit.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../app_harness.dart';

void main() {
  late AppHarness harness;

  setUp(() async => harness = await AppHarness.start());

  Future<void> remember(WidgetTester tester, int page, {int surah = 2}) =>
      tester.runAsync(
        () => sl<ReadingHistoryRepository>().record(
          ReadingPosition(
            surahNumber: surah,
            ayahNumber: 1,
            page: page,
            at: DateTime.now(),
          ),
        ),
      );

  group('the reading mark', () {
    testWidgets('is where "continue reading" goes while it is set, and the '
        'remembered page again when it is cleared', (
      WidgetTester tester,
    ) async {
      await remember(tester, 2);
      await harness.pumpApp(tester);
      expect(find.text(LocaleKeys.homeContinueReading.tr()), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_added), findsNothing);

      final SettingsCubit settings = BlocProvider.of<SettingsCubit>(
        tester.element(find.byType(SurahListScreen)),
      );
      await tester.runAsync(
        () => settings.markReading(
          ReadingPosition(
            surahNumber: 1,
            ayahNumber: 3,
            page: 1,
            at: DateTime(2026, 9, 30),
          ),
        ),
      );
      await AppHarness.settle(tester);
      // Still one card, now the mark's: the icon says so, and the place
      // is the marked ayah rather than the remembered page.
      expect(find.text(LocaleKeys.homeContinueReading.tr()), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_added), findsOneWidget);
      expect(find.byIcon(Icons.bookmark), findsNothing);
      expect(find.textContaining('٣'), findsWidgets);

      await tester.runAsync(settings.clearReadingMark);
      await AppHarness.settle(tester);
      expect(find.text(LocaleKeys.homeContinueReading.tr()), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_added), findsNothing);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
    });
  });

  group('the home bar', () {
    testWidgets('carries the way back and the settings, and nothing about '
        'how the list is drawn', (WidgetTester tester) async {
      await harness.pumpApp(tester);

      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      // List, grid or mushaf is chosen once, in Settings.
      expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
      expect(find.byIcon(Icons.view_list_outlined), findsNothing);
      expect(find.byIcon(Icons.auto_stories_outlined), findsNothing);
    });

    testWidgets('has two tabs, and a swipe moves between them', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      expect(find.byType(Tab), findsNWidgets(2));
      expect(find.byType(SurahRow), findsWidgets);
      expect(find.byType(JuzRow), findsNothing);

      await AppHarness.swipeToAjzaa(tester);
      expect(find.byType(JuzRow), findsWidgets);
    });

    testWidgets('lists all thirty ajzaa', (WidgetTester tester) async {
      await harness.pumpApp(tester);
      await AppHarness.swipeToAjzaa(tester);

      final ListView list = tester.widget<ListView>(
        find.ancestor(
          of: find.byType(JuzRow).first,
          matching: find.byType(ListView),
        ),
      );
      expect(list.childrenDelegate.estimatedChildCount, 30 * 2 - 1);
    });

    testWidgets('the ajzaa follow the grid setting too', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.setHomeView(tester, HomeViewMode.grid);
      await AppHarness.swipeToAjzaa(tester);

      expect(find.byType(JuzTile), findsWidgets);
      expect(find.byType(JuzRow), findsNothing);
    });
  });

  group('where you left off', () {
    testWidgets('nothing read yet: no "continue" card', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      expect(find.byIcon(Icons.bookmark), findsNothing);
    });

    testWidgets('list view: opens on the list, with the last place one tap '
        'away', (WidgetTester tester) async {
      await remember(tester, 50, surah: 3);
      await harness.pumpApp(tester);

      // The list, not the mushaf.
      expect(find.byType(MushafView), findsNothing);
      expect(find.byType(SurahRow), findsWidgets);
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.bookmark));
        await tester.pump();
        await tester.pump();
      });
      final MushafCubit cubit = BlocProvider.of<MushafCubit>(
        tester.element(find.byType(MushafView)),
      );
      expect(cubit.state.initialPage, 50);
    });

    testWidgets('choosing the mushaf view does not throw the mushaf open over '
        'whatever is on screen', (WidgetTester tester) async {
      // It decides how the app *opens*. Re-deciding whenever the setting
      // changed opened the mushaf on top of the Settings screen.
      await harness.pumpApp(tester);
      await AppHarness.setHomeView(tester, HomeViewMode.mushaf);

      expect(find.byType(MushafView), findsNothing);
      expect(find.byType(SurahRow), findsWidgets);
    });
  });

  group('history', () {
    testWidgets('lists the places read, newest first', (
      WidgetTester tester,
    ) async {
      await remember(tester, 3);
      await remember(tester, 282, surah: 18);
      await harness.pumpApp(tester);

      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.history));

      expect(find.byType(HistoryScreen), findsOneWidget);
      final List<PlaceTile> tiles = tester
          .widgetList<PlaceTile>(find.byType(PlaceTile))
          .toList();
      expect(tiles.map((PlaceTile t) => t.place.position.page), <int>[282, 3]);
    });

    testWidgets('writes the time in the numerals the rest of the app uses', (
      WidgetTester tester,
    ) async {
      await remember(tester, 3);
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.history));

      // Plain `ar` formats a time as 12:59; the screen around it says ٢٢.
      final BuildContext context = tester.element(find.byType(PlaceTile));
      final String label = PlaceTile.whenLabel(
        context,
        DateTime(2026, 9, 20, 12, 59),
      );
      expect(label, isNot(matches(RegExp('[0-9]'))), reason: label);
      expect(label, contains('١٢:٥٩'));
    });

    testWidgets('says so when there is nothing yet', (
      WidgetTester tester,
    ) async {
      await harness.pumpApp(tester);
      await AppHarness.tapAndSettle(tester, find.byIcon(Icons.history));

      expect(find.byType(PlaceTile), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });
}
