import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/data/repositories/practice_repository.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/domain/entities/practice_stats.dart';
import 'package:mirqat/features/stats/cubit/stats_cubit.dart';
import 'package:mirqat/features/stats/screen/stats_screen.dart';

import '../localized.dart';

class _Practice implements PracticeRepository {
  @override
  Future<Either<Failure, Map<DateTime, PracticeDay>>> all() async =>
      Right<Failure, Map<DateTime, PracticeDay>>(<DateTime, PracticeDay>{
        DateTime(2026, 11, 1): const PracticeDay(plays: 30, seconds: 900),
        DateTime(2026, 11, 2): const PracticeDay(plays: 12, seconds: 300),
      });

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Progress implements ProgressRepository {
  @override
  Future<Either<Failure, int>> memorizedCount() async =>
      const Right<Failure, int>(17);

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  setUpAll(ensureTestLocalization);

  setUp(() {
    GetIt.instance.registerFactory<StatsCubit>(
      () => StatsCubit(
        practiceRepository: _Practice(),
        progressRepository: _Progress(),
      ),
    );
  });
  tearDown(() => GetIt.instance.reset());

  for (final Locale locale in AppLocalization.supportedLocales) {
    testWidgets('lays out at 320 dp, in ${locale.languageCode}', (
      WidgetTester tester,
    ) async {
      // As the app's root does: numerals follow the locale.
      Intl.defaultLocale = locale.toString();
      addTearDown(() => Intl.defaultLocale = null);
      tester.view.physicalSize = const Size(320, 640);
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
              home: const StatsScreen(),
            ),
          ),
          locale: locale,
        ),
      );
      await settleLocalization(tester);
      expect(tester.takeException(), isNull);
      // Two days, twenty minutes, the seventeen memorized.
      final bool ar = locale.languageCode == 'ar';
      expect(find.text(ar ? '٢' : '2'), findsOneWidget);
      expect(find.text(ar ? '٢٠' : '20'), findsOneWidget);
      expect(find.text(ar ? '١٧' : '17'), findsOneWidget);
      // Nothing that marks a day not practised.
      expect(find.byIcon(Icons.circle_outlined), findsNothing);
    });
  }
}
