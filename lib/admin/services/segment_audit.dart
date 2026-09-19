import 'dart:math';

import 'segment_planner.dart';

/// Segments whose length their text cannot explain.
///
/// Length is fitted against letter-units across the surah — a pause per ayah
/// plus time per unit, refitted once without the wildest points so that the
/// faults being looked for do not set the standard they are judged by. A clip
/// under 45% of what its words need, or over 2.2 times, is reported, by index.
///
/// This is the one definition of "out of line" in the project. The splitter
/// uses it to decide whether a cut is good enough, the admin screen uses it to
/// mark the rows worth listening to, and `tool/audit_audio.py` applies the
/// same arithmetic to published files — so a surah cannot pass one and fail
/// another.
List<int> suspectSegments(List<double> durations, List<int> weights) {
  if (durations.length != weights.length || durations.length < 2) {
    return const <int>[];
  }

  (double, double) fit(List<int> xs, List<double> ys) {
    final double meanX = xs.reduce((int a, int b) => a + b) / xs.length;
    final double meanY = ys.reduce((double a, double b) => a + b) / ys.length;
    double sxx = 0;
    double sxy = 0;
    for (int i = 0; i < xs.length; i++) {
      sxx += (xs[i] - meanX) * (xs[i] - meanX);
      sxy += (xs[i] - meanX) * (ys[i] - meanY);
    }
    final double slope = sxx == 0 ? 0 : sxy / sxx;
    return (meanY - slope * meanX, slope);
  }

  (double, double) line = fit(weights, durations);
  if (durations.length >= 8) {
    final List<double> residuals = <double>[
      for (int i = 0; i < durations.length; i++)
        durations[i] - (line.$1 + line.$2 * weights[i]),
    ];
    final double spread = sqrt(
      residuals.fold<double>(0, (double a, double r) => a + r * r) /
          residuals.length,
    );
    final List<int> keep = <int>[
      for (int i = 0; i < residuals.length; i++)
        if (residuals[i].abs() <= 2.5 * spread) i,
    ];
    if (keep.length >= 6) {
      line = fit(
        <int>[for (final int i in keep) weights[i]],
        <double>[for (final int i in keep) durations[i]],
      );
    }
  }

  return <int>[
    for (int i = 0; i < durations.length; i++)
      if (_outOfLine(durations[i], max(line.$1 + line.$2 * weights[i], 0.8))) i,
  ];
}

bool _outOfLine(double actual, double expected) =>
    (actual < 0.45 * expected && expected - actual > 1.5) ||
    (actual > 2.2 * expected && actual - expected > 8);

/// [suspectSegments] for a list of cut segments.
List<int> suspectsIn(List<AudioSegment> segments, List<int> weights) =>
    suspectSegments(<double>[
      for (final AudioSegment s in segments) s.duration.inMilliseconds / 1000,
    ], weights);

/// The widest stretch of the recording with no candidate pause in it.
///
/// This is the number that decides whether a split can work at all. The
/// aligner can only cut where a pause was found, so a hole this wide is a
/// stretch it has to emit as one segment no matter what the text says.
Duration widestHole(List<AudioSegment> candidates, Duration total) {
  if (candidates.isEmpty) return total;
  final List<AudioSegment> sorted = <AudioSegment>[...candidates]
    ..sort((AudioSegment a, AudioSegment b) => a.start.compareTo(b.start));

  Duration widest = sorted.first.start;
  for (int i = 1; i < sorted.length; i++) {
    final Duration gap = sorted[i].start - sorted[i - 1].end;
    if (gap > widest) widest = gap;
  }
  final Duration tail = total - sorted.last.end;
  return tail > widest ? tail : widest;
}
