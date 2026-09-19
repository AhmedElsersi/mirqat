import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../../data/models/surah.dart';

/// One stretch of audio the splitter believes is a single recitation unit.
class AudioSegment extends Equatable {
  const AudioSegment({required this.start, required this.end});

  final Duration start;
  final Duration end;

  Duration get duration => end - start;

  AudioSegment copyWith({Duration? start, Duration? end}) =>
      AudioSegment(start: start ?? this.start, end: end ?? this.end);

  @override
  List<Object?> get props => <Object?>[start, end];
}

/// A segment with the ayah it will be published as.
class PlannedSegment extends Equatable {
  const PlannedSegment({
    required this.segment,
    required this.ayahNumber,
    required this.isBasmala,
    this.isIstiadhah = false,
  });

  final AudioSegment segment;

  /// The number in the exported file name — `{SSS}{AAA}.mp3`. Zero is the
  /// surah's own basmala.
  final int ayahNumber;

  /// Whether this segment is the basmala rather than an ayah. It is never
  /// counted as one (CLAUDE.md A.5).
  final bool isBasmala;

  /// Whether this segment is the isti'adhah the recording opens with. It is
  /// cut so that it does not end up inside the basmala or ayah 1, and then it
  /// is left out: it belongs to no surah, so nothing is published for it.
  final bool isIstiadhah;

  /// Whether a file is exported for this segment.
  bool get isPublished => !isIstiadhah;

  @override
  List<Object?> get props => <Object?>[
    segment,
    ayahNumber,
    isBasmala,
    isIstiadhah,
  ];
}

/// How many segments a surah should split into, and what the first one is.
///
/// Driven entirely by `basmala_mode` out of `quran.db` — never by the surah
/// number, and never by a list kept here (CLAUDE.md A.2 rule 2):
///
/// | `basmalaMode`        | segments        | segment 0 is            |
/// |----------------------|-----------------|-------------------------|
/// | `separate`           | ayahCount + 1   | the basmala, `{SSS}000` |
/// | `first_ayah`         | ayahCount       | ayah 1, basmala inside  |
/// | `none`               | ayahCount       | ayah 1, no basmala      |
///
/// That table is what the *surah* calls for. What a particular *recording*
/// holds is the operator's to say, because recordings differ: one reciter's
/// files open with the isti'adhah, another's start straight at ayah 1 with no
/// basmala at all. [recordingHasIstiadhah] adds a leading segment that is cut
/// and not published; [recordingHasBasmala] set to false takes the basmala
/// segment away, and the manifest then says `hasBasmala: false` so the app
/// never asks the CDN for a file that was never made.
class SegmentPlan extends Equatable {
  const SegmentPlan({
    required this.surah,
    required this.segments,
    this.recordingHasBasmala = true,
    this.recordingHasIstiadhah = false,
  });

  final Surah surah;
  final List<AudioSegment> segments;

  /// Whether this recording recites the basmala before ayah 1. Only has any
  /// effect on a `separate` surah — elsewhere there is no basmala segment to
  /// take away.
  final bool recordingHasBasmala;

  /// Whether this recording opens with the isti'adhah.
  final bool recordingHasIstiadhah;

  /// Whether a basmala segment is expected: the surah has one of its own and
  /// this recording recites it.
  bool get expectsBasmala =>
      surah.bismillahMode == BismillahMode.separatePreamble &&
      recordingHasBasmala;

  /// Whether the first segment is the isti'adhah.
  bool get expectsIstiadhah => recordingHasIstiadhah;

  /// How many segments this recording should have produced.
  int get expectedCount =>
      surah.ayahCount + (expectsBasmala ? 1 : 0) + (expectsIstiadhah ? 1 : 0);

  int get actualCount => segments.length;

  bool get countMatches => actualCount == expectedCount;

