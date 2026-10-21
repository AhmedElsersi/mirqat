import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/hifz_plan.dart';
import 'package:mirqat/domain/entities/review_card.dart';
import 'package:mirqat/features/review/cubit/review_cubit.dart';
import 'package:mirqat/features/review/widgets/review_widgets.dart';

import '../fake_review_repository.dart';
import '../localized.dart';
import '../quran_db_fixtures.dart';

void main() {
  setUpAll(ensureTestLocalization);

  late FakeReviewRepository reviews;
  late ReviewCubit cubit;

  Future<void> pump(
    WidgetTester tester,
    int dueCards, {
    HifzPlan? plan,
    bool bookends = false,
    String? bookendTaken,
    DateTime? now,
  }) async {
    reviews = FakeReviewRepository();
    for (int i = 1; i <= dueCards; i++) {
      final int surah = (i - 1) % 3 + 1;
      final int ayah = (i - 1) ~/ 3 + 1;
      await reviews.save(
        ReviewCard(
          from: AyahRef(surah, ayah),
          to: AyahRef(surah, ayah),
          step: 0,
          due: DateTime(2026, 12, 1),
          created: DateTime(2026, 11, 30),
        ),
      );
    }
    cubit = ReviewCubit(
      quranRepository: fixtureRepository(),
      reviewRepository: reviews,
      clock: () => now ?? DateTime(2026, 12, 1, 9),
    );
    addTearDown(cubit.close);
    await tester.runAsync(cubit.load);
    tester.view.physicalSize = const Size(320, 700);
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
              body: BlocProvider<ReviewCubit>.value(
                value: cubit,
                child: Column(
                  children: <Widget>[
                    TodayCard(
                      plan: plan,
                      bookends: bookends,
                      bookendTaken: bookendTaken,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleLocalization(tester);
  }

  testWidgets('nothing due: not drawn at all', (WidgetTester tester) async {
    await pump(tester, 0);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(Material).evaluate().length, lessThan(3));
  });

  testWidgets('a few due: one row each, and nothing overflows at 320 dp', (
    WidgetTester tester,
  ) async {
    await pump(tester, 2);
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.byType(TierChip), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('many due: three rows, and the rest counted', (
    WidgetTester tester,
  ) async {
    await pump(tester, 5);
    expect(find.byType(ListTile), findsNWidgets(TodayCard.shown));
    expect(find.textContaining('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  final HifzPlan plan = HifzPlan(
    from: const AyahRef(1, 1),
    to: const AyahRef(2, 3),
    days: 2,
    started: DateTime(2026, 12, 1),
    portions: const <Portion>[
      Portion(AyahRef(1, 1), AyahRef(1, 3)),
      Portion(AyahRef(2, 1), AyahRef(2, 3)),
    ],
  );

  testWidgets('a plan in hand: its portion shows, even with nothing due', (
    WidgetTester tester,
  ) async {
    await pump(tester, 0, plan: plan);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.byIcon(Icons.today), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the portion first, then the reviews', (
    WidgetTester tester,
  ) async {
    await pump(tester, 2, plan: plan);
    final List<ListTile> rows = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .toList();
    expect(rows, hasLength(3));
    expect((rows.first.leading! as Icon).icon, Icons.today);
  });

  testWidgets('a finished plan adds nothing', (WidgetTester tester) async {
    await pump(tester, 0, plan: plan.copyWith(completed: 2));
    expect(find.byType(ListTile), findsNothing);
  });

  group('bedtime and morning', () {
    testWidgets('off, as for every reader who has not chosen it: nothing '
        'added', (WidgetTester tester) async {
      await pump(tester, 2);
      expect(find.byIcon(Icons.wb_twilight), findsNothing);
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    });

    testWidgets('on, in the morning: last night\'s portion first — one row, '
        'not a second one beside its review', (WidgetTester tester) async {
      await pump(tester, 2, bookends: true);
      expect(find.byIcon(Icons.wb_twilight), findsOneWidget);
      expect(find.text('هذا الصباح: اقرأه من حفظك'), findsOneWidget);
      // Two cards were due: one is the morning's, one stays a review.
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(find.byType(TierChip), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on, at night: today\'s new portion, to hear once more, even '
        'with nothing due', (WidgetTester tester) async {
      // The cards were memorized on 30 November; it is that night.
      await pump(tester, 1, bookends: true, now: DateTime(2026, 11, 30, 22));
      expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
      expect(find.text('قبل النوم: استمع إليه مرة أخرى'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('taken up, it is gone', (WidgetTester tester) async {
      await pump(
        tester,
        1,
        bookends: true,
        now: DateTime(2026, 11, 30, 22),
        bookendTaken: 'night:1:1-1:1:2026-11-30',
      );
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    });
  });
}
