import 'dart:io';

import '../../data/models/surah.dart';
import 'ffmpeg_runner.dart';
import 'segment_audit.dart';
import 'segment_planner.dart';

/// How a split was arrived at.
enum SplitMethod {
  /// Cut at every pause the threshold found, and the count came out right.
  threshold,

  /// The pauses were treated as candidates and the text chose among them.
  aligned,
}

/// A proposed split, with what is needed to judge it.
class SplitResult {
  const SplitResult({
    required this.plan,
    required this.method,
    required this.candidates,
    required this.total,
    required this.suspects,
  });

  final SegmentPlan plan;
  final SplitMethod method;

  /// Every pause the sensitive pass found — what "split here" cuts on, and
  /// what a later re-alignment chooses from.
  final List<AudioSegment> candidates;

  final Duration total;

  /// Indices of segments whose length their text cannot explain.
  final List<int> suspects;

  /// The widest stretch with no pause in it. A large value explains a fused
  /// segment: there was nowhere to cut.
  Duration get widestStretchWithoutAPause => widestHole(candidates, total);
}

/// Splits a whole-surah recording into one segment per ayah.
///
/// The admin screen and `tool/publish_surah.dart` both come here, and that is
/// the point of this class. They used to cut separately, and every
/// improvement made while publishing a hundred surahs from the command line
/// — candidates chosen by coverage, the aligner judged by segment length, the
/// per-clip check — never reached the screen, whose own "more sensitive" pass
/// was in fact lowering the threshold and finding fewer pauses.
class SurahSplitter {
  const SurahSplitter({
    required this.ffmpeg,
    this.planner = const SegmentPlanner(),
  });

  final FfmpegRunner ffmpeg;
  final SegmentPlanner planner;

  /// [weights] is one entry per expected segment (see `segmentWeights`), or
  /// empty when the ayah text could not be loaded — in which case only the
  /// threshold split is possible and nothing can be checked against the text.
  Future<SplitResult> split({
    required File source,
    required Surah surah,
    required List<int> weights,
    required double thresholdDb,
    required Duration minimumSilence,
    bool recordingHasBasmala = true,
    bool recordingHasIstiadhah = false,
    Duration candidateMinimum = const Duration(milliseconds: 180),
  }) async {
    // Every ffmpeg pass this split could need, started at once. Each one
    // decodes the whole recording, and they used to run in single file: the
    // operator's threshold first, then up to eight sweep passes one after
    // another — minutes of wall clock for an hour-long surah, nearly all of
    // it the same decode repeated. The passes are independent, so the wall
    // time is now one decode, not nine.
    final Future<Duration> totalFuture = ffmpeg.durationOf(source);
    final Future<List<AudioSegment>> primary = ffmpeg.detectSilences(
      source,
      threshold: thresholdDb,
      minimumSilence: minimumSilence,
    );
    final Future<List<List<AudioSegment>>> sweep =
        Future.wait(<Future<List<AudioSegment>>>[
          for (final double threshold in _sweep)
            ffmpeg.detectSilences(
              source,
              threshold: threshold,
              minimumSilence: candidateMinimum,
            ),
        ]);

    final Duration total = await totalFuture;
    SegmentPlan plan = SegmentPlan(
      surah: surah,
      recordingHasBasmala: recordingHasBasmala,
      recordingHasIstiadhah: recordingHasIstiadhah,
      segments: planner.segmentsFrom(
        totalDuration: total,
        silences: await primary,
      ),
    );

    final bool comparable = weights.length == plan.expectedCount;
    final List<AudioSegment> candidates = chooseCandidates(
      bySweep: await sweep,
      needed: plan.expectedCount - 1,
      total: total,
    );

    // The right count is not the same as the right cuts: a surah can split
    // into exactly the expected number and still give one ayah a second of a
    // five-second recitation. So a split that matches is still checked.
    final List<int> plainSuspects = comparable && plan.countMatches
        ? suspectsIn(plan.segments, weights)
        : const <int>[];

    if (!comparable || (plan.countMatches && plainSuspects.isEmpty)) {
      return SplitResult(
        plan: plan,
        method: SplitMethod.threshold,
        candidates: candidates,
        total: total,
        suspects: plainSuspects,
      );
    }

    final SplitResult resolved = _alignedOrThreshold(
      plan: plan,
      candidates: candidates,
      total: total,
      weights: weights,
      plainSuspects: plainSuspects,
    );
    if (resolved.plan.countMatches && resolved.suspects.isEmpty) {
      return resolved;
    }

    // A second look with finer ears. A reciter who barely breathes between
    // ayahs leaves pauses shorter than [candidateMinimum], and at the default
    // that reads as "nowhere to cut": the split comes back short, or fused
    // clips read as suspects. Halving the minimum is exactly the fix an
    // operator used to apply by hand from the command line, so it is tried
    // here before anything is reported — but the finer cut only replaces the
    // first when it is strictly better, so a recording the first pass served
    // well is untouched. Below 60 ms a "pause" is the gap inside a word, and
    // no cut belongs there.
    final Duration finerMinimum = candidateMinimum ~/ 2;
    if (finerMinimum < const Duration(milliseconds: 60)) return resolved;

    final List<List<AudioSegment>> finerSweep =
        await Future.wait(<Future<List<AudioSegment>>>[
          for (final double threshold in _sweep)
            ffmpeg.detectSilences(
              source,
              threshold: threshold,
              minimumSilence: finerMinimum,
            ),
        ]);
    final List<AudioSegment> finerCandidates = chooseCandidates(
      bySweep: finerSweep,
      needed: plan.expectedCount - 1,
      total: total,
    );
    final List<AudioSegment> finerAligned = planner.alignToWeights(
      totalDuration: total,
      silences: finerCandidates,
      weights: weights,
    );
    if (finerAligned.isEmpty) return resolved;

    final List<int> finerSuspects = suspectsIn(finerAligned, weights);
    final bool better =
        !resolved.plan.countMatches ||
        finerSuspects.length < resolved.suspects.length;
    if (!better) return resolved;

    return SplitResult(
      plan: plan.copyWith(segments: finerAligned),
      method: SplitMethod.aligned,
      candidates: finerCandidates,
      total: total,
      suspects: finerSuspects,
    );
  }

