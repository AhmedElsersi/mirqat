/// The splitter's second look with finer ears: a reciter who barely breathes
/// between ayahs leaves pauses shorter than the candidate minimum, and the
/// split used to come back short until an operator lowered the minimum by
/// hand from the command line. Now the splitter tries half the minimum itself
/// before reporting anything — and leaves recordings the first pass served
/// well alone.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/surah_splitter.dart';
import 'package:mirqat/data/models/surah.dart';

const Surah _surah = Surah(
  number: 103,
  nameAr: 'العصر',
  nameEn: 'Al-Asr',
  ayahCount: 3,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.none,
);

/// One silencedetect line pair at [seconds].
String _pause(double seconds) =>
    '[silencedetect] silence_start: ${seconds - 0.1}\n'
    '[silencedetect] silence_end: ${seconds + 0.1} | '
    'silence_duration: 0.2\n';

/// An ffmpeg whose recording holds one generous pause (at 8 s) and one short
/// breath (at 4 s) that only a detection run with `d=` below 0.18 can see —
/// and which counts how many of those finer runs were asked for.
FfmpegRunner _shortBreathed({
  required List<double> finerMinimums,
  bool breathAtDefault = false,
}) => FfmpegRunner(
  run: (String executable, List<String> args) async {
    if (executable == 'ffprobe') return ProcessResult(0, 0, '12.0', '');
    if (args.contains('-version')) {
      return ProcessResult(0, 0, 'ffmpeg version 7.1', '');
    }
    final String filter = args.firstWhere(
      (String a) => a.startsWith('silencedetect'),
      orElse: () => '',
    );
    if (filter.isEmpty) return ProcessResult(0, 0, '', '');
    final double minimum = double.parse(filter.split(':d=').last);
    if (minimum < 0.18) finerMinimums.add(minimum);
    final bool seesTheBreath = breathAtDefault || minimum < 0.18;
    return ProcessResult(
      0,
      0,
      '',
      '${seesTheBreath ? _pause(4) : ''}${_pause(8)}',
    );
  },
);

void main() {
  late File source;

  setUp(() {
    source = File(
      '${Directory.systemTemp.createTempSync('mirqat_splitter').path}/103.mp3',
    )..writeAsStringSync('audio');
  });

  tearDown(() => source.parent.deleteSync(recursive: true));

  test('pauses too short for the default minimum are found at half of it, '
      'and the split comes out whole', () async {
    final List<double> finer = <double>[];
    final SplitResult result =
        await SurahSplitter(ffmpeg: _shortBreathed(finerMinimums: finer)).split(
          source: source,
          surah: _surah,
          weights: const <int>[1, 1, 1],
          thresholdDb: -30,
          minimumSilence: const Duration(milliseconds: 300),
        );

    expect(finer, isNotEmpty, reason: 'the finer sweep should have run');
    expect(finer, everyElement(closeTo(0.09, 0.0001)));
    expect(result.plan.actualCount, 3);
    expect(result.plan.countMatches, isTrue);
    expect(result.method, SplitMethod.aligned);
    expect(result.suspects, isEmpty);
  });

  test(
    'a recording the first pass splits cleanly is never swept again',
    () async {
      final List<double> finer = <double>[];
      final SplitResult result =
          await SurahSplitter(
            ffmpeg: _shortBreathed(finerMinimums: finer, breathAtDefault: true),
          ).split(
            source: source,
            surah: _surah,
            weights: const <int>[1, 1, 1],
            thresholdDb: -30,
            minimumSilence: const Duration(milliseconds: 300),
          );

      expect(result.plan.countMatches, isTrue);
      expect(result.suspects, isEmpty);
      expect(
        finer,
        isEmpty,
        reason: 'a clean first split must not pay for eight more decodes',
      );
    },
  );
}
