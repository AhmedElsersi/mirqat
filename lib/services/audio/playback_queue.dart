import 'package:equatable/equatable.dart';

import '../../domain/entities/playback_unit.dart';
import '../../domain/entities/session_plan.dart';

/// Why a spacer sits where it does. Carried for debugging and for the plan
/// timeline; playback treats every spacer the same.
enum GapKind { intraBlock, betweenRepeats, betweenSteps, afterPreamble }

enum PreambleKind { istiadhah, bismillah }

/// One item in the player's queue.
sealed class QueueEntry extends Equatable {
  const QueueEntry();
}

/// An ayah play. The only entry kind that maps to a [PlaybackUnit].
class AyahQueueEntry extends QueueEntry {
  const AyahQueueEntry(this.unit);

  final PlaybackUnit unit;

  @override
  List<Object?> get props => <Object?>[unit];
}

/// A 400 ms silence clip. Several in a row make a longer gap.
class SpacerQueueEntry extends QueueEntry {
  const SpacerQueueEntry(this.kind);

  final GapKind kind;

  @override
  List<Object?> get props => <Object?>[kind];
}

/// The isti'adhah or a standalone bismillah. Played once before the session,
/// never counted as a recitation.
class PreambleQueueEntry extends QueueEntry {
  const PreambleQueueEntry(this.kind, {this.surah});

  final PreambleKind kind;

  /// The surah whose basmala this is, for one the session runs on into. Null
  /// for the preambles that open the session, which belong to its first
  /// surah.
  final int? surah;

  @override
  List<Object?> get props => <Object?>[kind, surah];
}

/// The flat queue handed to the player, plus the index bookkeeping the UI
/// needs to map a queue position back onto the plan.
class PlaybackQueue extends Equatable {
  const PlaybackQueue({required this.entries, required this.plan});

  final List<QueueEntry> entries;
  final SessionPlan plan;

  int get length => entries.length;

  /// The unit playing at [queueIndex], or null for a spacer or preamble.
  PlaybackUnit? unitAt(int queueIndex) {
    if (queueIndex < 0 || queueIndex >= entries.length) return null;
    final QueueEntry entry = entries[queueIndex];
    return entry is AyahQueueEntry ? entry.unit : null;
  }

  /// Queue index of the [unitIndex]-th ayah play — where a session resumed
  /// part-way picks up. Unit 0 answers 0, not the first ayah's own index, so
  /// that a session started from the top still opens with its preambles.
  int indexOfUnit(int unitIndex) {
    if (unitIndex <= 0) return 0;
    int seen = 0;
    for (int i = 0; i < entries.length; i++) {
      if (entries[i] is! AyahQueueEntry) continue;
      if (seen == unitIndex) return i;
      seen++;
    }
    throw RangeError.index(unitIndex, plan.units, 'unitIndex');
  }

  /// Queue index of the first ayah play of [stepIndex].
  int indexOfStep(int stepIndex) {
    for (int i = 0; i < entries.length; i++) {
      final QueueEntry entry = entries[i];
      if (entry is AyahQueueEntry && entry.unit.stepIndex == stepIndex) {
        return i;
      }
    }
    throw RangeError.index(stepIndex, plan.steps, 'stepIndex');
  }

  /// Maps a player's `currentIndexStream` onto the unit being recited.
  ///
  /// Spacers and preambles carry no unit, so they are dropped rather than
  /// reported — crossing a gap must never look like a change of ayah. The
  /// distinct() is safe because consecutive units always differ by at least
  /// their repeat index.
  Stream<PlaybackUnit> unitStreamFrom(Stream<int?> indexStream) => indexStream
      .map((int? index) => index == null ? null : unitAt(index))
      .where((PlaybackUnit? unit) => unit != null)
      .cast<PlaybackUnit>()
      .distinct();

  @override
  List<Object?> get props => <Object?>[entries, plan];
}

/// Expands a [SessionPlan] into the player's queue, realising each configured
/// pause as a run of silence clips.
class PlaybackQueueBuilder {
  const PlaybackQueueBuilder({this.spacerMs = 400});

  /// Duration of the single silence asset. Gaps are built by repeating it, so
  /// every gap is quantised to a multiple of this.
  final int spacerMs;

  /// How many spacer clips approximate [gapMs].
  ///
  /// Rounded to the nearest whole clip, so with the shipped 400 ms spacer the
  /// defaults land at 400 / 800 / 1600 ms rather than the configured
  /// 300 / 800 / 1500. A gap under half a clip rounds away to nothing.
  int spacerCount(int gapMs) => (gapMs / spacerMs).round();

  PlaybackQueue build({
    required SessionPlan plan,
    bool includeIstiadhah = false,
    bool includeBismillah = false,
    Set<int> basmalaBeforeSurahs = const <int>{},
  }) {
    final List<QueueEntry> entries = <QueueEntry>[];

    void addGap(int gapMs, GapKind kind) {
      for (int i = 0; i < spacerCount(gapMs); i++) {
        entries.add(SpacerQueueEntry(kind));
      }
    }

    if (includeIstiadhah) {
      entries.add(const PreambleQueueEntry(PreambleKind.istiadhah));
      addGap(plan.config.betweenStepsPauseMs, GapKind.afterPreamble);
    }
    if (includeBismillah) {
      entries.add(const PreambleQueueEntry(PreambleKind.bismillah));
      addGap(plan.config.betweenStepsPauseMs, GapKind.afterPreamble);
    }

    // A surah the session runs on into is announced the way a reciter
    // announces it: its basmala, once, ahead of the first time its opening
    // ayah is heard. Not ahead of every repeat — the basmala is not part of
    // the drill, and saying it thirty times would make it one.
    final Set<int> announced = <int>{};

    for (int i = 0; i < plan.units.length; i++) {
      final PlaybackUnit unit = plan.units[i];
      if (basmalaBeforeSurahs.contains(unit.surahNumber) &&
          announced.add(unit.surahNumber)) {
        entries.add(
          PreambleQueueEntry(PreambleKind.bismillah, surah: unit.surahNumber),
        );
        addGap(plan.config.betweenStepsPauseMs, GapKind.afterPreamble);
      }
      entries.add(AyahQueueEntry(unit));

      if (i == plan.units.length - 1) break;

      addGap(
        plan.gapAfter(unit).inMilliseconds,
        unit.isLastUnitOfStep
            ? GapKind.betweenSteps
            : unit.isLastUnitOfRepeat
            ? GapKind.betweenRepeats
            : GapKind.intraBlock,
      );
    }

    return PlaybackQueue(
      entries: List<QueueEntry>.unmodifiable(entries),
      plan: plan,
    );
  }
}
