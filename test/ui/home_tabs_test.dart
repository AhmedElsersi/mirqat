import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/features/my_hifz/cubit/my_hifz_cubit.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/features/home/screen/home_shell.dart';
import 'package:mirqat/features/my_hifz/my_hifz_view.dart';
import 'package:mirqat/features/settings/screen/settings_screen.dart';
import 'package:mirqat/features/surah_list/screen/surah_list_screen.dart';
import 'package:mirqat/features/today/today_view.dart';

import '../app_harness.dart';

/// The home's four tabs: Today first, and each a tap from the others.
void main() {
  late AppHarness harness;
  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  testWidgets('the app opens on Today, and each tab is a tap away', (
    WidgetTester tester,
  ) async {
    await harness.pumpApp(tester, tab: null);
    expect(find.byType(TodayView), findsOneWidget);

    await AppHarness.openTab(tester, HomeTab.mushaf);
    expect(find.byType(SurahListScreen), findsOneWidget);
    expect(find.byType(TodayView), findsNothing, reason: 'kept, not shown');

    await AppHarness.openTab(tester, HomeTab.hifz);
    expect(find.byType(MyHifzView), findsOneWidget);

    await AppHarness.openTab(tester, HomeTab.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('My hifz counts what is memorized, and maps it by juz', (
    WidgetTester tester,
  ) async {
    await harness.pumpApp(tester, tab: HomeTab.hifz);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await AppHarness.settle(tester);
    expect(find.text('آيات علّمتها محفوظة'), findsOneWidget);
    expect(find.text('٠'), findsWidgets);

    final MyHifzCubit cubit = BlocProvider.of<MyHifzCubit>(
      tester.element(find.byType(MyHifzView)),
    );
    // The cubit reloads on every progress change; here the reload is run
    // where its reads complete, not under the test's fake clock.
    await tester.runAsync(() async {
      await sl<ProgressRepository>().setStatus(
        1,
        1,
        MemorizationStatus.memorized,
      );
      await cubit.load();
    });
    await AppHarness.settle(tester);
    expect(cubit.state.juzShares, hasLength(30));
    expect(cubit.state.juzShares.first, greaterThan(0));
    expect(cubit.state.juzShares.skip(1).every((double s) => s == 0), isTrue);
    expect(
      find.descendant(of: find.byType(MyHifzView), matching: find.text('١')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
