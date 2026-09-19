import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/data/models/surah.dart';

/// The same pipeline the admin tool runs, against the real `ffmpeg` on this
/// machine.
///
/// The unit tests pin the parsing and the arguments; this pins the assumption
/// underneath them — that a given ffmpeg build still writes `silence_start` the
/// way the regex expects, and still cuts where it is told. A future ffmpeg that
/// changes either would otherwise show up as one giant segment in front of an
/// operator, not as a failing test.
///
/// Skipped where ffmpeg is absent: it is the operator's tool, not the app's.
void main() {
  final bool hasFfmpeg =
      Process.runSync('which', <String>['ffmpeg']).exitCode == 0;

  group(
    'the real ffmpeg',
    skip: hasFfmpeg ? null : 'ffmpeg is not on PATH',
    () {
      late Directory dir;
      late File recording;
      final FfmpegRunner runner = FfmpegRunner();

      setUpAll(() async {
        dir = Directory.systemTemp.createTempSync('mirqat_ffmpeg_real');
        recording = File('${dir.path}/surah.mp3');

        // Three one-second tones separated by one second of silence: a
        // stand-in for three ayahs with a breath between them.
        final ProcessResult built = Process.runSync('ffmpeg', <String>[
          '-hide_banner',
          '-y',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:duration=1',
          '-f',
          'lavfi',
          '-i',
          'anullsrc=r=44100:cl=mono:duration=1',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=520:duration=1',
          '-f',
          'lavfi',
          '-i',
          'anullsrc=r=44100:cl=mono:duration=1',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=660:duration=1',
          '-filter_complex',
          '[0][1][2][3][4]concat=n=5:v=0:a=1',
          '-ac',
          '1',
          '-b:a',
          '64k',
          recording.path,
        ]);
        expect(
          built.exitCode,
          0,
          reason: 'could not build the fixture recording: ${built.stderr}',
        );
      });

      tearDownAll(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      test('reports a version', () async {
        expect(await runner.version(), contains('ffmpeg version'));
      });

      test('measures the recording', () async {
        final Duration length = await runner.durationOf(recording);

        expect(length.inMilliseconds, greaterThan(4800));
        expect(length.inMilliseconds, lessThan(5400));
      });

      test('finds the two silences and splits into three segments', () async {
        final List<AudioSegment> silences = await runner.detectSilences(
          recording,
          minimumSilence: const Duration(milliseconds: 400),
        );
        expect(silences, hasLength(2));

        const SegmentPlanner planner = SegmentPlanner();
        final List<AudioSegment> segments = planner.segmentsFrom(
          totalDuration: await runner.durationOf(recording),
          silences: silences,
        );

        expect(segments, hasLength(3));
        // Cut in the middle of each silence: around 1.5 s and 3.5 s.
        expect(segments[0].end.inMilliseconds, closeTo(1500, 250));
        expect(segments[1].end.inMilliseconds, closeTo(3500, 250));

        // And a three-ayah surah with no separate basmala matches exactly.
        const Surah surah = Surah(
          number: 3,
          nameAr: 'س',
          nameEn: 'Three',
          ayahCount: 3,
          revelationPlace: RevelationPlace.makkah,
          bismillahMode: BismillahMode.none,
        );
        expect(
          SegmentPlan(surah: surah, segments: segments).countMatches,
          isTrue,
        );
      });

      test('exports a segment of the length it was asked for', () async {
        final File out = File('${dir.path}/003002.mp3');

        await runner.exportSegment(
          source: recording,
          destination: out,
          segment: const AudioSegment(
            start: Duration(milliseconds: 1500),
            end: Duration(milliseconds: 3500),
          ),
          bitrate: 64,
        );

        expect(out.existsSync(), isTrue);
        expect(out.lengthSync(), greaterThan(0));
        expect(
          (await runner.durationOf(out)).inMilliseconds,
          closeTo(2000, 150),
        );
      });
    },
  );
}
