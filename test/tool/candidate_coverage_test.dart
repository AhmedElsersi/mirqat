import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/segment_audit.dart';
import 'package:mirqat/admin/services/segment_planner.dart';

AudioSegment at(int startMs, int endMs) => AudioSegment(
  start: Duration(milliseconds: startMs),
  end: Duration(milliseconds: endMs),
);

/// The aligner can only cut where a pause was found, so a stretch with no
/// pause in it is a stretch that must come out as one segment. Counting
/// candidates hides that: surah 24 had 77 pauses for 64 cuts and still
/// published seventeen minutes of recitation as a single ayah, because all 77
/// sat in the quiet half of the recording.
void main() {
  const Duration total = Duration(seconds: 100);

  test('no candidates at all means the whole recording is one hole', () {
    expect(widestHole(const <AudioSegment>[], total), total);
  });

  test('the lead-in before the first pause counts', () {
    // A recording that only pauses near its end is not well covered.
    expect(
      widestHole(<AudioSegment>[at(90000, 90500)], total),
      const Duration(milliseconds: 90000),
    );
  });

  test('the tail after the last pause counts', () {
    expect(
      widestHole(<AudioSegment>[at(1000, 1500)], total),
      const Duration(milliseconds: 98500),
    );
  });

  test('the widest gap between two pauses is found', () {
    final Duration hole = widestHole(<AudioSegment>[
      at(1000, 1500),
      at(2000, 2500),
      at(60000, 60500), // the 57.5s hole
      at(61000, 61500),
      at(99000, 99500),
    ], total);
    expect(hole, const Duration(milliseconds: 57500));
  });

  test('candidates out of order are still measured correctly', () {
    // detectSilences returns them in order, but the measure must not depend
    // on that — a wrong answer here silently passes a bad split.
    final List<AudioSegment> shuffled = <AudioSegment>[
      at(61000, 61500),
      at(1000, 1500),
      at(99000, 99500),
      at(60000, 60500),
    ];
    // 1.5s -> 60s is the widest of this set.
    expect(widestHole(shuffled, total), const Duration(milliseconds: 58500));
  });

  test('evenly spread pauses leave a small hole', () {
    final List<AudioSegment> even = <AudioSegment>[
      for (int t = 5000; t < 100000; t += 5000) at(t, t + 300),
    ];
    expect(widestHole(even, total).inMilliseconds, lessThanOrEqualTo(5000));
  });
}
