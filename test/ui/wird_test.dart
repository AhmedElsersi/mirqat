import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/daily_wird.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/home/screen/home_shell.dart';
import 'package:mirqat/features/today/today_view.dart';
import 'package:mirqat/services/audio/memorization_player_service.dart';

import '../app_harness.dart';
import '../fake_session_player.dart';

/// Today's wird on the home page: set by the reader, kept until they change
/// it, and each part opening the reading view the way it is worked.
void main() {
  late AppHarness harness;
  setUp(() async => harness = await AppHarness.start());
  tearDown(() async => harness.stop());
  tearDownAll(AppHarness.disposeAll);

  Future<AppSettings> stored() async => (await sl<SettingsRepository>().read())
      .getOrElse(() => const AppSettings());

  group('the stored ranges', () {
    test('round-trip, and anything unreadable is simply not set', () {
      const DailyWird wird = <WirdPart, WirdRange>{
        WirdPart.fresh: WirdRange(from: AyahRef(67, 1), to: AyahRef(67, 5)),
        WirdPart.old: WirdRange(from: AyahRef(78, 1), to: AyahRef(114, 6)),
      };
      expect(dailyWirdFromMap(dailyWirdToMap(wird)), wird);
      expect(
        AppSettings.fromMap(const AppSettings(wird: wird).toMap()).wird,
        wird,
      );

      expect(
        dailyWirdFromMap(<String, Object?>{
          'new': <String, Object?>{
            'from': <int>[2, 9],
            'to': <int>[2, 3],
          },
          'recent': 'nonsense',
          'someday': <String, Object?>{
            'from': <int>[1, 1],
            'to': <int>[1, 7],
          },
          'old': <String, Object?>{
            'from': <int>[1, 1],
            'to': <int>[1, 7],
          },
        }),
        <WirdPart, WirdRange>{
          WirdPart.old: const WirdRange(from: AyahRef(1, 1), to: AyahRef(1, 7)),
        },
        reason: 'reversed, malformed and unknown parts are dropped',
      );
      expect(dailyWirdFromMap(null), isEmpty);
    });
  });

  group('the Today tab', () {
    testWidgets('with nothing set it offers to set the wird; a part added and '
        'saved is listed and kept', (WidgetTester tester) async {
      await harness.pumpApp(tester, tab: HomeTab.today);
      expect(find.byType(TodayView), findsOneWidget);
      expect(find.text('ماذا تحفظ اليوم؟'), findsOneWidget);

      await AppHarness.tapAndSettle(tester, find.text('حدّد الوِرد'));
      // The first part is the new portion: switch it on, as it starts.
      await AppHarness.tapAndSettle(tester, find.byType(Switch).first);
      await tester.runAsync(() async {
        await tester.tap(find.text('احفظ'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await AppHarness.settle(tester);

      // Today's new portion is now the page's first card, ready to start.
      expect(
        find.descendant(
          of: find.byType(TodayView),
          matching: find.text('سورة الفاتحة كاملة'),
        ),
        findsOneWidget,
      );
      expect(find.text('ابدأ الحفظ'), findsOneWidget);
      final AppSettings saved = await tester.runAsync(stored) as AppSettings;
      expect(saved.wird.keys, <WirdPart>[WirdPart.fresh]);
      expect(saved.onboardingSeen, isTrue, reason: 'nothing else is lost');
    });

    testWidgets('a part opens the reading view on its range, worked its own '
        'way, with its chip shown chosen', (WidgetTester tester) async {
      await tester.runAsync(
        () => sl<SettingsRepository>().save(
          const AppSettings(
            onboardingSeen: true,
            homeViewMode: HomeViewMode.list,
            wird: <WirdPart, WirdRange>{
              WirdPart.recent: WirdRange(
                from: AyahRef(1, 2),
                to: AyahRef(1, 5),
              ),
            },
          ),
        ),
      );
      await harness.pumpApp(tester, tab: HomeTab.today);
      expect(find.text('مراجعة القريب'), findsOneWidget);

      await AppHarness.openReading(tester, find.byTooltip('ابدأ المراجعة'));
      final SessionCubit session = BlocProvider.of<SessionCubit>(
        tester.element(find.byType(MushafView)),
      );
      await tester.runAsync(() async {
        for (int i = 0; i < 100 && session.state.activePreset == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(session.state.activePreset, 'recent');
      expect(session.state.config!.start, const AyahRef(1, 2));
      expect(session.state.config!.end, const AyahRef(1, 5));
      expect(session.state.config!.repeatCount, 2, reason: 'recent review');

      final FakeSessionPlayer player =
          sl<MemorizationPlayerService>() as FakeSessionPlayer;
      expect(player.loads, hasLength(1), reason: 'it starts at once');
    });
  });
}