  /// Each segment with the ayah number it will be exported as.
  ///
  /// For a `separate` surah the first segment is the basmala and everything
  /// after it shifts by one; otherwise segment 0 *is* ayah 1.
  List<PlannedSegment> get planned {
    // Segments before ayah 1, in the order they are recited.
    final int lead = expectsIstiadhah ? 1 : 0;
    final int basmalaIndex = expectsBasmala ? lead : -1;
    final int firstAyahIndex = lead + (expectsBasmala ? 1 : 0);
    return List<PlannedSegment>.unmodifiable(<PlannedSegment>[
      for (int i = 0; i < segments.length; i++)
        PlannedSegment(
          segment: segments[i],
          ayahNumber: i < firstAyahIndex ? 0 : i - firstAyahIndex + 1,
          isBasmala: i == basmalaIndex,
          isIstiadhah: expectsIstiadhah && i == 0,
        ),
    ]);
  }

  /// The segments a file is exported for — everything but the isti'adhah.
  List<PlannedSegment> get published => List<PlannedSegment>.unmodifiable(
    planned.where((PlannedSegment s) => s.isPublished),
  );

  /// The ayah whose text belongs beside [index], or null for the basmala —
  /// which is not an ayah and has no row in `ayahs`.
  int? ayahNumberFor(int index) {
    final PlannedSegment planned = this.planned[index];
    return planned.isBasmala || planned.isIstiadhah ? null : planned.ayahNumber;
  }

  SegmentPlan copyWith({List<AudioSegment>? segments}) => SegmentPlan(
    surah: surah,
    segments: segments ?? this.segments,
    recordingHasBasmala: recordingHasBasmala,
    recordingHasIstiadhah: recordingHasIstiadhah,
  );

  /// [segments] with one replaced, for an operator nudging a boundary.
  SegmentPlan replacing(int index, AudioSegment segment) => copyWith(
    segments: <AudioSegment>[
      for (int i = 0; i < segments.length; i++)
        if (i == index) segment else segments[i],
    ],
  );

  /// [segments] with one boundary moved to [to].
  ///
  /// Boundaries are numbered by the segment they *start*: 0 is where the first
  /// segment begins, `segments.length` is where the last one ends, and every
  /// number between is shared — it is the end of one segment and the start of
  /// the next, and moving it moves both, because a gap or an overlap between
  /// two ayahs is never what an operator means.
  ///
  /// This is the one edit that does not need a pause to land on. Where a
  /// reciter runs the basmala into ayah 1, or one ayah into the next, there is
  /// no pause for the splitter to find, and the only way to a right cut is for
  /// someone to listen and say where it goes.
  ///
  /// [to] is held inside what it can mean: a boundary cannot pass its
  /// neighbours, and neither side is left shorter than [minimumSegment].
  SegmentPlan movingBoundary(
    int boundary,
    Duration to, {
    required Duration recordingLength,
  }) {
    if (segments.isEmpty || boundary < 0 || boundary > segments.length) {
      return this;
    }

    final Duration lowest = boundary == 0
        ? Duration.zero
        : segments[boundary - 1].start + minimumSegment;
    final Duration highest = boundary == segments.length
        ? recordingLength
        : segments[boundary].end - minimumSegment;
    if (highest < lowest) return this;

    final Duration at = to < lowest ? lowest : (to > highest ? highest : to);
    return copyWith(
      segments: <AudioSegment>[
        for (int i = 0; i < segments.length; i++)
          segments[i].copyWith(
            start: i == boundary ? at : null,
            end: i == boundary - 1 ? at : null,
          ),
      ],
    );
  }

