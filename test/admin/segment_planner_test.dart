import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/publish_guard.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/data/models/surah.dart';

/// Al-Fatiha: the basmala **is** ayah 1, so seven segments is the whole surah.
const Surah fatiha = Surah(
  number: 1,
  nameAr: 'الفاتحة',
  nameEn: 'Al-Fatiha',
  ayahCount: 7,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.countedAsAyah1,
);

/// Al-Ikhlas: the basmala precedes ayah 1, so five segments for four ayahs.
const Surah ikhlas = Surah(
  number: 112,
  nameAr: 'الإخلاص',
  nameEn: 'Al-Ikhlas',
  ayahCount: 4,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

/// At-Tawba: no basmala at all.
const Surah tawba = Surah(
  number: 9,
  nameAr: 'التوبة',
  nameEn: 'At-Tawba',
  ayahCount: 129,
  revelationPlace: RevelationPlace.madinah,
  bismillahMode: BismillahMode.none,
);

List<AudioSegment> segments(int count) => <AudioSegment>[
  for (int i = 0; i < count; i++)
    AudioSegment(
      start: Duration(seconds: i * 5),
      end: Duration(seconds: (i + 1) * 5),
    ),
];

void main() {
  group('what a surah should split into', () {
    test(
      'a separate-basmala surah expects one segment more than its ayahs',
      () {
        final SegmentPlan plan = SegmentPlan(
          surah: ikhlas,
          segments: segments(5),
        );

        expect(plan.expectsBasmala, isTrue);
        expect(plan.expectedCount, 5);
        expect(plan.countMatches, isTrue);

        // Segment 0 is the basmala and exports as 112000; the ayahs shift by
        // one behind it.
        final List<PlannedSegment> planned = plan.planned;
        expect(planned.first.isBasmala, isTrue);
        expect(planned.first.ayahNumber, 0);
        expect(planned[1].ayahNumber, 1);
        expect(planned.last.ayahNumber, 4);
        expect(
          plan.ayahNumberFor(0),
          isNull,
          reason: 'the basmala is not an ayah',
        );
        expect(plan.ayahNumberFor(1), 1);
      },
    );

    test('Al-Fatiha expects exactly its ayah count, basmala inside ayah 1', () {
      final SegmentPlan plan = SegmentPlan(
        surah: fatiha,
        segments: segments(7),
      );

      expect(plan.expectsBasmala, isFalse);
      expect(plan.expectedCount, 7);
      expect(plan.countMatches, isTrue);
      expect(plan.planned.first.isBasmala, isFalse);
      expect(plan.planned.first.ayahNumber, 1);
      expect(plan.ayahNumberFor(0), 1);
    });

    test('At-Tawba expects exactly its ayah count, with no basmala', () {
      final SegmentPlan plan = SegmentPlan(
        surah: tawba,
        segments: segments(129),
      );

      expect(plan.expectsBasmala, isFalse);
      expect(plan.expectedCount, 129);
      expect(plan.planned.first.ayahNumber, 1);
      expect(plan.planned.last.ayahNumber, 129);
    });

    test(
      'a separate-basmala surah split as though it had none is a mismatch',
      () {
        final SegmentPlan plan = SegmentPlan(
          surah: ikhlas,
          segments: segments(4),
        );

        expect(plan.countMatches, isFalse);
        expect(plan.expectedCount, 5);
        expect(plan.actualCount, 4);
      },
    );
  });

  group('editing a split', () {
    test('dropping a segment renumbers everything after it', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(6),
      ).removing(2);

      expect(plan.actualCount, 5);
      expect(plan.countMatches, isTrue);
      expect(plan.planned[2].ayahNumber, 2);
    });

    test('splitting a segment adds one, and the halves meet exactly', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(4),
      ).splitting(1, const Duration(seconds: 7));

      expect(plan.actualCount, 5);
      expect(plan.segments[1].end, const Duration(seconds: 7));
      expect(plan.segments[2].start, const Duration(seconds: 7));
    });

    test('a split lands at the quietest moment, not at the midpoint', () {
      // One segment holding two ayahs with a real gap at 6–7 s. Halving it
      // would cut at 5 s, inside a word.
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: const <AudioSegment>[
          AudioSegment(start: Duration.zero, end: Duration(seconds: 10)),
        ],
      );

      final Duration? cut = plan.bestCutFor(0, const <AudioSegment>[
        AudioSegment(
          start: Duration(milliseconds: 2400),
          end: Duration(milliseconds: 2600),
        ),
        AudioSegment(start: Duration(seconds: 6), end: Duration(seconds: 7)),
      ]);

      expect(cut, const Duration(milliseconds: 6500));
    });

    test('a candidate too close to an edge is not a cut', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: const <AudioSegment>[
          AudioSegment(start: Duration.zero, end: Duration(seconds: 10)),
        ],
      );

      // 100 ms in would leave a sliver, not an ayah.
      expect(
        plan.bestCutFor(0, const <AudioSegment>[
          AudioSegment(
            start: Duration(milliseconds: 100),
            end: Duration(milliseconds: 200),
          ),
        ]),
        isNull,
      );
    });

    test('no candidates at all means no cut to offer', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(2),
      );

      expect(plan.bestCutFor(0, const <AudioSegment>[]), isNull);
    });

    test('a cut outside the segment is refused rather than reordering it', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(4),
      );

      expect(plan.splitting(1, const Duration(seconds: 99)), plan);
      expect(plan.splitting(1, Duration.zero), plan);
    });
  });

  group('turning silences into segments', () {
    const SegmentPlanner planner = SegmentPlanner();

    test('cuts in the middle of each silence, so no ayah loses its tail', () {
      final List<AudioSegment> result = planner.segmentsFrom(
        totalDuration: const Duration(seconds: 30),
        silences: <AudioSegment>[
          const AudioSegment(
            start: Duration(seconds: 9),
            end: Duration(seconds: 11),
          ),
          const AudioSegment(
            start: Duration(seconds: 19),
            end: Duration(seconds: 21),
          ),
        ],
      );

      expect(result, hasLength(3));
      expect(result[0].end, const Duration(seconds: 10));
      expect(result[1].start, const Duration(seconds: 10));
      expect(result[1].end, const Duration(seconds: 20));
      expect(result.last.end, const Duration(seconds: 30));
    });

    test('a pause inside an ayah does not become a segment of its own', () {
      final List<AudioSegment> result = planner.segmentsFrom(
        totalDuration: const Duration(seconds: 10),
        silences: <AudioSegment>[
          // Two silences 200 ms apart: a madd, not an ayah boundary.
          const AudioSegment(
            start: Duration(milliseconds: 4900),
            end: Duration(milliseconds: 5100),
          ),
          const AudioSegment(
            start: Duration(milliseconds: 5200),
            end: Duration(milliseconds: 5400),
          ),
        ],
      );

      expect(result, hasLength(2));
    });

    test('a trailing silence is the end of the recording, not an ayah', () {
      // The failure this came from: a real 22.36 s recording ending in 0.7 s
      // of room tone produced a 0.35 s final "ayah" of nothing.
      final List<AudioSegment> result = planner.segmentsFrom(
        totalDuration: const Duration(milliseconds: 22360),
        silences: const <AudioSegment>[
          AudioSegment(
            start: Duration(milliseconds: 4137),
            end: Duration(milliseconds: 4680),
          ),
          AudioSegment(
            start: Duration(milliseconds: 5758),
            end: Duration(milliseconds: 6155),
          ),
          AudioSegment(
            start: Duration(milliseconds: 10597),
            end: Duration(milliseconds: 11253),
          ),
          AudioSegment(
            start: Duration(milliseconds: 21658),
            end: Duration(milliseconds: 22360),
          ),
        ],
      );

      // Four segments — basmala, and three ayahs — and the last ends where the
      // recitation does, not where the file does.
      expect(result, hasLength(4));
      expect(result.last.end, const Duration(milliseconds: 21658));
      expect(result.map((AudioSegment s) => s.duration.inMilliseconds), <int>[
        4408,
        1548,
        4968,
        10733,
      ]);
    });

    test('room tone before the first word is not part of the first ayah', () {
      final List<AudioSegment> result = planner.segmentsFrom(
        totalDuration: const Duration(seconds: 10),
        silences: const <AudioSegment>[
          AudioSegment(start: Duration.zero, end: Duration(milliseconds: 300)),
          AudioSegment(
            start: Duration(milliseconds: 4900),
            end: Duration(milliseconds: 5400),
          ),
        ],
      );

      expect(result.first.start, const Duration(milliseconds: 300));
      expect(result, hasLength(2));
    });

    test('no silences means one segment for the whole recording', () {
      expect(
        planner.segmentsFrom(
          totalDuration: const Duration(seconds: 12),
          silences: const <AudioSegment>[],
        ),
        <AudioSegment>[
          const AudioSegment(start: Duration.zero, end: Duration(seconds: 12)),
        ],
      );
    });
  });

  group('aligning to the text', () {
    const SegmentPlanner planner = SegmentPlanner();

    /// Pauses every second of a ten-second recording.
    List<AudioSegment> everySecond(int count) => <AudioSegment>[
      for (int i = 1; i <= count; i++)
        AudioSegment(
          start: Duration(milliseconds: i * 1000 - 50),
          end: Duration(milliseconds: i * 1000 + 50),
        ),
    ];

    test('a long ayah gets proportionally more of the recording', () {
      // Three ayahs weighted 1:3:1 across 10 s should take about 2 s, 6 s and
      // 2 s — and every cut still lands in a real pause.
      final List<AudioSegment> result = planner.alignToWeights(
        totalDuration: const Duration(seconds: 10),
        silences: everySecond(9),
        weights: <int>[10, 30, 10],
      );

      expect(result, hasLength(3));
      expect(result[0].end, const Duration(seconds: 2));
      expect(result[1].end, const Duration(seconds: 8));
      expect(result.last.end, const Duration(seconds: 10));
    });

    test('the chosen cuts are the best possible set, not the best one at a '
        'time', () {
      // Checked against every valid set of cuts rather than against a
      // hand-picked answer: taking the nearest pause for an early ayah can
      // leave a later one with nothing near it, and the only way to know the
      // result is optimal is to compare it with all the alternatives.
      const List<int> weights = <int>[30, 25, 45];
      const Duration total = Duration(seconds: 20);
      final List<AudioSegment> pauses = <AudioSegment>[
        for (final int ms in <int>[2300, 5100, 6200, 9400, 11800, 15900])
          AudioSegment(
            start: Duration(milliseconds: ms - 50),
            end: Duration(milliseconds: ms + 50),
          ),
      ];

      final List<AudioSegment> result = planner.alignToWeights(
        totalDuration: total,
        silences: pauses,
        weights: weights,
      );
      expect(result, hasLength(weights.length));

      // The objective, restated independently of the planner: each segment
      // should be the right length for its own text, and being half as long
      // is as wrong as being twice as long.
      final List<double> points = <double>[
        0,
        for (final AudioSegment pause in pauses)
          (pause.start + (pause.end - pause.start) ~/ 2).inMilliseconds / 1000,
        total.inMilliseconds / 1000,
      ];
      final double span = total.inMilliseconds / 1000;
      final double pause = math.min(1.0, span / weights.length / 10);
      final double perUnit = (span - pause * weights.length) / 100;
      final List<double> expected = <double>[
        for (final int w in weights) pause + perUnit * w,
      ];
      double cost(List<double> lengths) {
        double sum = 0;
        for (int k = 0; k < lengths.length; k++) {
          final double ratio = math.log(lengths[k] / expected[k]);
          sum += expected[k] * ratio * ratio;
        }
        return sum;
      }

      double best = double.infinity;
      for (int i = 1; i < points.length - 1; i++) {
        for (int j = i + 1; j < points.length - 1; j++) {
          final double c = cost(<double>[
            points[i] - points[0],
            points[j] - points[i],
            points.last - points[j],
          ]);
          if (c < best) best = c;
        }
      }

      expect(
        cost(<double>[
          for (final AudioSegment segment in result)
            segment.duration.inMilliseconds / 1000,
        ]),
        closeTo(best, 1e-9),
      );
    });

    test('a change of pace does not drag every later cut with it', () {
      // The fault this aligner was rewritten for. Eight ayahs, short and long
      // alternating; the reciter takes the first four a quarter slower than
      // average and the last four a fifth faster. Placing cuts where the
      // surah's *average* pace says they belong expects the fourth at 24s when
      // it is at 28.8s, and the nearest pause to 24s is the breath at 23.4s
      // inside ayah 4. Judged by segment length, each ayah only has to be
      // about right for its own words.
      //
      // It is not magic: double the pace change and the text alone can no
      // longer tell a slow long ayah from two ordinary ones. This is the size
      // of drift a real recitation has.
      const List<int> trueCuts = <int>[
        3600,
        14400,
        18000,
        28800,
        31200,
        38400,
        40800,
      ];
      // Breaths inside ayahs 2, 4, 6 and 8.
      const List<int> breaths = <int>[9000, 23400, 34800, 44400];
      final List<AudioSegment> pauses = <AudioSegment>[
        for (final int ms in <int>[...trueCuts, ...breaths]..sort())
          AudioSegment(
            start: Duration(milliseconds: ms - 50),
            end: Duration(milliseconds: ms + 50),
          ),
      ];

      final List<AudioSegment> result = planner.alignToWeights(
        totalDuration: const Duration(seconds: 48),
        silences: pauses,
        weights: <int>[10, 30, 10, 30, 10, 30, 10, 30],
      );

      expect(result, hasLength(8));
      expect(<int>[
        for (final AudioSegment segment in result.take(7))
          segment.end.inMilliseconds,
      ], trueCuts);
    });

    test('a fragment is never the cheap way out', () {
      // A click 300ms into a long first ayah. A cost based on the difference
      // in seconds cannot charge more than the ayah's own length for cutting
      // there, which made a 0.3s "ayah" the cheapest mistake available; by
      // ratio it is the most expensive one.
      final List<AudioSegment> pauses = <AudioSegment>[
        for (final int ms in <int>[300, 9000, 20000])
          AudioSegment(
            start: Duration(milliseconds: ms - 50),
            end: Duration(milliseconds: ms + 50),
          ),
      ];
      final List<AudioSegment> result = planner.alignToWeights(
        totalDuration: const Duration(seconds: 30),
        silences: pauses,
        weights: <int>[30, 35, 35],
      );

      expect(result, hasLength(3));
      expect(result[0].end, const Duration(seconds: 9));
      for (final AudioSegment segment in result) {
        expect(segment.duration, greaterThan(const Duration(seconds: 2)));
      }
    });

    test('fewer pauses than ayahs is refused rather than invented', () {
      // Cutting inside a word to reach a count is worse than saying no.
      expect(
        planner.alignToWeights(
          totalDuration: const Duration(seconds: 10),
          silences: everySecond(1),
          weights: <int>[10, 10, 10],
        ),
        isEmpty,
      );
    });

    test('a leading silence is not part of the first ayah', () {
      final List<AudioSegment> result = planner.alignToWeights(
        totalDuration: const Duration(seconds: 10),
        silences: <AudioSegment>[
          const AudioSegment(start: Duration.zero, end: Duration(seconds: 1)),
          ...everySecond(9).skip(2),
        ],
        weights: <int>[10, 10],
      );

      expect(result.first.start, const Duration(seconds: 1));
    });

    test('weights that say nothing produce nothing', () {
      expect(
        planner.alignToWeights(
          totalDuration: const Duration(seconds: 10),
          silences: everySecond(9),
          weights: <int>[0, 0],
        ),
        isEmpty,
      );
    });
  });

  group('the publish guard', () {
    const PublishGuard guard = PublishGuard();

    test('a matching count is allowed', () {
      expect(
        guard.decide(
          plan: SegmentPlan(surah: ikhlas, segments: segments(5)),
        ),
        isA<PublishAllowed>(),
      );
    });

    test('a mismatch is blocked, and says what it expected', () {
      final PublishDecision decision = guard.decide(
        plan: SegmentPlan(surah: ikhlas, segments: segments(4)),
      );

      expect(decision, isA<PublishBlocked>());
      expect((decision as PublishBlocked).reason, contains('expected 5'));
      expect(decision.reason, contains('basmala'));
    });

    test('an override with no real reason is still blocked', () {
      final PublishDecision decision = guard.decide(
        plan: SegmentPlan(surah: ikhlas, segments: segments(4)),
        override: PublishOverride(reason: 'ok', at: DateTime(2026)),
      );

      expect(decision, isA<PublishBlocked>());
      expect((decision as PublishBlocked).reason, contains('at least'));
    });

    test('an override with a typed reason publishes, and records it', () {
      final PublishOverride override = PublishOverride(
        reason: 'The reciter joins ayahs 3 and 4 in this reading.',
        at: DateTime(2026),
      );

      final PublishDecision decision = guard.decide(
        plan: SegmentPlan(surah: ikhlas, segments: segments(4)),
        override: override,
      );

      expect(decision, isA<PublishOverridden>());
      expect((decision as PublishOverridden).operatorOverride, override);
      expect(decision.summary, contains('4 segments, expected 5'));
    });

    test('nothing split is never publishable', () {
      expect(
        guard.decide(
          plan: SegmentPlan(surah: ikhlas, segments: const <AudioSegment>[]),
        ),
        isA<PublishBlocked>(),
      );
    });
  });
}
