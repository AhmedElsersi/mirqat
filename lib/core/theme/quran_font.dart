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
  hafsV18('hafs_v18', 'assets/fonts/KFGQPCHafs-Uthmanic-v18.ttf'),

  /// The KFGQPC QPC V2 print: not one font but 604, one for each page, each
  /// drawing its page's words from the glyph codes `quran.db` keeps for
  /// them (`words.glyph_v2`), laid out by that print's own lines. None ships:
  /// a page's font is fetched from the CDN when the page is first drawn
  /// (`QpcFontService`). Everything that is not a mushaf page — and a page
  /// whose font has not arrived — is drawn in [textFace].
  qpcV2('qpc_v2', null);

  const QuranFont(this.storageValue, this.assetPath);

  final String storageValue;

  /// The font file, as declared in `pubspec.yaml`. Null for a face that is
  /// fetched rather than bundled.
  final String? assetPath;

  /// Whether this face draws mushaf pages from per-page fonts and glyph
  /// codes, in the QPC V2 layout.
  bool get pageFonts => this == qpcV2;

  /// The bundled face that draws the text itself wherever this one does not.
  QuranFont get textFace => assetPath == null ? fallback : this;

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