  /// [segments] with only segment [index]'s own start or end moved — its
  /// neighbour stays where it is.
  ///
  /// [movingBoundary] keeps two segments joined, which is right when the cut
  /// between two ayahs is simply in the wrong place. This is for the other
  /// case: something between them that belongs to neither — a cough, a phrase
  /// the reciter repeated, an isti'adhah before the basmala. Pulling one edge
  /// in without its neighbour leaves a gap, and what is in the gap is exported
  /// to no clip at all.
  ///
  /// A gap, never an overlap: the edge is held at its neighbour's, because two
  /// clips sharing the same second of audio would each recite words that
  /// belong to only one of them. Moving an edge *past* its neighbour is what
  /// the joined move is for.
  SegmentPlan trimmingEdge(
    int index, {
    Duration? start,
    Duration? end,
    required Duration recordingLength,
  }) {
    if (index < 0 || index >= segments.length) return this;
    final AudioSegment current = segments[index];

    Duration hold(Duration value, Duration lowest, Duration highest) =>
        value < lowest ? lowest : (value > highest ? highest : value);

    Duration newStart = current.start;
    Duration newEnd = current.end;
    if (start != null) {
      final Duration floor = index == 0
          ? Duration.zero
          : segments[index - 1].end;
      final Duration ceiling = current.end - minimumSegment;
      if (ceiling >= floor) newStart = hold(start, floor, ceiling);
    }
    if (end != null) {
      final Duration floor = newStart + minimumSegment;
      final Duration ceiling = index == segments.length - 1
          ? recordingLength
          : segments[index + 1].start;
      if (ceiling >= floor) newEnd = hold(end, floor, ceiling);
    }

    return replacing(index, AudioSegment(start: newStart, end: newEnd));
  }

  /// The audio between segment [index] and the one after it that belongs to
  /// neither, or zero when they are joined.
  Duration gapAfter(int index) {
    if (index < 0 || index >= segments.length - 1) return Duration.zero;
    final Duration gap = segments[index + 1].start - segments[index].end;
    return gap > Duration.zero ? gap : Duration.zero;
  }

  /// The shortest a hand edit may leave a segment. Short enough to keep a
  /// one-word ayah, long enough that a slip of the mouse cannot make a clip
  /// that holds nothing.
  static const Duration minimumSegment = Duration(milliseconds: 200);

  /// [segments] with one removed — a silence the splitter mistook for a break.
  SegmentPlan removing(int index) => copyWith(
    segments: <AudioSegment>[
      for (int i = 0; i < segments.length; i++)
        if (i != index) segments[i],
    ],
  );

  /// Where to cut [index] in two, given [candidates] — quiet moments the
  /// primary pass rejected as too short or too faint to be breaks.
  ///
  /// The longest quiet moment inside the segment wins, and the cut lands in
  /// the middle of it. Halving a segment instead, which is the obvious thing
  /// to do, cuts wherever the arithmetic lands — usually inside a word, which
  /// is how an ayah ends up beginning mid-syllable.
  ///
  /// Null when no candidate leaves a usable piece on both sides; the caller
  /// then has nothing better than the midpoint.
  Duration? bestCutFor(
    int index,
    List<AudioSegment> candidates, {
    Duration minimumPiece = const Duration(milliseconds: 500),
  }) {
    final AudioSegment target = segments[index];
    final List<AudioSegment> inside =
        candidates
            .where(
              (AudioSegment c) =>
                  c.start >= target.start + minimumPiece &&
                  c.end <= target.end - minimumPiece,
            )
            .toList()
          ..sort(
            (AudioSegment a, AudioSegment b) =>
                b.duration.compareTo(a.duration),
          );
    if (inside.isEmpty) return null;
    final AudioSegment quietest = inside.first;
    return quietest.start + (quietest.end - quietest.start) ~/ 2;
  }

  /// [segments] with one split in two at [at], for a break the splitter missed.
  SegmentPlan splitting(int index, Duration at) {
    final AudioSegment target = segments[index];
    if (at <= target.start || at >= target.end) return this;
    return copyWith(
      segments: <AudioSegment>[
        for (int i = 0; i < segments.length; i++)
          if (i != index)
            segments[i]
          else ...<AudioSegment>[
            AudioSegment(start: target.start, end: at),
            AudioSegment(start: at, end: target.end),
          ],
      ],
    );
  }

  @override
  List<Object?> get props => <Object?>[
    surah,
    segments,
    recordingHasBasmala,
    recordingHasIstiadhah,
  ];
}

/// Turns the silences ffmpeg found into segments.
///
/// Pure, and deliberately separate from the ffmpeg call: the arithmetic that
/// decides where an ayah begins is the part worth testing, and it should not
/// need a binary on PATH to run.
class SegmentPlanner {
  const SegmentPlanner();

