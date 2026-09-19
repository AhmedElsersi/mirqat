import 'dart:io';

import '../../core/error/exceptions.dart';
import 'segment_planner.dart';

/// The system `ffmpeg`, over `Process.run`.
///
/// The system binary and not a plugin: `ffmpeg_kit_flutter` was archived in
/// 2026, and this tool only ever runs on a Mac with Homebrew, where `ffmpeg`
/// is one `brew install` away. A missing binary is reported once, by name,
/// with the command to fix it — never worked around.
class FfmpegRunner {
  /// The silence threshold a split starts from, in dBFS.
  static const double defaultThresholdDb = -35;

  FfmpegRunner({
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
    Future<ProcessResult> Function(String, List<String>)? run,
  }) : _run = run ?? Process.run;

  final String ffmpeg;
  final String ffprobe;
  final Future<ProcessResult> Function(String, List<String>) _run;

  /// Throws [ToolMissingException] when ffmpeg is not on PATH.
  Future<String> version() async {
    final ProcessResult result;
    try {
      result = await _run(ffmpeg, <String>['-version']);
    } on ProcessException catch (e) {
      throw ToolMissingException(ffmpeg, e.message);
    }
    if (result.exitCode != 0) {
      throw ToolMissingException(
        ffmpeg,
        '`$ffmpeg -version` exited ${result.exitCode}.',
      );
    }
    return '${result.stdout}'.split('\n').first.trim();
  }

  /// How long [file] runs for.
  Future<Duration> durationOf(File file) async {
    final ProcessResult result = await _run(ffprobe, <String>[
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      file.path,
    ]);
    final double? seconds = double.tryParse('${result.stdout}'.trim());
    if (result.exitCode != 0 || seconds == null) {
      throw ProcessingException(
        file.path,
        'Could not read the length of this recording: ${result.stderr}',
      );
    }
    return Duration(microseconds: (seconds * 1000000).round());
  }

  /// The silences in [file], as ffmpeg's `silencedetect` filter reports them.
  ///
  /// [threshold] is in dBFS and [minimumSilence] is how long a gap has to be
  /// before it counts as a break between ayahs. Both are the operator's to
  /// tune: a reciter with a slow, breathy style needs a longer minimum than
  /// one who runs ayahs together.
  Future<List<AudioSegment>> detectSilences(
    File file, {
    double threshold = defaultThresholdDb,
    Duration minimumSilence = const Duration(milliseconds: 600),
  }) async {
    final double seconds = minimumSilence.inMilliseconds / 1000;
    final ProcessResult result = await _run(ffmpeg, <String>[
      '-hide_banner',
      '-i',
      file.path,
      // `-vn`, and it is load-bearing: a recording with embedded cover art
      // carries a video stream, and without this ffmpeg maps the artwork,
      // finishes after its single frame, and reports no silences at all — a
      // two-hour surah then "splits" into one segment.
      '-vn',
      '-af',
      'silencedetect=noise=${threshold}dB:d=$seconds',
      '-f',
      'null',
      '-',
    ]);
    // silencedetect writes to stderr even on success; a non-zero exit is the
    // only real failure.
    if (result.exitCode != 0) {
      throw ProcessingException(
        file.path,
        'ffmpeg could not read this recording: ${result.stderr}',
      );
    }
    return parseSilences('${result.stderr}');
  }

  /// Parses `silence_start` / `silence_end` lines. Public for its tests: this
  /// is where a format change would silently produce one giant segment.
  static List<AudioSegment> parseSilences(String stderr) {
    final RegExp start = RegExp(r'silence_start:\s*([0-9.]+)');
    final RegExp end = RegExp(r'silence_end:\s*([0-9.]+)');

    final List<Duration> starts = <Duration>[
      for (final RegExpMatch m in start.allMatches(stderr))
        _secondsToDuration(m.group(1)!),
    ];
    final List<Duration> ends = <Duration>[
      for (final RegExpMatch m in end.allMatches(stderr))
        _secondsToDuration(m.group(1)!),
    ];

    return List<AudioSegment>.unmodifiable(<AudioSegment>[
      for (int i = 0; i < starts.length && i < ends.length; i++)
        AudioSegment(start: starts[i], end: ends[i]),
    ]);
  }

  /// Writes one segment of [source] to [destination], re-encoded at
  /// [bitrate] kbps.
  ///
  /// Re-encoded rather than stream-copied on purpose: a copy can only cut on a
  /// frame boundary, which moves a cut by up to 26 ms and can clip the first
  /// syllable of an ayah.
  Future<File> exportSegment({
    required File source,
    required File destination,
    required AudioSegment segment,
    required int bitrate,
  }) async {
    destination.parent.createSync(recursive: true);
    if (destination.existsSync()) destination.deleteSync();

    // Seek before `-i`, not after. After it, ffmpeg decodes from the start of
    // the file for every segment — fine for a short surah, and three hours of
    // work for Al-Baqarah's 287. Before it, ffmpeg jumps near the offset and
    // decodes only what follows.
    //
    // The jump lands on a frame boundary rather than exactly, so it aims a
    // second early and trims the rest off precisely with a second, output-side
    // seek: fast *and* landing where it was told, which matters when the cut
    // is the start of an ayah.
    final Duration preroll = segment.start < _preroll
        ? segment.start
        : _preroll;
    final ProcessResult result = await _run(ffmpeg, <String>[
      '-hide_banner',
      '-y',
      '-ss',
      _ffmpegTime(segment.start - preroll),
      '-i',
      source.path,
      '-ss',
      _ffmpegTime(preroll),
      '-t',
      _ffmpegTime(segment.duration),
      '-vn',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '${bitrate}k',
      // One channel: recitation is a single voice, and stereo doubles the
      // bytes a phone has to download for nothing.
      '-ac',
      '1',
      destination.path,
    ]);

    if (result.exitCode != 0 || !destination.existsSync()) {
      throw ProcessingException(
        destination.path,
        'ffmpeg could not write this segment: ${result.stderr}',
      );
    }
    return destination;
  }

  /// How far before a cut the fast seek aims, so the accurate seek has frames
  /// to work with.
  static const Duration _preroll = Duration(seconds: 1);

  static Duration _secondsToDuration(String value) =>
      Duration(microseconds: ((double.tryParse(value) ?? 0) * 1000000).round());

  /// `HH:MM:SS.mmm`, which ffmpeg accepts for both `-ss` and `-to`.
  static String _ffmpegTime(Duration d) {
    final String hours = d.inHours.toString().padLeft(2, '0');
    final String minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    final String millis = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds.$millis';
  }
}
