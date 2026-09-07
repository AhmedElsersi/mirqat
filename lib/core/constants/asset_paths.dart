/// Canonical asset locations. Every path the app loads is derived here so the
/// on-disk layout is described in exactly one place.
class AssetPaths {
  const AssetPaths._();

  static const String translations = 'assets/translations';

  static const String _data = 'assets/data';
  static const String surahsCatalog = '$_data/surahs.json';
  static const String recitersCatalog = '$_data/reciters.json';

  static const String silenceSpacer = 'assets/audio/silence_400ms.mp3';

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

  /// Standalone bismillah clip, used only by surahs whose `bismillahMode`
  /// is `separate_preamble`.
  static String bismillahFile(String basePath) => '$basePath/bismillah.mp3';
}