  /// Segments between [silences] across a recording of [totalDuration].
  ///
  /// A cut is placed in the *middle* of each silence rather than at its edges:
  /// a reciter's breath belongs to neither ayah, and splitting at the start
  /// would clip the tail of the one before.
  List<AudioSegment> segmentsFrom({
    required Duration totalDuration,
    required List<AudioSegment> silences,
    Duration minimumSegment = const Duration(milliseconds: 700),
  }) {
    final List<AudioSegment> sorted = <AudioSegment>[...silences]
      ..sort((AudioSegment a, AudioSegment b) => a.start.compareTo(b.start));

    // Room tone before the first word, and the tail after the last, are not
    // ayahs. Left in, the tail becomes a segment of its own — a fraction of a
    // second of nothing, published as the last ayah of the surah.
    Duration start = Duration.zero;
    Duration end = totalDuration;
    if (sorted.isNotEmpty && sorted.first.start <= _edge) {
      start = sorted.first.end;
    }
    if (sorted.isNotEmpty && totalDuration - sorted.last.end <= _edge) {
      end = sorted.last.start;
    }

    final List<Duration> cuts = <Duration>[
      for (final AudioSegment silence in sorted)
        if (silence.start > start && silence.end < end)
          silence.start + (silence.end - silence.start) ~/ 2,
    ]..sort();

    final List<AudioSegment> segments = <AudioSegment>[];
    Duration cursor = start;
    for (final Duration cut in cuts) {
      if (cut <= cursor || cut >= end) continue;
      final AudioSegment candidate = AudioSegment(start: cursor, end: cut);
      // A silence inside an ayah — a pause for effect, a long madd — would
      // otherwise produce a fragment no ayah could match.
      if (candidate.duration < minimumSegment) continue;
      segments.add(candidate);
      cursor = cut;
    }
    if (end > cursor) {
      segments.add(AudioSegment(start: cursor, end: end));
    }
    return List<AudioSegment>.unmodifiable(segments);
  }

  /// How close to either end a silence has to be to count as lead-in or tail
  /// rather than a break between ayahs.
  static const Duration _edge = Duration(milliseconds: 400);

