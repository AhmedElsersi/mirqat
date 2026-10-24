import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/widgets/panel.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/daily_wird.dart';
import 'package:mirqat/domain/entities/hifz_plan.dart';
import 'package:mirqat/domain/entities/review_card.dart';
import 'package:mirqat/features/review/cubit/review_cubit.dart';
import 'package:mirqat/features/today/today_view.dart';

import '../fake_review_repository.dart';
import '../localized.dart';
import '../quran_db_fixtures.dart';

/// The Today tab: the new portion first, the two reviews, a suggestion for
/// before sleep or the morning if asked for, what is due, and the plan.
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
    DailyWird wird = const <WirdPart, WirdRange>{},
    DateTime? now,
  }) async {
    Intl.defaultLocale = 'ar';
    addTearDown(() => Intl.defaultLocale = null);
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
    final List<Surah> surahs = (await tester.runAsync(
      () async => (await fixtureRepository().getSurahs()).getOrElse(
        () => const <Surah>[],
      ),
    ))!;
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
                child: TodayView(
                  settings: AppSettings(
                    hifzPlan: plan,
                    bookends: bookends,
                    bookendTaken: bookendTaken,
                    wird: wird,
                  ),
                  surahs: surahs,
                  onWirdChanged: (_, _) async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleLocalization(tester);
  }

  // A due row leads with the ladder; the bookend's and the continue card's
  // rows lead with a tile icon.
  Finder dueRows() => find.byWidgetPredicate(
    (Widget w) => w is ListTile && w.leading is! Icon && w.leading is! TileIcon,
  );

  testWidgets('nothing set and nothing due: one card that asks what to '
      'memorize, and nothing else', (WidgetTester tester) async {
    await pump(tester, 0);
    expect(find.text('ماذا تحفظ اليوم؟'), findsOneWidget);
    expect(find.text('حدّد الوِرد'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a few due: one row each, and nothing overflows at 320 dp',
    (WidgetTester tester) async {
      await pump(tester, 2);
      expect(find.text('حان موعد مراجعته'), findsOneWidget);
      expect(dueRows(), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
    skip:
        true /* RELEASE-1.4(review-ladder): its entry point is commented out */,
  );

  testWidgets(
    'many due: three rows, and the rest a tap away',
    (WidgetTester tester) async {
      await pump(tester, 5);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();
      expect(dueRows(), findsNWidgets(TodayView.shownDue));
      expect(find.text('الكل (٥)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip:
        true /* RELEASE-1.4(review-ladder): its entry point is commented out */,
  );

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

  testWidgets('a plan in hand: its portion is the new portion, with a start '
      'button, and its progress below', (WidgetTester tester) async {
    await pump(tester, 0, plan: plan);
    expect(find.text('ابدأ الحفظ'), findsOneWidget);
    expect(find.text('حفظ اليوم: ١ من ٢'), findsOneWidget);
    expect(find.textContaining('خطة الحفظ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: true /* RELEASE-1.4(hifz-plan): its entry point is commented out */);

  testWidgets('the reader\'s own new portion wins over the plan\'s', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      0,
      plan: plan,
      wird: const <WirdPart, WirdRange>{
        WirdPart.fresh: WirdRange(from: AyahRef(3, 1), to: AyahRef(3, 2)),
      },
    );
    expect(find.text('حفظ اليوم: ١ من ٢'), findsNothing);
    expect(find.textContaining('الآيات ١ - ٢'), findsOneWidget);
    expect(find.text('ابدأ الحفظ'), findsOneWidget);
  });

  testWidgets('a finished plan offers nothing to start', (
    WidgetTester tester,
  ) async {
    await pump(tester, 0, plan: plan.copyWith(completed: 2));
    expect(find.text('ماذا تحفظ اليوم؟'), findsOneWidget);
    expect(find.text('ابدأ الحفظ'), findsNothing);
  });

  group('bedtime and morning', () {
    testWidgets('off, as for every reader who has not chosen it: nothing '
        'added', (WidgetTester tester) async {
      await pump(tester, 2);
      expect(find.byIcon(Icons.wb_twilight), findsNothing);
      expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    });

    testWidgets(
      'on, in the morning: last night\'s portion first — one row, '
      'not a second one beside its review',
      (WidgetTester tester) async {
        await pump(tester, 2, bookends: true);
        expect(find.byIcon(Icons.wb_twilight), findsOneWidget);
        expect(find.text('هذا الصباح'), findsOneWidget);
        // Two cards were due: one is the morning's, one stays a review.
        expect(dueRows(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      skip: true /* RELEASE-1.4(bookends): its entry point is commented out */,
    );

    testWidgets(
      'on, at night: today\'s new portion, to hear once more, even '
      'with nothing due',
      (WidgetTester tester) async {
        // The cards were memorized on 30 November; it is that night.
        await pump(tester, 1, bookends: true, now: DateTime(2026, 11, 30, 22));
        expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
        expect(find.text('قبل النوم'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      skip: true /* RELEASE-1.4(bookends): its entry point is commented out */,
    );

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
