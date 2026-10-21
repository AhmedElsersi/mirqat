import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/domain/engine/hifz_planner.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/hifz_plan.dart';

List<({AyahRef ref, int weight})> ayahs(List<int> weights, {int surah = 2}) =>
    <({AyahRef ref, int weight})>[
      for (int i = 0; i < weights.length; i++)
        (ref: AyahRef(surah, i + 1), weight: weights[i]),
    ];

void main() {
  const HifzPlanner planner = HifzPlanner();

  /// Every ayah of [w], in order, exactly once, across [portions].
  void expectCovers(
    List<Portion> portions,
    List<({AyahRef ref, int weight})> w,
  ) {
    final List<AyahRef> seen = <AyahRef>[];
    for (final Portion p in portions) {
      final int a = w.indexWhere((x) => x.ref == p.from);
      final int b = w.indexWhere((x) => x.ref == p.to);
      expect(a, isNonNegative);
      expect(b, greaterThanOrEqualTo(a), reason: 'a portion is never empty');
      for (int i = a; i <= b; i++) {
        seen.add(w[i].ref);
      }
    }
    expect(seen, w.map((x) => x.ref).toList());
  }

  group('cutting a range into portions', () {
    test('as many portions as days, covering the range once, in order', () {
      final List<({AyahRef ref, int weight})> w = ayahs(
        List<int>.generate(40, (int i) => 20 + (i * 7) % 30),
      );
      final List<Portion> p = planner.split(w, 7);
      expect(p, hasLength(7));
      expectCovers(p, w);
    });

    test('portions come out near the even share of recitation', () {
      final List<({AyahRef ref, int weight})> w = ayahs(
        List<int>.generate(60, (int i) => 30 + (i * 13) % 50),
      );
      final List<Portion> p = planner.split(w, 6);
      final int total = w.fold(0, (int a, x) => a + x.weight);
      final int maxAyah = w
          .map((x) => x.weight)
          .reduce((a, b) => a > b ? a : b);
      for (final Portion portion in p) {
        final int a = w.indexWhere((x) => x.ref == portion.from);
        final int b = w.indexWhere((x) => x.ref == portion.to);
        int sum = 0;
        for (int i = a; i <= b; i++) {
          sum += w[i].weight;
        }
        expect((sum - total / 6).abs(), lessThanOrEqualTo(maxAyah * 1.5));
      }
    });

    test('one very long ayah gets a day to itself', () {
      final List<({AyahRef ref, int weight})> w = ayahs(<int>[
        10,
        10,
        10,
        600,
        10,
        10,
      ]);
      final List<Portion> p = planner.split(w, 3);
      expect(p.any((Portion x) => x.from == x.to && x.from.ayah == 4), isTrue);
      expectCovers(p, w);
    });

    test('fewer ayahs than days: one a day, and no empty days', () {
      final List<({AyahRef ref, int weight})> w = ayahs(<int>[5, 9, 4]);
      final List<Portion> p = planner.split(w, 10);
      expect(p, hasLength(3));
      expect(p.every((Portion x) => x.from == x.to), isTrue);
    });

    test('one day: the whole range', () {
      final List<({AyahRef ref, int weight})> w = ayahs(<int>[5, 9, 4]);
      expect(planner.split(w, 1), <Portion>[
        const Portion(AyahRef(2, 1), AyahRef(2, 3)),
      ]);
    });

    test('a range across surahs is cut across them too', () {
      final List<({AyahRef ref, int weight})> w = <({AyahRef ref, int weight})>[
        ...ayahs(<int>[10, 10], surah: 112),
        ...ayahs(<int>[10, 10], surah: 113),
      ];
      final List<Portion> p = planner.split(w, 2);
      expectCovers(p, w);
      expect(p.first.to, const AyahRef(112, 2));
    });

    test('a weight of nothing still counts as an ayah', () {
      final List<Portion> p = planner.split(ayahs(<int>[0, 0, 0, 0]), 2);
      expect(p, hasLength(2));
    });

    test('nothing to cut, or no days, is refused', () {
      expect(() => planner.split(ayahs(<int>[]), 3), throwsArgumentError);
      expect(() => planner.split(ayahs(<int>[1]), 0), throwsArgumentError);
    });
  });

  group('the plan', () {
    final HifzPlan plan = planner.plan(
      weights: ayahs(List<int>.filled(10, 10)),
      days: 5,
      now: DateTime(2026, 10, 21, 22, 15),
    );

    test('starts today, at the first portion', () {
      expect(plan.started, DateTime(2026, 10, 21));
      expect(plan.current, plan.portions.first);
      expect(plan.from, const AyahRef(2, 1));
      expect(plan.to, const AyahRef(2, 10));
    });

    test('the calendar says which portion should be in hand', () {
      expect(HifzPlanner.expectedPortion(plan, DateTime(2026, 10, 21, 23)), 1);
      expect(HifzPlanner.expectedPortion(plan, DateTime(2026, 10, 23)), 3);
      expect(HifzPlanner.expectedPortion(plan, DateTime(2027, 1, 1)), 5);
    });

    test('done when every portion is', () {
      expect(plan.copyWith(completed: 5).isFinished, isTrue);
      expect(plan.copyWith(completed: 5).current, isNull);
    });

    test('round-trips through storage', () {
      expect(
        HifzPlan.fromMap(plan.copyWith(completed: 2).toMap()),
        plan.copyWith(completed: 2),
      );
    });

    test(
      'a plan that does not hold together is dropped, never half-followed',
      () {
        final Map<String, dynamic> good = plan.toMap();
        final List<List<int>> portions = (good['portions'] as List<List<int>>)
            .toList();
        final List<List<int>> overlapping = <List<int>>[
          ...portions.take(1),
          <int>[2, 1, 2, 4],
          ...portions.skip(2),
        ];
        for (final MapEntry<String, Object?> broken
            in <MapEntry<String, Object?>>[
              MapEntry<String, Object?>('portions', overlapping),
              const MapEntry<String, Object?>('portions', <Object?>[]),
              const MapEntry<String, Object?>('days', 0),
              const MapEntry<String, Object?>('completed', -1),
              const MapEntry<String, Object?>('started', <int>[2026, 10]),
              const MapEntry<String, Object?>('to', <int>[2, 11]),
            ]) {
          expect(
            HifzPlan.fromMap(<String, dynamic>{
              ...good,
              broken.key: broken.value,
            }),
            isNull,
            reason: broken.key,
          );
        }
        expect(HifzPlan.fromMap('plan'), isNull);
      },
    );

    test('more portions done than there are reads as all of them', () {
      final HifzPlan? p = HifzPlan.fromMap(<String, dynamic>{
        ...plan.toMap(),
        'completed': 99,
      });
      expect(p!.completed, 5);
    });
  });
}
