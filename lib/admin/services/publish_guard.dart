import 'package:equatable/equatable.dart';

import 'segment_planner.dart';

/// An operator's explicit decision to publish a split that does not match the
/// catalog.
class PublishOverride extends Equatable {
  const PublishOverride({required this.reason, required this.at});

  /// Typed by the operator, in their own words. Not a checkbox: the point is
  /// that somebody had to state, in writing, why a surah is being published
  /// with the wrong number of segments.
  final String reason;
  final DateTime at;

  /// The shortest reason worth recording. Anything under this is a click
  /// dressed up as a decision.
  static const int minimumReasonLength = 12;

  bool get isUsable => reason.trim().length >= minimumReasonLength;

  @override
  List<Object?> get props => <Object?>[reason, at];
}

/// Whether a split may be published.
sealed class PublishDecision extends Equatable {
  const PublishDecision();

  @override
  List<Object?> get props => <Object?>[];
}

/// The segment count matches what the surah's `basmala_mode` predicts.
class PublishAllowed extends PublishDecision {
  const PublishAllowed();
}

/// The count matches only because an operator said to proceed anyway.
class PublishOverridden extends PublishDecision {
  const PublishOverridden(this.operatorOverride, this.summary);

  // Not named `override`: a field by that name shadows the annotation inside
  // this class, and `@override` below then fails to resolve.
  final PublishOverride operatorOverride;

  /// What was overridden, for the log line that goes with the upload.
  final String summary;

  @override
  List<Object?> get props => <Object?>[operatorOverride, summary];
}

/// The count is wrong and nobody has said otherwise.
class PublishBlocked extends PublishDecision {
  const PublishBlocked(this.reason);

  final String reason;

  @override
  List<Object?> get props => <Object?>[reason];
}

/// The one gate between a reviewed split and the CDN.
///
/// A surah published with the wrong number of segments puts every later ayah
/// under the wrong number — the app would then recite ayah 6's audio against
/// ayah 5's text, and teach that by repetition. So the count is checked
/// against `quran.db` and nothing else, and it cannot be waved through by a
/// checkbox: an override needs a reason someone typed.
class PublishGuard {
  const PublishGuard();

  PublishDecision decide({
    required SegmentPlan plan,
    PublishOverride? override,
  }) {
    if (plan.segments.isEmpty) {
      return const PublishBlocked('There is nothing to publish yet.');
    }
    if (plan.countMatches) return const PublishAllowed();

    final String summary =
        '${plan.surah.nameAr} (${plan.surah.number}): '
        '${plan.actualCount} segments, expected ${plan.expectedCount} '
        '(${plan.surah.ayahCount} ayahs'
        '${plan.expectsBasmala ? ' + basmala' : ''}).';

    if (override == null) {
      return PublishBlocked(
        '$summary Fix the split, or record a reason to publish it as it is.',
      );
    }
    if (!override.isUsable) {
      return PublishBlocked(
        '$summary The override needs a reason of at least '
        '${PublishOverride.minimumReasonLength} characters.',
      );
    }
    return PublishOverridden(override, summary);
  }
}
