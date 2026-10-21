import '../entities/ayah_ref.dart';
import '../entities/hifz_plan.dart';
import 'review_scheduler.dart';

/// Cuts a range into daily portions of about equal recitation.
///
/// Pure Dart: each ayah's weight is handed in — the length of its letters,
/// read from the text's search column, a derived value that is never shown
/// (CLAUDE.md A.2 rule 1). Ayahs are never split: a portion is whole ayahs.
class HifzPlanner {
  const HifzPlanner();

  /// Days a plan may run, at most: a ten-year plan is not a plan.
  static const int maxDays = 3650;

  /// [weights] in mushaf order, every ayah of the range once. Returns as
  /// many portions as [days] — fewer only when the range has fewer ayahs,
  /// one ayah a day then — each as near the even share as whole ayahs allow.
  List<Portion> split(List<({AyahRef ref, int weight})> weights, int days) {
    if (weights.isEmpty) {
      throw ArgumentError('A plan needs at least one ayah.');
    }
    if (days < 1) throw ArgumentError('A plan needs at least one day.');
    final int n = weights.length;
    final int portions = days < n ? days : n;

    final List<int> w = <int>[
      for (final ({AyahRef ref, int weight}) x in weights)
        x.weight < 1 ? 1 : x.weight,
    ];
    final int total = w.fold(0, (int a, int b) => a + b);

    final List<Portion> out = <Portion>[];
    int start = 0;
    int done = 0;
    for (int p = 1; p <= portions; p++) {
      if (p == portions) {
        out.add(Portion(weights[start].ref, weights[n - 1].ref));
        break;
      }
      // Where this portion should end, by weight; then the nearer whole-ayah
      // boundary to it — leaving at least one ayah for every portion still
      // to come.
      final double target = total * p / portions;
      int end = start;
      int sum = done + w[start];
      final int lastAllowed = n - (portions - p) - 1;
      while (end < lastAllowed && sum + w[end + 1] <= target) {
        end++;
        sum += w[end];
      }
      if (end < lastAllowed &&
          (target - sum).abs() > (sum + w[end + 1] - target).abs()) {
        end++;
        sum += w[end];
      }
      out.add(Portion(weights[start].ref, weights[end].ref));
      done = sum;
      start = end + 1;
    }
    return List<Portion>.unmodifiable(out);
  }

  HifzPlan plan({
    required List<({AyahRef ref, int weight})> weights,
    required int days,
    required DateTime now,
  }) {
    final List<Portion> portions = split(weights, days.clamp(1, maxDays));
    return HifzPlan(
      from: portions.first.from,
      to: portions.last.to,
      days: days.clamp(1, maxDays),
      started: ReviewScheduler.dayOf(now),
      portions: portions,
    );
  }
}