  /// Chooses cuts so each segment's share of the recording matches its ayah's
  /// share of the text.
  ///
  /// Thresholding alone cannot split a long surah: Al-Baqarah yields 387
  /// segments at one setting and 206 at the next, and no setting in between is
  /// trustworthy — a count that matches is then a coincidence, with ayahs
  /// merged in one place and split in another.
  ///
  /// So the silences stop being the answer and become the *candidates*. The
  /// answer comes from the text: an ayah twice as long takes roughly twice as
  /// long to recite, so [weights] — letters per segment, straight from
  /// `quran.db` — say where each boundary should fall, and each one is moved
  /// to the nearest real silence. Every cut still lands in a gap the reciter
  /// left; which gaps are chosen is what the text decides.
  ///
  /// Answers an empty list when there are fewer candidates than cuts needed,
  /// because inventing a boundary inside a word is worse than saying no.
  List<AudioSegment> alignToWeights({
    required Duration totalDuration,
    required List<AudioSegment> silences,
    required List<int> weights,
  }) {
    if (weights.length < 2) return const <AudioSegment>[];

    final List<AudioSegment> sorted = <AudioSegment>[...silences]
      ..sort((AudioSegment a, AudioSegment b) => a.start.compareTo(b.start));

    Duration start = Duration.zero;
    Duration end = totalDuration;
    if (sorted.isNotEmpty && sorted.first.start <= _edge) {
      start = sorted.first.end;
    }
    if (sorted.isNotEmpty && totalDuration - sorted.last.end <= _edge) {
      end = sorted.last.start;
    }

    final List<Duration> candidates = <Duration>[
      for (final AudioSegment silence in sorted)
        if (silence.start > start && silence.end < end)
          silence.start + (silence.end - silence.start) ~/ 2,
    ]..sort();

    final int cuts = weights.length - 1;
    if (candidates.length < cuts) return const <AudioSegment>[];

    final int totalWeight = weights.fold<int>(0, (int a, int b) => a + b);
    if (totalWeight <= 0) return const <AudioSegment>[];

    // What each segment should last, in seconds: a pause after every ayah plus
    // time in proportion to its text. The pause is capped at a tenth of a
    // typical segment so that the text still decides.
    final double span = (end - start).inMicroseconds / 1e6;
    final int count = weights.length;
    final double pause = math.min(1.0, span / count / 10);
    final double perUnit = (span - pause * count) / totalWeight;
    final List<double> expected = <double>[
      for (final int weight in weights)
        math.max(pause + perUnit * weight, 0.05),
    ];

    // Every point a segment may start or end on: the recording's own start,
    // each pause, and its end.
    final List<double> points = <double>[
      start.inMicroseconds / 1e6,
      for (final Duration candidate in candidates)
        candidate.inMicroseconds / 1e6,
      end.inMicroseconds / 1e6,
    ];
    final int n = points.length;

    // Chosen by dynamic programming over *segment lengths*, not cut positions.
    //
    // The first version placed each cut where the surah's average pace said it
    // should fall and took the nearest pause. A reciter who slows for one
    // passage is then "late" for every cut after it, and the error walks
    // forward through the surah: measured against the published clips, that
    // left a misplaced boundary in 63 of 113 surahs. Asking instead that each
    // segment be the right length for its own words makes a slow passage a
    // local matter.
    //
    // The cost is the squared log of the ratio, weighted by the expected
    // length. A difference-based cost, (d - e)^2 / e, tops out at e as d goes
    // to zero, which made a quarter-second fragment the cheapest mistake on
    // offer; a ratio makes half as long and twice as long equally wrong.
    const double unreachable = double.infinity;
    List<double> previous = List<double>.filled(n, unreachable)..[0] = 0;
    final List<List<int>> from = <List<int>>[];

    for (int k = 0; k < count; k++) {
      final List<double> cost = List<double>.filled(n, unreachable);
      final List<int> parent = List<int>.filled(n, -1);
      final bool last = k == count - 1;

      // Segment k ends on point j. The last one must end on the final point;
      // the others must leave a pause for every segment still to come.
      final int lowest = last ? n - 1 : k + 1;
      final int highest = last ? n - 1 : n - 1 - (count - 1 - k);
      // No segment is allowed past four times its expected length plus ten
      // seconds: it bounds the search, and nothing that long is a candidate.
      final double reach = 4 * expected[k] + 10;

      for (int j = lowest; j <= highest; j++) {
        double best = unreachable;
        int bestIndex = -1;
        for (int i = j - 1; i >= k; i--) {
          final double length = points[j] - points[i];
          if (length > reach && bestIndex != -1) break;
          if (previous[i] == unreachable) continue;
          final double ratio = math.log(math.max(length, 0.05) / expected[k]);
          final double here = previous[i] + expected[k] * ratio * ratio;
          if (here < best) {
            best = here;
            bestIndex = i;
          }
        }
        cost[j] = best;
        parent[j] = bestIndex;
      }

      previous = cost;
      from.add(parent);
    }

    if (previous[n - 1] == unreachable) return const <AudioSegment>[];

    // Walk back from the end; chosen[k] is the point segment k ends on.
    final List<int> ends = List<int>.filled(count, 0);
    int at = n - 1;
    for (int k = count - 1; k >= 0; k--) {
      ends[k] = at;
      at = from[k][at];
      if (at < 0) return const <AudioSegment>[];
    }
    // As indices into `candidates`, which is what the code below cuts on.
    final List<int> chosen = <int>[for (int k = 0; k < cuts; k++) ends[k] - 1];

    final List<AudioSegment> segments = <AudioSegment>[];
    Duration cursor = start;
    for (final int index in chosen) {
      segments.add(AudioSegment(start: cursor, end: candidates[index]));
      cursor = candidates[index];
    }
    segments.add(AudioSegment(start: cursor, end: end));
    return List<AudioSegment>.unmodifiable(segments);
  }
}
