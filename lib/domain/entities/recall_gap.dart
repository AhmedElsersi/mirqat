/// How long the silence of one recall round is.
///
/// One home for the arithmetic, used by the playback queue to lay the silence
/// out in spacer clips and by [SessionPlan.estimatedDuration] to add it up, so
/// the summary and the session can never disagree about it.
abstract final class RecallGap {
  /// The reader recites unaided at roughly the reciter's own pace, plus a
  /// breath to begin. The margin is a fifth of the clip and a fixed 600 ms,
  /// so a short ayah still gets its breath and a long one is not padded out
  /// of proportion.
  static const double clipFactor = 1.2;
  static const Duration margin = Duration(milliseconds: 600);

  /// For an ayah whose clip could not be measured — one that would have to be
  /// streamed. A fixed gap, not a guess dressed as a measurement: it is never
  /// shown as a number, only lived through, and six seconds holds most ayahs
  /// of a drill-sized range.
  static const Duration fallback = Duration(seconds: 6);

  /// The gap for an ayah whose recitation lasts [clip], or [fallback] when
  /// there is no measurement to size it from.
  static Duration of(Duration? clip) => clip == null
      ? fallback
      : Duration(
          microseconds: (clip.inMicroseconds * clipFactor).round(),
        ) +
          margin;
}
