import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';

/// Which preambles lead a session — the whole decision, in one place.
///
/// Two independent questions, deliberately not collapsed into one:
///
/// | `bismillahMode`      | bismillah preamble | why                          |
/// |----------------------|--------------------|------------------------------|
/// | `counted_as_ayah_1`  | **never**          | it already *is* ayah 1's audio |
/// | `separate_preamble`  | once, at the start | precedes ayah 1, unnumbered  |
/// | `none`               | never              | At-Tawbah                    |
///
/// The isti'adhah is orthogonal to all three: it plays once, before the
/// bismillah, when the user's toggle is on and the reciter has the clip.
///
/// Neither preamble is ever a `PlaybackUnit` of kind ayah. They must not
/// appear in repeat blocks, in cumulative connections, or in the ayah count
/// the progress UI shows. If either leaked into the queue as an ayah the
/// repeat counts would be wrong, and the app would teach the error by
/// repetition — the one failure mode a memorization app cannot ship.
///
/// Scattering this across call sites is how surah 1 ends up reciting the
/// bismillah twice, so every caller reads it from here.
class SessionPreambles {
  const SessionPreambles({required this.istiadhah, required this.bismillah});

  /// No preambles at all — the shape every `none` surah lands on.
  static const SessionPreambles empty = SessionPreambles(
    istiadhah: false,
    bismillah: false,
  );

  /// Resolves the table above for one session.
  ///
  /// [istiadhahEnabled] is the user's toggle; the bismillah has none, because
  /// whether it belongs is a property of the surah, not a preference.
  factory SessionPreambles.forSession({
    required Surah surah,
    required Reciter reciter,
    required bool istiadhahEnabled,
  }) => SessionPreambles(
    istiadhah: istiadhahEnabled && reciter.hasIstiadhah,
    bismillah: _playsBismillah(surah) && reciter.hasBismillah,
  );

  /// Every [BismillahMode] gets an explicit arm, `none` included, so adding a
  /// fourth mode is a compile error here rather than silence at playback.
  static bool _playsBismillah(Surah surah) => switch (surah.bismillahMode) {
    BismillahMode.countedAsAyah1 => false,
    BismillahMode.separatePreamble => true,
    BismillahMode.none => false,
  };

  /// Play the isti'adhah once, before everything else.
  final bool istiadhah;

  /// Play the standalone bismillah once, after any isti'adhah and before
  /// ayah 1.
  final bool bismillah;

  /// How many queue entries these preambles occupy — never part of the ayah
  /// count shown to the user.
  int get count => (istiadhah ? 1 : 0) + (bismillah ? 1 : 0);

  @override
  String toString() =>
      'SessionPreambles(istiadhah: $istiadhah, bismillah: $bismillah)';
}