  /// The aligner's verdict at one set of candidates: the aligned cut when it
  /// earns its place, the threshold cut otherwise.
  SplitResult _alignedOrThreshold({
    required SegmentPlan plan,
    required List<AudioSegment> candidates,
    required Duration total,
    required List<int> weights,
    required List<int> plainSuspects,
  }) {
    final List<AudioSegment> aligned = planner.alignToWeights(
      totalDuration: total,
      silences: candidates,
      weights: weights,
    );
    if (aligned.isEmpty) {
      return SplitResult(
        plan: plan,
        method: SplitMethod.threshold,
        candidates: candidates,
        total: total,
        suspects: plainSuspects,
      );
    }

    // When the plain split already had the right count, the aligned one has
    // to earn its place: it replaces it only by leaving fewer clips out of
    // line with their text.
    final List<int> alignedSuspects = suspectsIn(aligned, weights);
    if (plan.countMatches && alignedSuspects.length >= plainSuspects.length) {
      return SplitResult(
        plan: plan,
        method: SplitMethod.threshold,
        candidates: candidates,
        total: total,
        suspects: plainSuspects,
      );
    }

    return SplitResult(
      plan: plan.copyWith(segments: aligned),
      method: SplitMethod.aligned,
      candidates: candidates,
      total: total,
      suspects: alignedSuspects,
    );
  }

  /// Candidate pauses for the aligner, chosen by coverage rather than count.
  ///
  /// An earlier version took the first threshold yielding 1.2x the cuts
  /// needed. That reads "enough pauses" as "usable pauses", and the two come
  /// apart badly on a recording whose loud passages sit above the threshold
  /// its quiet ones fall below: surah 24 found 77 pauses for 64 cuts and still
  /// had a seventeen-minute stretch with none in it, so seventeen minutes of
  /// recitation came out as a single ayah. What matters is that no stretch is
  /// left without a pause, so that is what is measured here.
  ///
  /// [bySweep] is one detection result per [_sweep] threshold, in [_sweep]'s
  /// order — detected in parallel by [split], judged here in the same strict
  /// to lenient order the sequential sweep used, so the choice is unchanged.
  static List<AudioSegment> chooseCandidates({
    required List<List<AudioSegment>> bySweep,
    required int needed,
    required Duration total,
  }) {
    // Twice the average segment. Erring towards more candidates is the safe
    // direction: a spurious pause only offers the aligner a cut it can
    // decline, while a missing one forces a fusion it cannot avoid.
    final Duration acceptable = Duration(
      milliseconds: (total.inMilliseconds / (needed + 1) * 2).round(),
    );

    List<AudioSegment> best = const <AudioSegment>[];
    List<AudioSegment> largest = const <AudioSegment>[];
    Duration bestHole = total;

    for (final List<AudioSegment> found in bySweep) {
      if (found.length > largest.length) largest = found;
      if (found.length < needed) continue;

      final Duration hole = widestHole(found, total);
      if (hole < bestHole) {
        bestHole = hole;
        best = found;
      }
      // Quieter thresholds cut inside fewer ayahs, so the first one that
      // covers the recording is the one to take — provided it also leaves
      // the aligner something to choose from. Surah 50 offered 52 pauses for
      // 45 cuts: with that little slack the aligner is being told where to
      // cut, not asked, and one breath in the wrong place becomes a
      // quarter-second "ayah".
      if (hole <= acceptable && found.length >= (needed * 1.6).ceil()) break;
    }

    // Nothing reached the count: hand back the largest set anyway, so the
    // caller can show what there is rather than nothing at all.
    return best.isEmpty ? largest : best;
  }

  /// From strict to lenient. Lower numbers demand a deeper silence and so
  /// find fewer pauses; the sweep stops at the first that is enough.
  static const List<double> _sweep = <double>[
    -45, -40, -35, -30, -25, -20, -15, -12, //
  ];
}
