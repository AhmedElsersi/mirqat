import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';

import '../quran_db_fixtures.dart';

/// What the admin tool expects a recording of each surah to contain, checked
/// against the shipped `quran.db` rather than against a list kept here.
///
/// The operator's recordings all open with the basmala except At-Tawba, and
/// the pipeline has to agree with that for all 114 surahs — including the one
/// where the basmala is not a separate file because it *is* ayah 1.
void main() {
  late QuranRepository quran;
  late List<Surah> catalog;

  setUpAll(() async {
    quran = repositoryOverRealDatabase();
    catalog = (await quran.getSurahs()).getOrElse(
      () => throw StateError('quran.db did not load'),
    );
  });

  /// One segment per expected unit, so the plan can be asked what it wants.
  SegmentPlan planFor(Surah surah) => SegmentPlan(
    surah: surah,
    segments: <AudioSegment>[
      for (
        int i = 0;
        i <
            surah.ayahCount +
                (surah.bismillahMode == BismillahMode.separatePreamble ? 1 : 0);
        i++
      )
        AudioSegment(
          start: Duration(seconds: i),
          end: Duration(seconds: i + 1),
        ),
    ],
  );

  test('the catalog says what the recordings do: every surah opens with the '
      'basmala except At-Tawba', () {
    final Map<BismillahMode, List<int>> byMode = <BismillahMode, List<int>>{};
    for (final Surah surah in catalog) {
      byMode.putIfAbsent(surah.bismillahMode, () => <int>[]).add(surah.number);
    }

    expect(catalog, hasLength(114));
    // A canary on the data build, not an opinion: these two surahs are the
    // mushaf's own exceptions, and the whole pipeline keys off them.
    expect(byMode[BismillahMode.countedAsAyah1], <int>[1]);
    expect(byMode[BismillahMode.none], <int>[9]);
    expect(byMode[BismillahMode.separatePreamble], hasLength(112));
  });

  test('a separate-basmala surah expects one segment more than its ayahs, and '
      'segment 0 is exported as 000', () {
    for (final Surah surah in catalog.where(
      (Surah s) => s.bismillahMode == BismillahMode.separatePreamble,
    )) {
      final SegmentPlan plan = planFor(surah);

      expect(
        plan.expectedCount,
        surah.ayahCount + 1,
        reason: '${surah.number}',
      );
      expect(plan.countMatches, isTrue, reason: '${surah.number}');
      expect(plan.planned.first.isBasmala, isTrue, reason: '${surah.number}');
      expect(plan.planned.first.ayahNumber, 0, reason: '${surah.number}');
      expect(plan.planned[1].ayahNumber, 1, reason: '${surah.number}');
      expect(plan.planned.last.ayahNumber, surah.ayahCount);
      expect(
        plan.ayahNumberFor(0),
        isNull,
        reason: 'the basmala is not an ayah',
      );
    }
  });

  test(
    'Al-Fatiha expects exactly its ayahs, because its basmala is ayah 1',
    () {
      final Surah fatiha = catalog.firstWhere((Surah s) => s.number == 1);
      final SegmentPlan plan = planFor(fatiha);

      // The recording still opens with «بسم الله الرحمن الرحيم» — it is simply
      // ayah 1 of this surah, so it is published as 001001, never 001000.
      expect(plan.expectsBasmala, isFalse);
      expect(plan.expectedCount, fatiha.ayahCount);
      expect(plan.planned.first.isBasmala, isFalse);
      expect(plan.planned.first.ayahNumber, 1);
      expect(plan.ayahNumberFor(0), 1);
    },
  );

  test('At-Tawba expects exactly its ayahs, with no basmala at all', () {
    final Surah tawba = catalog.firstWhere((Surah s) => s.number == 9);
    final SegmentPlan plan = planFor(tawba);

    expect(plan.expectsBasmala, isFalse);
    expect(plan.expectedCount, tawba.ayahCount);
    expect(plan.planned.first.ayahNumber, 1);
  });
}
