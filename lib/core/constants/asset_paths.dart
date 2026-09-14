/// Canonical asset locations. Every path the app loads is derived here so the
/// on-disk layout is described in exactly one place.
class AssetPaths {
  const AssetPaths._();

  static const String translations = 'assets/translations';

  static const String _brand = 'assets/brand';

  /// The animated splash's back plate: the sunrise vista. 1836 x 3876.
  static const String splashScene = '$_brand/splash_scene.webp';

  /// The animated splash's front plate: cave rock with the opening cut out as
  /// real alpha. 1224 x 2584 — smaller on purpose, and the same aspect ratio
  /// as [splashScene], which is what keeps the two aligned.
  static const String splashCave = '$_brand/splash_cave.webp';

  /// Frame 0, baked, for the native splash that precedes the Flutter one.
  /// Not loaded by the app — `flutter_native_splash` reads it at build time —
  /// but named here so the asset audit can see it is accounted for.
  static const String splashFirstFrame = '$_brand/splash_first_frame.png';

  static const String _data = 'assets/data';
  static const String surahsCatalog = '$_data/surahs.json';
  static const String recitersCatalog = '$_data/reciters.json';

  /// The WAV, not the MP3. MP3 cannot encode exactly 400 ms — encoder delay
  /// and frame padding leave the shipped MP3 at 391.7 ms, and that error
  /// accumulates across every gap in a session. The WAV is sample-exact at
  /// 44.1 kHz mono, matching the ayah clips.
  static const String silenceSpacer = 'assets/audio/silence_400ms.wav';

  /// Zero-pads a surah or ayah number to the 3-digit form used by every
  /// file name in the asset tree (`1` -> `001`).
  static String pad3(int number) => number.toString().padLeft(3, '0');

  /// Ayah text file for a surah: `assets/data/ayahs/001.json`.
  static String ayahsForSurah(int surahNumber) =>
      '$_data/ayahs/${pad3(surahNumber)}.json';

  /// Timings file for a `single_file_with_timings` reciter:
  /// `assets/data/timings/<reciterId>/001.json`.
  static String timingsForSurah(String reciterId, int surahNumber) =>
      '$_data/timings/$reciterId/${pad3(surahNumber)}.json';

  /// One ayah clip for a `per_ayah_files` reciter:
  /// `<basePath>/001/001.mp3`.
  static String perAyahFile(String basePath, int surahNumber, int ayahNumber) =>
      '$basePath/${pad3(surahNumber)}/${pad3(ayahNumber)}.mp3';

  /// Whole-surah clip for a `single_file_with_timings` reciter:
  /// `<basePath>/001.mp3`.
  static String surahFile(String basePath, int surahNumber) =>
      '$basePath/${pad3(surahNumber)}.mp3';

  /// Standalone bismillah clip: `<basePath>/bismillah.mp3`.
  ///
  /// One per reciter, not one per surah. The words, the reciter and the
  /// recording session are the same for every surah that needs it, so a
  /// per-surah copy would be identical audio under a different name. Whether
  /// a given session plays it is a catalog decision, not a path decision —
  /// see `SessionPreambles`.
  static String bismillahFile(String basePath) => '$basePath/bismillah.mp3';

  /// Standalone isti'adhah clip: `<basePath>/istiadhah.mp3`.
  ///
  /// Reciter-level for the same reason as the bismillah, and surah-independent
  /// in a stronger sense: it is not part of any surah. Neither preamble is an
  /// ayah, and neither ever enters the playback queue as one.
  static String istiadhahFile(String basePath) => '$basePath/istiadhah.mp3';
}
