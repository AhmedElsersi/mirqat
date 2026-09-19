import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/core/error/exceptions.dart';

/// Real `silencedetect` output, as ffmpeg writes it to stderr.
const String silenceOutput = '''
[silencedetect @ 0x14b606060] silence_start: 4.52
[silencedetect @ 0x14b606060] silence_end: 5.31 | silence_duration: 0.79
[silencedetect @ 0x14b606060] silence_start: 9.014
[silencedetect @ 0x14b606060] silence_end: 9.802 | silence_duration: 0.788
size=N/A time=00:00:12.00 bitrate=N/A speed=  46x
''';

void main() {
  test('silences are parsed out of ffmpeg stderr', () {
    final List<AudioSegment> silences = FfmpegRunner.parseSilences(
      silenceOutput,
    );

    expect(silences, hasLength(2));
    expect(silences.first.start, const Duration(milliseconds: 4520));
    expect(silences.first.end, const Duration(milliseconds: 5310));
    expect(silences.last.start, const Duration(milliseconds: 9014));
    expect(silences.last.end, const Duration(milliseconds: 9802));
  });

  test('a run with no silences parses as none, not as a failure', () {
    expect(FfmpegRunner.parseSilences('size=N/A time=00:00:03.00'), isEmpty);
  });

  test('a missing ffmpeg is reported by name, with what to install', () async {
    final FfmpegRunner runner = FfmpegRunner(
      run: (String executable, List<String> _) async =>
          throw ProcessException(executable, <String>[], 'No such file'),
    );

    await expectLater(
      runner.version,
      throwsA(
        isA<ToolMissingException>().having(
          (ToolMissingException e) => e.tool,
          'tool',
          'ffmpeg',
        ),
      ),
    );
  });

  test('a non-zero ffmpeg -version is a missing tool too', () async {
    final FfmpegRunner runner = FfmpegRunner(
      run: (_, _) async => ProcessResult(0, 127, '', 'command not found'),
    );

    await expectLater(runner.version, throwsA(isA<ToolMissingException>()));
  });

  test('the version is the first line of ffmpeg -version', () async {
    final FfmpegRunner runner = FfmpegRunner(
      run: (_, _) async => ProcessResult(
        0,
        0,
        'ffmpeg version 7.1 Copyright (c) 2000-2024\nbuilt with clang',
        '',
      ),
    );

    expect(
      await runner.version(),
      'ffmpeg version 7.1 Copyright (c) 2000-2024',
    );
  });

  test(
    'an export asks ffmpeg for the right window, mono, at the bitrate',
    () async {
      late List<String> args;
      final Directory dir = Directory.systemTemp.createTempSync(
        'mirqat_ffmpeg',
      );
      addTearDown(() => dir.deleteSync(recursive: true));
      final File destination = File('${dir.path}/001002.mp3');

      final FfmpegRunner runner = FfmpegRunner(
        run: (String _, List<String> a) async {
          args = a;
          destination.writeAsStringSync('mp3');
          return ProcessResult(0, 0, '', '');
        },
      );

      await runner.exportSegment(
        source: File('${dir.path}/surah.mp3'),
        destination: destination,
        segment: const AudioSegment(
          start: Duration(milliseconds: 1500),
          end: Duration(milliseconds: 3250),
        ),
        bitrate: 64,
      );

      // Seek before the input — decoding a two-hour file from the start for
      // every one of 287 segments is three hours of work — and then trim
      // precisely with an output-side seek, so the cut still lands where it was
      // told.
      expect(
        args.sublist(0, args.indexOf('-i')),
        containsAllInOrder(<String>['-ss', '00:00:00.500']),
      );
      expect(
        args.sublist(args.indexOf('-i')),
        containsAllInOrder(<String>[
          '-ss',
          '00:00:01.000',
          '-t',
          '00:00:01.750',
        ]),
      );
      expect(args, containsAllInOrder(<String>['-b:a', '64k']));
      expect(args, containsAllInOrder(<String>['-ac', '1']));
      // Re-encoded, not stream-copied: a copy can only cut on a frame boundary
      // and would clip the first syllable.
      expect(args, containsAllInOrder(<String>['-c:a', 'libmp3lame']));
    },
  );

  test('silence detection ignores any video stream', () async {
    // An mp3 with cover art has one. Mapped, ffmpeg ends after that single
    // frame and reports no silences — which reads as "this surah is one
    // segment" for a recording two hours long.
    late List<String> args;
    final FfmpegRunner runner = FfmpegRunner(
      run: (String _, List<String> a) async {
        args = a;
        return ProcessResult(0, 0, '', silenceOutput);
      },
    );

    await runner.detectSilences(File('surah.mp3'));

    expect(args, contains('-vn'));
  });

  test(
    'an export that writes nothing is a failure, not a silent skip',
    () async {
      final Directory dir = Directory.systemTemp.createTempSync(
        'mirqat_ffmpeg',
      );
      addTearDown(() => dir.deleteSync(recursive: true));

      final FfmpegRunner runner = FfmpegRunner(
        run: (_, _) async => ProcessResult(0, 1, '', 'Invalid argument'),
      );

      await expectLater(
        () => runner.exportSegment(
          source: File('${dir.path}/surah.mp3'),
          destination: File('${dir.path}/001001.mp3'),
          segment: const AudioSegment(
            start: Duration.zero,
            end: Duration(seconds: 1),
          ),
          bitrate: 64,
        ),
        throwsA(isA<ProcessingException>()),
      );
    },
  );
}
