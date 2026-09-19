import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/admin/services/timecode.dart';
import 'package:mirqat/data/models/surah.dart';

const Surah surah = Surah(
  number: 112,
  nameAr: 'الإخلاص',
  nameEn: 'Al-Ikhlas',
  ayahCount: 2,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

Duration s(double seconds) => Duration(milliseconds: (seconds * 1000).round());

/// basmala 0–5, ayah 1 5–12, ayah 2 12–20, in a 20 s recording.
SegmentPlan plan() => SegmentPlan(
  surah: surah,
  segments: <AudioSegment>[
    AudioSegment(start: s(0), end: s(5)),
    AudioSegment(start: s(5), end: s(12)),
    AudioSegment(start: s(12), end: s(20)),
  ],
);

/// The edit for a cut that has no pause to land on: a reciter who runs the
/// basmala into ayah 1 leaves nothing for the splitter to find, and the only
/// way to a right cut is for someone to listen and say where it goes.
void main() {
  group('moving a boundary', () {
    test(
      'a shared boundary moves both segments, leaving no gap or overlap',
      () {
        final SegmentPlan moved = plan().movingBoundary(
          1,
          s(6.5),
          recordingLength: s(20),
        );
        expect(moved.segments[0].end, s(6.5));
        expect(moved.segments[1].start, s(6.5));
        // Nothing else is touched.
        expect(moved.segments[0].start, s(0));
        expect(moved.segments[1].end, s(12));
        expect(moved.segments[2], plan().segments[2]);

        for (int i = 1; i < moved.segments.length; i++) {
          expect(moved.segments[i].start, moved.segments[i - 1].end);
        }
      },
    );

    test('boundary 0 trims a preamble off the front of the first segment', () {
      // Surah 24: the basmala clip held 21 s because the recording opens with
      // something else and no pause separates them.
      final SegmentPlan moved = plan().movingBoundary(
        0,
        s(2.25),
        recordingLength: s(20),
      );
      expect(moved.segments.first.start, s(2.25));
      expect(moved.segments.first.end, s(5));
    });

    test('the last boundary trims the tail', () {
      final SegmentPlan moved = plan().movingBoundary(
        3,
        s(18),
        recordingLength: s(20),
      );
      expect(moved.segments.last.end, s(18));
    });

    test('a boundary cannot pass its neighbours or squash a segment', () {
      const Duration min = SegmentPlan.minimumSegment;
      // Dragged far past the end of ayah 1: held just inside it.
      expect(
        plan().movingBoundary(1, s(19), recordingLength: s(20)).segments[0].end,
        s(12) - min,
      );
      // And far before the start of the basmala.
      expect(
        plan().movingBoundary(1, s(-4), recordingLength: s(20)).segments[0].end,
        s(0) + min,
      );
      // The end of the recording is a wall too.
      expect(
        plan().movingBoundary(3, s(90), recordingLength: s(20)).segments[2].end,
        s(20),
      );
    });

    test('a boundary that does not exist changes nothing', () {
      expect(plan().movingBoundary(-1, s(3), recordingLength: s(20)), plan());
      expect(plan().movingBoundary(4, s(3), recordingLength: s(20)), plan());
    });

    test('the count and the recording options survive an edit', () {
      final SegmentPlan withOptions = SegmentPlan(
        surah: surah,
        segments: plan().segments,
        recordingHasIstiadhah: true,
      );
      final SegmentPlan moved = withOptions.movingBoundary(
        1,
        s(4),
        recordingLength: s(20),
      );
      expect(moved.actualCount, withOptions.actualCount);
      expect(moved.recordingHasIstiadhah, isTrue);
    });
  });

  group('trimming one edge without its neighbour', () {
    test('pulling an end in leaves a gap, and the next segment stays put', () {
      // A phrase the reciter repeated after ayah 1: it belongs to neither.
      final SegmentPlan trimmed = plan().trimmingEdge(
        1,
        end: s(10.5),
        recordingLength: s(20),
      );
      expect(trimmed.segments[1].end, s(10.5));
      expect(trimmed.segments[2].start, s(12), reason: 'neighbour untouched');
      expect(trimmed.gapAfter(1), s(1.5));
      expect(trimmed.gapAfter(0), Duration.zero);
    });

    test('pushing a start in leaves a gap before it', () {
      final SegmentPlan trimmed = plan().trimmingEdge(
        1,
        start: s(6),
        recordingLength: s(20),
      );
      expect(trimmed.segments[1].start, s(6));
      expect(trimmed.segments[0].end, s(5), reason: 'neighbour untouched');
      expect(trimmed.gapAfter(0), s(1));
    });

    test('a gap, never an overlap: an edge stops at its neighbour', () {
      // Two clips sharing a second of audio would both recite words that
      // belong to one of them. Going *past* a neighbour is the joined move.
      expect(
        plan()
            .trimmingEdge(1, end: s(15), recordingLength: s(20))
            .segments[1]
            .end,
        s(12),
      );
      expect(
        plan()
            .trimmingEdge(1, start: s(3), recordingLength: s(20))
            .segments[1]
            .start,
        s(5),
      );
      // The first and last segments are held by the recording itself.
      expect(
        plan()
            .trimmingEdge(0, start: s(-2), recordingLength: s(20))
            .segments[0]
            .start,
        s(0),
      );
      expect(
        plan()
            .trimmingEdge(2, end: s(99), recordingLength: s(20))
            .segments[2]
            .end,
        s(20),
      );
    });

    test('a segment cannot be trimmed to nothing', () {
      const Duration min = SegmentPlan.minimumSegment;
      expect(
        plan()
            .trimmingEdge(1, end: s(1), recordingLength: s(20))
            .segments[1]
            .end,
        s(5) + min,
      );
      expect(
        plan()
            .trimmingEdge(1, start: s(19), recordingLength: s(20))
            .segments[1]
            .start,
        s(12) - min,
      );
    });

    test('a joined move afterwards closes the gap again', () {
      final SegmentPlan trimmed = plan().trimmingEdge(
        1,
        end: s(10.5),
        recordingLength: s(20),
      );
      final SegmentPlan rejoined = trimmed.movingBoundary(
        2,
        s(11),
        recordingLength: s(20),
      );
      expect(rejoined.segments[1].end, s(11));
      expect(rejoined.segments[2].start, s(11));
      expect(rejoined.gapAfter(1), Duration.zero);
    });

    test('the count and options survive, and nothing else moves', () {
      final SegmentPlan trimmed = plan().trimmingEdge(
        1,
        start: s(6),
        end: s(11),
        recordingLength: s(20),
      );
      expect(trimmed.actualCount, 3);
      expect(trimmed.segments[0], plan().segments[0]);
      expect(trimmed.segments[2], plan().segments[2]);
    });
  });

  group('timecodes', () {
    test('what the list shows can be typed back in', () {
      for (final double seconds in <double>[0, 4.25, 75.4, 3725.125]) {
        expect(parseTimecode(formatTimecode(s(seconds))), s(seconds));
      }
    });

    test('plain seconds, m:ss and h:mm:ss are all read', () {
      expect(parseTimecode('75.4'), s(75.4));
      expect(parseTimecode('1:15.4'), s(75.4));
      expect(parseTimecode('1:02:15.5'), s(3735.5));
      expect(parseTimecode('  12  '), s(12));
    });

    test('a typo is refused rather than turned into a cut', () {
      for (final String bad in <String>[
        '',
        'abc',
        '1:75',
        '-3',
        '1:2:3:4',
        '1:-5',
        '1.5:20',
        'NaN',
        '1:',
      ]) {
        expect(parseTimecode(bad), isNull, reason: '"$bad"');
      }
    });
  });
}
