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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'quran_db_fixtures.dart';

/// Checks 31–35 of the audit: what a built session actually contains.
///
/// Catalog-driven, like the asset integrity suite — every surah the reciter
/// has recorded is exercised, so a recording added tomorrow is covered by this
/// file unchanged. The `none` branch uses the catalog's own no-bismillah surah,
/// found by its mode rather than its number; no reciter has recorded it yet,
/// but a queue can be built without the audio files.
///
/// The stake: a preamble that leaks into the queue as an ayah makes every
/// repeat count wrong, and the app then teaches the error by repetition.
Future<void> main() async {
  final List<Surah> catalog = await _catalog();
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

  for (final Surah surah in catalog.where(
    (Surah s) => reciter.hasSurah(s.number),
  )) {
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
        final Set<int> distinct = plan.units
            .map((PlaybackUnit u) => u.ayahNumber)
            .toSet();

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
        final int ayahEntries = queue.entries
            .whereType<AyahQueueEntry>()
            .length;
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

  group('bismillahMode: none', () {
    final Surah tawbahShaped = catalog.firstWhere(
      (Surah s) => s.bismillahMode == BismillahMode.none,
    );
    final int end = tawbahShaped.ayahCount < 4 ? tawbahShaped.ayahCount : 4;

    test('no bismillah unit, with or without the istiʿadhah', () {
      final SessionPlan plan = plans.buildOrThrow(
        SessionConfig(
          surahNumber: tawbahShaped.number,
          startAyah: 1,
          endAyah: end,
        ),
        surahAyahCount: tawbahShaped.ayahCount,
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
    if (queue.entries[i] case PreambleQueueEntry(
      kind: final PreambleKind k,
    ) when k == kind)
      i,
];

/// Reads the shipped catalog straight out of `quran.db`. No Flutter binding,
/// so the engine stays testable as the pure Dart it is.
Future<List<Surah>> _catalog() async {
  final Database db = await RepoQuranDatabase().open();
  return (await db.query(
    'surahs',
    orderBy: 'id',
  )).map(Surah.fromDbRow).toList();
}

List<Reciter> _reciters() => <Reciter>[
  for (final dynamic entry
      in jsonDecode(File(AssetPaths.recitersCatalog).readAsStringSync())
          as List<dynamic>)
    Reciter.fromJson(entry as Map<String, dynamic>, AssetPaths.recitersCatalog),
];
