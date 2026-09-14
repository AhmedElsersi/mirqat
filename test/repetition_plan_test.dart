import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/services/audio/playback_queue.dart';
import 'package:mirqat/services/audio/session_preambles.dart';

/// Checks 31–35 of the audit: what a built session actually contains.
///
/// Catalog-driven, like the asset integrity suite — every surah in
/// `surahs.json` is exercised, so a surah added tomorrow is covered by this
/// file unchanged. The one hardcoded surah here is a *synthetic* `none`
/// fixture, because no shipped surah is At-Tawbah yet and the branch would
/// otherwise go untested until the day it shipped.
///
/// The stake: a preamble that leaks into the queue as an ayah makes every
/// repeat count wrong, and the app then teaches the error by repetition.
void main() {
  final List<Surah> catalog = _catalog();
  final Reciter reciter = _reciters().first;

  const RepetitionPlanBuilder plans = RepetitionPlanBuilder();
  const PlaybackQueueBuilder queues = PlaybackQueueBuilder();

  test('the catalog under test is not empty', () {
    expect(catalog, isNotEmpty);
    expect(
      catalog.map((Surah s) => s.bismillahMode).toSet(),
      isNotEmpty,
      reason: 'every mode present in the catalog is exercised below',
    );
  });

  for (final Surah surah in catalog) {
    final String label = 'surah ${surah.number} (${surah.nameEn})';

    SessionPlan planFor({int repeats = 3}) => plans.buildOrThrow(
      SessionConfig(
        surahNumber: surah.number,
        startAyah: 1,
        endAyah: surah.ayahCount,
        repeatCount: repeats,
      ),
      surahAyahCount: surah.ayahCount,
    );

    group(label, () {
      test('31 a plan at repeat 3 holds exactly ayahCount distinct ayahs', () {
        final SessionPlan plan = planFor();
        final Set<int> distinct =
            plan.units.map((PlaybackUnit u) => u.ayahNumber).toSet();

        expect(
          distinct.length,
          surah.ayahCount,
          reason:
              'the plan recites ${distinct.length} distinct ayahs but the '
              'catalog declares ${surah.ayahCount}',
        );
        expect(
          distinct,
          List<int>.generate(surah.ayahCount, (int i) => i + 1).toSet(),
          reason: 'the ayahs recited must be exactly 1..${surah.ayahCount}',
        );
      });

      test('32 no queue entry is a preamble typed as an ayah', () {
        final PlaybackQueue queue = _queue(
          queues,
          planFor(),
          surah: surah,
          reciter: reciter,
          istiadhahEnabled: true,
        );

        for (int i = 0; i < queue.entries.length; i++) {
          final QueueEntry entry = queue.entries[i];
          if (entry is! AyahQueueEntry) continue;
          expect(
            entry.unit.ayahNumber,
            inInclusiveRange(1, surah.ayahCount),
            reason:
                'queue index $i is typed as an ayah but points outside '
                '1..${surah.ayahCount}',
          );
        }

        // The ayah count the progress UI shows must exclude the preambles.
        final int ayahEntries =
            queue.entries.whereType<AyahQueueEntry>().length;
        expect(
          ayahEntries,
          planFor().units.length,
          reason: 'a preamble was counted as a recitation',
        );
      });

      test('33/34 the bismillah preamble follows the catalog', () {
        final SessionPreambles preambles = SessionPreambles.forSession(
          surah: surah,
          reciter: reciter,
          istiadhahEnabled: false,
        );
        final PlaybackQueue queue = queues.build(
          plan: planFor(),
          includeIstiadhah: preambles.istiadhah,
          includeBismillah: preambles.bismillah,
        );

        final List<int> at = _indicesOf(queue, PreambleKind.bismillah);

        switch (surah.bismillahMode) {
          case BismillahMode.countedAsAyah1:
            expect(
              at,
              isEmpty,
              reason:
                  'the bismillah IS ayah 1 here, so a preamble would recite '
                  'it twice',
            );
          case BismillahMode.separatePreamble:
            expect(at, hasLength(1), reason: 'exactly one, at session start');
            expect(
              at.single,
              0,
              reason:
                  'the bismillah opens the session; inside a repeat block or a '
                  'cumulative connection it would be recited over and over',
            );
          case BismillahMode.none:
            expect(at, isEmpty);
        }
      });

      test('35 the istiʿadhah plays once, first, and never re-enters', () {
        final PlaybackQueue on = _queue(
          queues,
          planFor(),
          surah: surah,
          reciter: reciter,
          istiadhahEnabled: true,
        );

        final List<int> istiadhah = _indicesOf(on, PreambleKind.istiadhah);
        expect(istiadhah, hasLength(1));
        expect(istiadhah.single, 0, reason: 'it leads the whole session');

        final List<int> bismillah = _indicesOf(on, PreambleKind.bismillah);
        if (bismillah.isNotEmpty) {
          expect(
            istiadhah.single,
            lessThan(bismillah.single),
            reason: 'the istiʿadhah precedes the bismillah',
          );
        }

        final PlaybackQueue off = _queue(
          queues,
          planFor(),
          surah: surah,
          reciter: reciter,
          istiadhahEnabled: false,
        );
        expect(
          _indicesOf(off, PreambleKind.istiadhah),
          isEmpty,
          reason: 'the toggle is off, so it must not play at all',
        );
      });

      test('cumulative connection blocks hold ayahs only', () {
        final SessionPlan plan = plans.buildOrThrow(
          SessionConfig(
            surahNumber: surah.number,
            startAyah: 1,
            endAyah: surah.ayahCount,
            repeatCount: 3,
            connectMode: ConnectMode.cumulative,
          ),
          surahAyahCount: surah.ayahCount,
        );

        for (final PlanStep step in plan.steps) {
          if (step.type != StepType.connect) continue;
          for (final int ayah in step.ayahs) {
            expect(
              ayah,
              inInclusiveRange(1, surah.ayahCount),
              reason: 'a connection block reached outside the surah',
            );
          }
        }

        final PlaybackQueue queue = _queue(
          queues,
          plan,
          surah: surah,
          reciter: reciter,
          istiadhahEnabled: true,
        );
        // Past the opening preambles, no preamble may appear again.
        final int firstAyah = queue.entries.indexWhere(
          (QueueEntry e) => e is AyahQueueEntry,
        );
        expect(
          queue.entries
              .skip(firstAyah)
              .whereType<PreambleQueueEntry>()
              .toList(),
          isEmpty,
          reason:
              'a preamble appeared after the session started — inside a repeat '
              'block or a connection',
        );
      });
    });
  }

  group('bismillahMode: none (synthetic — no shipped surah is At-Tawbah)', () {
    final Surah tawbahShaped = Surah.fromJson(<String, dynamic>{
      'number': 9,
      'nameAr': '-',
      'nameEn': 'none-mode fixture',
      'ayahCount': 4,
      'revelationPlace': 'madinah',
      'bismillahMode': 'none',
    }, 'synthetic');

    test('no bismillah unit, with or without the istiʿadhah', () {
      final SessionPlan plan = plans.buildOrThrow(
        const SessionConfig(surahNumber: 9, startAyah: 1, endAyah: 4),
        surahAyahCount: 4,
      );

      for (final bool istiadhah in <bool>[true, false]) {
        final PlaybackQueue queue = _queue(
          queues,
          plan,
          surah: tawbahShaped,
          reciter: reciter,
          istiadhahEnabled: istiadhah,
        );
        expect(
          _indicesOf(queue, PreambleKind.bismillah),
          isEmpty,
          reason: 'At-Tawbah opens with no bismillah',
        );
        expect(
          _indicesOf(queue, PreambleKind.istiadhah),
          hasLength(istiadhah ? 1 : 0),
          reason: 'the istiʿadhah is independent of bismillahMode',
        );
      }
    });
  });

  group('a reciter who supplies neither preamble', () {
    final Reciter bare = Reciter.fromJson(<String, dynamic>{
      'id': 'bare',
      'nameAr': '-',
      'nameEn': 'No preambles',
      'audioMode': 'per_ayah_files',
      'basePath': 'assets/audio/bare',
      'availableSurahs': <int>[1],
    }, 'synthetic');

    test('the flags default to false, so nothing is queued that has no '
        'file behind it', () {
      expect(bare.hasIstiadhah, isFalse);
      expect(bare.hasBismillah, isFalse);

      for (final Surah surah in catalog) {
        final SessionPreambles preambles = SessionPreambles.forSession(
          surah: surah,
          reciter: bare,
          istiadhahEnabled: true,
        );
        expect(preambles.istiadhah, isFalse);
        expect(preambles.bismillah, isFalse);
        expect(preambles.count, 0);
      }
    });
  });

  test('preamble paths are reciter-level, with no surah in them', () {
    expect(
      AssetPaths.istiadhahFile(reciter.basePath),
      '${reciter.basePath}/istiadhah.mp3',
    );
    expect(
      AssetPaths.bismillahFile(reciter.basePath),
      '${reciter.basePath}/bismillah.mp3',
    );
  });
}

