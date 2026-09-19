import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/recitation_weight.dart';
import 'package:mirqat/admin/services/segment_audit.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/data/models/surah.dart';

const Surah ikhlas = Surah(
  number: 112,
  nameAr: 'الإخلاص',
  nameEn: 'Al-Ikhlas',
  ayahCount: 4,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

const Surah fatiha = Surah(
  number: 1,
  nameAr: 'الفاتحة',
  nameEn: 'Al-Fatiha',
  ayahCount: 7,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.countedAsAyah1,
);

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
      end: Duration(seconds: i * 5 + 5),
    ),
];

/// Recordings differ, and only the operator knows which kind this one is:
/// some open with the isti'adhah, some start straight at ayah 1. Both change
/// how many segments a correct split has — and getting that number wrong
/// files every ayah under its neighbour's name.
void main() {
  group('what the recording holds', () {
    test('by default a separate surah expects its basmala', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(5),
      );
      expect(plan.expectedCount, 5);
      expect(plan.countMatches, isTrue);
      expect(plan.planned.first.isBasmala, isTrue);
      expect(plan.planned.first.ayahNumber, 0);
      expect(plan.planned[1].ayahNumber, 1);
      expect(plan.published, hasLength(5));
    });

    test('a recording that starts at ayah 1 has no basmala segment', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(4),
        recordingHasBasmala: false,
      );
      expect(plan.expectsBasmala, isFalse);
      expect(plan.expectedCount, 4);
      expect(plan.countMatches, isTrue);
      // Segment 0 is ayah 1, and nothing is exported as 000.
      expect(plan.planned.first.isBasmala, isFalse);
      expect(plan.planned.first.ayahNumber, 1);
      expect(plan.published.map((PlannedSegment s) => s.ayahNumber), <int>[
        1, 2, 3, 4, //
      ]);
    });

    test("an isti'adhah is one more segment, cut and never published", () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(6),
        recordingHasIstiadhah: true,
      );
      expect(plan.expectedCount, 6);
      expect(plan.planned[0].isIstiadhah, isTrue);
      expect(plan.planned[0].isPublished, isFalse);
      expect(plan.planned[1].isBasmala, isTrue);
      expect(plan.planned[2].ayahNumber, 1);
      expect(plan.ayahNumberFor(0), isNull);
      expect(plan.ayahNumberFor(1), isNull);
      expect(plan.ayahNumberFor(2), 1);

      // The files that go up are exactly the basmala and the four ayahs.
      expect(plan.published.map((PlannedSegment s) => s.ayahNumber), <int>[
        0, 1, 2, 3, 4, //
      ]);
      expect(plan.published.any((PlannedSegment s) => s.isIstiadhah), isFalse);
    });

    test("isti'adhah straight into ayah 1, with no basmala", () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(5),
        recordingHasBasmala: false,
        recordingHasIstiadhah: true,
      );
      expect(plan.expectedCount, 5);
      expect(plan.planned[0].isIstiadhah, isTrue);
      expect(plan.planned[1].ayahNumber, 1);
      expect(plan.published.map((PlannedSegment s) => s.ayahNumber), <int>[
        1, 2, 3, 4, //
      ]);
    });

    test('"has basmala" cannot add a segment the surah does not call for', () {
      // Al-Fatiha's basmala is ayah 1 and At-Tawba has none: there is no
      // basmala segment to keep or drop in either, whatever the box says.
      for (final Surah surah in <Surah>[fatiha, tawba]) {
        for (final bool ticked in <bool>[true, false]) {
          final SegmentPlan plan = SegmentPlan(
            surah: surah,
            segments: const <AudioSegment>[],
            recordingHasBasmala: ticked,
          );
          expect(plan.expectsBasmala, isFalse, reason: surah.nameEn);
          expect(plan.expectedCount, surah.ayahCount, reason: surah.nameEn);
        }
      }
    });

    test('an edit keeps the options it was made under', () {
      final SegmentPlan plan = SegmentPlan(
        surah: ikhlas,
        segments: segments(5),
        recordingHasBasmala: false,
        recordingHasIstiadhah: true,
      );
      final SegmentPlan edited = plan.removing(2);
      expect(edited.recordingHasBasmala, isFalse);
      expect(edited.recordingHasIstiadhah, isTrue);
      expect(edited.expectedCount, plan.expectedCount);
    });
  });

  group('segment weights follow the options', () {
    const List<String> ayahs = <String>[
      'قُلْ هُوَ',
      'ٱللَّهُ',
      'لَمْ يَلِدْ',
      'وَلَمْ',
    ];
    const String basmala = 'بِسْمِ ٱللَّهِ';

    test('one weight per expected segment, in recited order', () {
      expect(
        segmentWeights(
          ayahTexts: ayahs,
          basmalaText: basmala,
          hasBasmala: true,
          hasIstiadhah: true,
        ),
        <int>[
          kIstiadhahWeight,
          recitationWeight(basmala),
          for (final String a in ayahs) recitationWeight(a),
        ],
      );
      expect(
        segmentWeights(
          ayahTexts: ayahs,
          basmalaText: basmala,
          hasBasmala: false,
          hasIstiadhah: false,
        ),
        hasLength(ayahs.length),
      );
    });
  });

  group('clips out of line with their text', () {
    test('a fragment and a fusion are found; honest variation is not', () {
      // Ten ayahs of 20 units at about 0.3s a unit plus a pause: ~7s each,
      // with ordinary variation. Then ayah 4 loses most of itself to ayah 5.
      final List<int> weights = List<int>.filled(10, 20);
      final List<double> honest = <double>[
        7.1, 6.6, 7.4, 6.9, 7.2, 6.8, 7.0, 7.3, 6.7, 7.1, //
      ];
      expect(suspectSegments(honest, weights), isEmpty);

      final List<double> miscut = <double>[...honest]
        ..[3] = 0.4
        ..[4] = 13.7;
      expect(suspectSegments(miscut, weights), contains(3));
    });

    test('a long ayah is not suspect for being long', () {
      final List<int> weights = <int>[10, 10, 80, 10, 10, 10, 10, 10, 10];
      final List<double> durations = <double>[
        4.0, 4.2, 25.0, 3.9, 4.1, 4.0, 4.3, 3.8, 4.1, //
      ];
      expect(suspectSegments(durations, weights), isEmpty);
    });

    test('mismatched lengths give no verdict rather than a wrong one', () {
      expect(suspectSegments(<double>[1, 2, 3], <int>[1, 2]), isEmpty);
    });
  });
}
