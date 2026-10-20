/// The typefaces the mushaf's text may be drawn in.
///
/// Only a face built for the text's own encoding belongs here. `quran.db`
/// holds QUL's KFGQPC Hafs encoding, in which some codepoints name marks of
/// that script — U+065E is one, in more than a thousand ayahs — so a face
/// made for another encoding draws the wrong mark, or none, and a different
/// mark is a change to the mushaf (CLAUDE.md A.2 rule 1). Amiri Quran ships
/// in `assets/fonts/` and is **not** offered for exactly that reason.
///
/// `test/core/quran_font_coverage_test.dart` holds every face listed here to
/// a glyph for every codepoint in `quran.db`; a face that fails it cannot be
/// added. The family each one is declared under in `pubspec.yaml` is named in
/// `AppTextStyles` alone.
enum QuranFont {
  /// KFGQPC Hafs Uthmanic Script, version 2.2 — the face QUL ships with the
  /// script export `quran.db` is built from. The default.
  hafsV22('hafs_v22', 'assets/fonts/UthmanicHafs_V22.ttf'),

  /// The same script, version 0.18: the earlier cut of the face.
  hafsV18('hafs_v18', 'assets/fonts/KFGQPCHafs-Uthmanic-v18.ttf');

  const QuranFont(this.storageValue, this.assetPath);

  final String storageValue;

  /// The font file, as declared in `pubspec.yaml`.
  final String assetPath;

  static const QuranFont fallback = QuranFont.hafsV22;

  /// A stored value no longer offered — or never written by this app — is
  /// the default face, never an error: the text must always be drawable.
  static QuranFont fromStorage(Object? value) {
    for (final QuranFont font in QuranFont.values) {
      if (font.storageValue == value) return font;
    }
    return fallback;
  }
}