/// Builds the queue exactly as `MemorizationPlayerService.load` does, through
/// the one place that decides which preambles a session gets.
PlaybackQueue _queue(
  PlaybackQueueBuilder queues,
  SessionPlan plan, {
  required Surah surah,
  required Reciter reciter,
  required bool istiadhahEnabled,
}) {
  final SessionPreambles preambles = SessionPreambles.forSession(
    surah: surah,
    reciter: reciter,
    istiadhahEnabled: istiadhahEnabled,
  );
  return queues.build(
    plan: plan,
    includeIstiadhah: preambles.istiadhah,
    includeBismillah: preambles.bismillah,
  );
}

List<int> _indicesOf(PlaybackQueue queue, PreambleKind kind) => <int>[
  for (int i = 0; i < queue.entries.length; i++)
    if (queue.entries[i] case PreambleQueueEntry(kind: final PreambleKind k)
        when k == kind)
      i,
];

/// Reads the shipped catalog off disk. No Flutter binding, so the engine stays
/// testable as the pure Dart it is.
List<Surah> _catalog() => <Surah>[
  for (final dynamic entry
      in jsonDecode(File(AssetPaths.surahsCatalog).readAsStringSync())
          as List<dynamic>)
    Surah.fromJson(entry as Map<String, dynamic>, AssetPaths.surahsCatalog),
];

List<Reciter> _reciters() => <Reciter>[
  for (final dynamic entry
      in jsonDecode(File(AssetPaths.recitersCatalog).readAsStringSync())
          as List<dynamic>)
    Reciter.fromJson(entry as Map<String, dynamic>, AssetPaths.recitersCatalog),
];
