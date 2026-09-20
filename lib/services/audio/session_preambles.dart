import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';

/// Which preambles lead a session — the whole decision, in one place.
///
/// Two independent questions, deliberately not collapsed into one:
///
/// | `bismillahMode`      | bismillah preamble | why                          |
/// |----------------------|--------------------|------------------------------|
/// | `counted_as_ayah_1`  | **never**          | it already *is* ayah 1's audio |
/// | `separate_preamble`  | once, before ayah 1| precedes ayah 1, unnumbered  |
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
  ///
  /// [startAyah] is where in [surah] the session begins. The basmala opens a
  /// surah, so it leads a session only when the session starts at the surah's
  /// first ayah (CLAUDE.md A.5): one that picks up at ayah 120 is not the
  /// opening of anything. The isti'adhah is for beginning to recite at all,
  /// and does not mind where.
  factory SessionPreambles.forSession({
    required Surah surah,
    required Reciter reciter,
    required bool istiadhahEnabled,
    int startAyah = 1,
  }) => SessionPreambles(
    istiadhah: istiadhahEnabled && reciter.hasIstiadhah,
    // `hasBasmala`, not `hasBismillah`: a manifest reciter's basmala is ayah 0
    // of the surah rather than a reciter-level clip, and a session over
    // streamed audio still opens with it.
    bismillah: startAyah == 1 && playsBasmala(surah: surah, reciter: reciter),
  );

  /// Whether [surah] is opened with a standalone basmala in [reciter]'s voice.
  ///
  /// The same answer serves the surah a session starts in and any surah it
  /// runs on into, which is the point of asking it in one place.
  static bool playsBasmala({required Surah surah, required Reciter reciter}) =>
      _playsBismillah(surah) && reciter.hasBasmala(surah.number);

  /// Of the surahs a session enters after its first, those whose basmala is
  /// played on the way in. A range only ever enters a later surah at its
  /// ayah 1, so there is no "started part-way" case to weigh here.
  static Set<int> forLaterSurahs({
    required Iterable<Surah> surahs,
    required Reciter reciter,
  }) => <int>{
    for (final Surah surah in surahs)
      if (playsBasmala(surah: surah, reciter: reciter)) surah.number,
  };

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
