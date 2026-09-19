import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:http/testing.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/cubit/admin_cubit.dart';
import 'package:mirqat/admin/cubit/admin_state.dart';
import 'package:mirqat/admin/services/admin_file_picker.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/pack_publisher.dart';
import 'package:mirqat/admin/services/pages_publisher.dart';
import 'package:mirqat/admin/services/publish_guard.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/admin/services/segment_preview.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';

import '../quran_db_fixtures.dart';
import '../text_comparison.dart';

const AdminConfig config = AdminConfig(
  accountId: 'acc',
  accessKey: 'key',
  secretKey: 'secret',
  bucket: 'iqra-cdn',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
);

/// Two silences in a twelve-second recording — three segments, which is what
/// the fixture surahs have ayahs.
const String silences = '''
[silencedetect] silence_start: 3.9
[silencedetect] silence_end: 4.1 | silence_duration: 0.2
[silencedetect] silence_start: 7.9
[silencedetect] silence_end: 8.1 | silence_duration: 0.2
''';

/// One real break, at 8 s. Even the sensitive pass finds only two pauses, one
/// short of the three cuts a four-segment surah needs, so no alignment is
/// possible and the split stays a mismatch for the operator to deal with.
const String oneSilence = '''
[silencedetect] silence_start: 7.9
[silencedetect] silence_end: 8.1 | silence_duration: 0.2
''';

/// Stands in for the binary: answers `-version`, `ffprobe`, `silencedetect`
/// and an export, and records every export it was asked for.
class _Ffmpeg extends FfmpegRunner {
  _Ffmpeg({this.silenceOutput = silences})
    : super(
        run: (String executable, List<String> args) async {
          if (executable == 'ffprobe') return ProcessResult(0, 0, '12.0', '');
          if (args.contains('-version')) {
            return ProcessResult(0, 0, 'ffmpeg version 7.1', '');
          }
          final String filter = args.firstWhere(
            (String a) => a.startsWith('silencedetect'),
            orElse: () => '',
          );
          if (filter.isNotEmpty) {
            // The candidate sweep sees one more, shorter quiet moment — at
            // 3 s, between the basmala and ayah 1. Only the sweep asks at
            // -45 dB (the runner formats it as `noise=-45.0dB`); the plain
            // split asks at the operator's threshold.
            final bool sensitive = filter.contains('=-45');
            return ProcessResult(
              0,
              0,
              '',
              sensitive && silenceOutput.isNotEmpty
                  ? '$silenceOutput'
                        '[silencedetect] silence_start: 2.9\n'
                        '[silencedetect] silence_end: 3.1 | silence_duration: 0.2\n'
                  : silenceOutput,
            );
          }
          // An export: write the destination so the runner is satisfied.
          File(args.last).writeAsStringSync('mp3');
          exported.add(args.last);
          return ProcessResult(0, 0, '', '');
        },
      );

  final String silenceOutput;
  static final List<String> exported = <String>[];
}

/// Stands in for the audio device: records what it was asked to play.
class _Preview implements SegmentPreview {
  final List<(Duration, Duration)> played = <(Duration, Duration)>[];
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  int stops = 0;

  @override
  Future<void> play(
    File source, {
    required Duration from,
    required Duration to,
  }) async {
    played.add((from, to));
    _playing.add(true);
  }

  @override
  Future<void> stop() async {
    stops++;
    _playing.add(false);
  }

  /// The recording ran out on its own.
  void finish() => _playing.add(false);

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Future<void> dispose() => _playing.close();
}

/// Stands in for the macOS open panel.
class _Picker implements AdminFilePicker {
  _Picker(this.answer);

  /// A path, null for a cancelled panel, or a thrown error.
  final Object? answer;
  int calls = 0;

  @override
  Future<String?> pickRecording() async {
    calls++;
    final Object? answer = this.answer;
    if (answer is Exception) throw answer;
    return answer as String?;
  }

  @override
  Future<String?> pickImage() async => null;
}

void main() {
  late Directory recordingDir;
  late File recording;
  late List<String> uploaded;

  setUp(() {
    _Ffmpeg.exported.clear();
    uploaded = <String>[];
    recordingDir = Directory.systemTemp.createTempSync('mirqat_admin_src');
    recording = File('${recordingDir.path}/112.mp3')
      ..writeAsStringSync('whole surah');
  });

  tearDown(() {
    if (recordingDir.existsSync()) recordingDir.deleteSync(recursive: true);
  });

  AdminCubit open({
    QuranRepository? quran,
    String silenceOutput = silences,
    AdminFilePicker? picker,
    SegmentPreview? preview,
  }) {
    final AdminCubit cubit = AdminCubit(
      quranRepository: quran ?? fixtureRepository(),
      adminConfig: config,
      filePicker: picker ?? _Picker(null),
      segmentPreview: preview,
      ffmpegRunner: _Ffmpeg(silenceOutput: silenceOutput),
      r2Client: R2Client(
        adminConfig: config,
        client: MockClient((http.Request request) async {
          if (request.method == 'HEAD') return http.Response('', 404);
          uploaded.add(request.url.path);
          return http.Response('', 200);
        }),
      ),
      packPublisher: PackPublisher(
        manifestUrl: 'https://example.invalid/manifest.json',
        // No manifest published yet — the state this CDN was actually in.
        client: MockClient((http.Request _) async => http.Response('', 404)),
      ),
      // No GitHub credentials in `config`, so the tool writes the manifest and
      // says so rather than publishing it — the path a build without a token
      // takes.
      pagesPublisher: PagesPublisher(
        adminConfig: config,
        client: MockClient((http.Request _) async => http.Response('', 200)),
      ),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  test('the surah dropdown is the catalog, not a list kept here', () async {
    final AdminCubit cubit = open();

    await cubit.load();

    expect(cubit.state.status, LoadStatus.ready);
    // The fixture catalog has three surahs; the real one has 114. Either way
    // it comes from quran.db.
    expect(cubit.state.surahs.map((Surah s) => s.number), <int>[1, 2, 3]);
    expect(cubit.state.ffmpegVersion, 'ffmpeg version 7.1');
  });

  test('a missing ffmpeg stops the tool before anything else', () async {
    final AdminCubit cubit = AdminCubit(
      quranRepository: fixtureRepository(),
      adminConfig: config,
      ffmpegRunner: FfmpegRunner(
        run: (String executable, List<String> _) async =>
            throw ProcessException(executable, <String>[], 'not found'),
      ),
      r2Client: R2Client(
        adminConfig: config,
        client: MockClient((_) async => http.Response('', 200)),
      ),
    );
    addTearDown(cubit.close);

    await cubit.load();

    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.errorMessage, contains('brew install ffmpeg'));
    expect(cubit.state.surahs, isEmpty);
  });

  test('the ayah text beside a segment is quran.db byte for byte', () async {
    final AdminCubit cubit = open();
    await cubit.load();

    await cubit.selectSurah(
      cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
    );

    expect(cubit.state.ayahs, hasLength(3));
    // The fixture text is a bare bāʼ; the point is that whatever came out of
    // the database is what the cubit holds — no trimming, no normalising.
    // `skeletonForComparison` is a test helper and lives only here.
    for (final String text in cubit.state.ayahs.map((a) => a.text)) {
      expect(text, 'ب');
      expect(skeletonForComparison(text), skeletonForComparison('ب'));
    }
  });

  test('splitting a segment cuts at the quiet moment the sensitive pass '
      'found', () async {
    final AdminCubit cubit = open(silenceOutput: oneSilence);
    await cubit.load();
    await cubit.selectSurah(
      cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
    );
    cubit
      ..setReciterId('shaheen')
      ..selectSource(recording.path);

    await cubit.split();
    // One break, at 8 s: the first segment runs 0 → 8 s, and there are too
    // few pauses for the aligner to have fixed it on its own.
    expect(cubit.state.plan!.segments.first.end, const Duration(seconds: 8));

    cubit.splitSegment(0);

    // Cut at the quiet moment inside it, not at 4 s, which is where halving
    // would have landed.
    expect(cubit.state.plan!.segments.first.end, const Duration(seconds: 3));
    expect(cubit.state.plan!.actualCount, 3);
  });

  test(
    'a segment with nowhere quiet to cut says so instead of halving it',
    () async {
      final AdminCubit cubit = open(silenceOutput: '');
      await cubit.load();
      await cubit.selectSurah(
        cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
      );
      cubit
        ..setReciterId('shaheen')
        ..selectSource(recording.path);
      await cubit.split();

      cubit.splitSegment(0);

      expect(cubit.state.errorMessage, contains('No quiet moment'));
      expect(cubit.state.plan!.actualCount, 1);
    },
  );

  test('a matching split publishes every segment, basmala as 000', () async {
    final AdminCubit cubit = open();
    await cubit.load();
    // Surah 2 in the fixture catalog has three ayahs and a separate basmala,
    // so four segments are expected — and the recording has four.
    await cubit.selectSurah(
      cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
    );
    cubit
      ..setReciterId('shaheen')
      ..selectSource(recording.path);

    await cubit.split();
    // The threshold alone sees two breaks and would stop at three segments.
    // The break it missed — the short one between the basmala and ayah 1 —
    // is among the candidates, and the text says four segments belong here,
    // so Split finds it without the operator hunting for it.
    expect(cubit.state.plan!.expectedCount, 4);
    expect(cubit.state.plan!.actualCount, 4);
    expect(cubit.state.plan!.segments.first.end, const Duration(seconds: 3));
    expect(cubit.state.decision, isA<PublishAllowed>());

    await cubit.publish();

    expect(cubit.state.stage, AdminStage.published);
    // The ayahs, and then the pack — without which the app can stream the
    // surah but never download it.
    expect(uploaded, <String>[
      '/iqra-cdn/audio/shaheen/64/002000.mp3',
      '/iqra-cdn/audio/shaheen/64/002001.mp3',
      '/iqra-cdn/audio/shaheen/64/002002.mp3',
      '/iqra-cdn/audio/shaheen/64/002003.mp3',
      '/iqra-cdn/packs/shaheen/64/002.zip',
    ]);

    // And the manifest entry, without which the app cannot see it at all.
    final File manifest = File('${recordingDir.path}/manifest.json');
    expect(manifest.existsSync(), isTrue);
    final Map<String, dynamic> written =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    final Map<String, dynamic> reciter =
        (written['reciters'] as List<dynamic>).single as Map<String, dynamic>;
    expect(reciter['id'], 'shaheen');
    expect(reciter['bitrate'], 64);
    final Map<String, dynamic> surah =
        (reciter['surahs'] as List<dynamic>).single as Map<String, dynamic>;
    expect(surah['n'], 2);
    expect(surah['ayahs'], 3, reason: 'the ayah count comes from quran.db');
    expect(surah['hasBasmala'], isTrue);
    expect(surah['sha256'], isNotEmpty);
    expect(written['baseUrl'], config.publicBase);
    expect(
      cubit.state.log.any((String line) => line.contains('manifest.json')),
      isTrue,
    );
  });

  test('a mismatched split uploads nothing until a reason is typed', () async {
    final AdminCubit cubit = open(silenceOutput: oneSilence);
    await cubit.load();
    await cubit.selectSurah(
      cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
    );
    cubit
      ..setReciterId('shaheen')
      ..selectSource(recording.path);
    await cubit.split();

    // Two segments where four are expected, and too few pauses to align.
    expect(cubit.state.plan!.actualCount, 2);
    await cubit.publish();
    expect(uploaded, isEmpty);
    expect(cubit.state.errorMessage, contains('expected 4'));

    // A token reason is not a decision.
    cubit.setOverrideReason('fine');
    await cubit.publish();
    expect(uploaded, isEmpty);

    // A real one publishes, and the log records it.
    cubit.setOverrideReason('Only the opening was recorded; ayah 1 onward.');
    await cubit.publish();

    // The two segments there are, and the pack.
    expect(uploaded, hasLength(3));
    expect(
      cubit.state.log.any((String line) => line.startsWith('OVERRIDE:')),
      isTrue,
    );
    expect(
      cubit.state.log.any((String line) => line.contains('ayah 1 onward')),
      isTrue,
    );
  });

  test('a recording that starts at ayah 1 publishes no basmala, and says so '
      'in the manifest', () async {
    final AdminCubit cubit = open();
    await cubit.load();
    await cubit.selectSurah(
      cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
    );
    cubit
      ..setReciterId('shaheen')
      ..selectSource(recording.path)
      // What used to need a typed override is now a fact the operator states.
      ..setRecordingHasBasmala(false);

    await cubit.split();
    expect(cubit.state.plan!.expectedCount, 3);
    expect(cubit.state.plan!.actualCount, 3);
    expect(cubit.state.decision, isA<PublishAllowed>());

    await cubit.publish();

    expect(uploaded, <String>[
      '/iqra-cdn/audio/shaheen/64/002001.mp3',
      '/iqra-cdn/audio/shaheen/64/002002.mp3',
      '/iqra-cdn/audio/shaheen/64/002003.mp3',
      '/iqra-cdn/packs/shaheen/64/002.zip',
    ]);
    final Map<String, dynamic> written =
        jsonDecode(
              File('${recordingDir.path}/manifest.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final Map<String, dynamic> surah =
        (((written['reciters'] as List<dynamic>).single
                        as Map<String, dynamic>)['surahs']
                    as List<dynamic>)
                .single
            as Map<String, dynamic>;
    // False, so the app never asks the CDN for a 002000.mp3 nobody made.
    expect(surah['hasBasmala'], isFalse);
  });

  test("an isti'adhah is cut off and never uploaded", () async {
    final AdminCubit cubit = open();
    await cubit.load();
    await cubit.selectSurah(
      cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
    );
    cubit
      ..setReciterId('shaheen')
      ..selectSource(recording.path)
      ..setRecordingHasBasmala(false)
      ..setRecordingHasIstiadhah(true);

    await cubit.split();
    // isti'adhah + three ayahs, from the three pauses the sweep finds.
    expect(cubit.state.plan!.expectedCount, 4);
    expect(cubit.state.plan!.actualCount, 4);
    expect(cubit.state.plan!.planned.first.isIstiadhah, isTrue);

    await cubit.publish();

    expect(uploaded, <String>[
      '/iqra-cdn/audio/shaheen/64/002001.mp3',
      '/iqra-cdn/audio/shaheen/64/002002.mp3',
      '/iqra-cdn/audio/shaheen/64/002003.mp3',
      '/iqra-cdn/packs/shaheen/64/002.zip',
    ]);
  });

  group('listening and hand edits', () {
    Future<AdminCubit> splitSurah2(_Preview preview) async {
      final AdminCubit cubit = open(preview: preview);
      await cubit.load();
      await cubit.selectSurah(
        cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
      );
      cubit
        ..setReciterId('shaheen')
        ..selectSource(recording.path);
      await cubit.split();
      // 0–3 basmala, 3–4 ayah 1, 4–8 ayah 2, 8–12 ayah 3.
      expect(cubit.state.plan!.actualCount, 4);
      return cubit;
    }

    test(
      'a segment plays from the recording, between its own two times',
      () async {
        final _Preview preview = _Preview();
        final AdminCubit cubit = await splitSurah2(preview);

        await cubit.previewSegment(2);

        expect(preview.played.single, (
          const Duration(seconds: 4),
          const Duration(seconds: 8),
        ));
        expect(cubit.state.previewingIndex, 2);
      },
    );

    test('pressing play on what is playing stops it', () async {
      final _Preview preview = _Preview();
      final AdminCubit cubit = await splitSurah2(preview);

      await cubit.previewSegment(2);
      await cubit.previewSegment(2);

      expect(preview.stops, greaterThan(0));
      expect(cubit.state.previewingIndex, isNull);
    });

    test('the button goes back to play when the clip runs out', () async {
      final _Preview preview = _Preview();
      final AdminCubit cubit = await splitSurah2(preview);

      await cubit.previewSegment(1);
      preview.finish();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.previewingIndex, isNull);
    });

    test('the ending, and across the end, are the last few seconds and the '
        'seconds either side', () async {
      final _Preview preview = _Preview();
      final AdminCubit cubit = await splitSurah2(preview);

      await cubit.previewSegment(2, part: PreviewPart.ending);
      await cubit.previewSegment(2, part: PreviewPart.acrossEnd);
      // A one-second ayah has no "last three seconds": it plays whole.
      await cubit.previewSegment(1, part: PreviewPart.ending);

      expect(preview.played, <(Duration, Duration)>[
        (const Duration(seconds: 5), const Duration(seconds: 8)),
        (const Duration(seconds: 5), const Duration(seconds: 11)),
        (const Duration(seconds: 3), const Duration(seconds: 4)),
      ]);
    });

    test('a boundary moved by hand moves both neighbours and keeps the '
        'count', () async {
      final AdminCubit cubit = await splitSurah2(_Preview());

      cubit.moveBoundary(2, const Duration(milliseconds: 4600));
      await Future<void>.delayed(Duration.zero);

      final List<AudioSegment> segments = cubit.state.plan!.segments;
      expect(segments[1].end, const Duration(milliseconds: 4600));
      expect(segments[2].start, const Duration(milliseconds: 4600));
      expect(cubit.state.plan!.actualCount, 4);
      expect(cubit.state.decision, isA<PublishAllowed>());
    });

    test('a nudge is relative, and what is then played is the edited '
        'segment', () async {
      final _Preview preview = _Preview();
      final AdminCubit cubit = await splitSurah2(preview);

      cubit.nudgeBoundary(3, const Duration(milliseconds: -500));
      await Future<void>.delayed(Duration.zero);
      await cubit.previewSegment(2);

      expect(preview.played.single, (
        const Duration(seconds: 4),
        const Duration(milliseconds: 7500),
      ));
    });

    test('joined is the default: moving an end takes the next start with '
        'it', () async {
      final AdminCubit cubit = await splitSurah2(_Preview());

      cubit.moveEdge(2, SegmentEdge.end, const Duration(milliseconds: 7400));
      await Future<void>.delayed(Duration.zero);

      final SegmentPlan plan = cubit.state.plan!;
      expect(plan.segments[2].end, const Duration(milliseconds: 7400));
      expect(plan.segments[3].start, const Duration(milliseconds: 7400));
      expect(plan.gapAfter(2), Duration.zero);
    });

    test('unjoined, the rest is cut out: the next segment stays where it '
        'was and the gap is exported to no clip', () async {
      final AdminCubit cubit = await splitSurah2(_Preview());

      cubit.moveEdge(
        2,
        SegmentEdge.end,
        const Duration(milliseconds: 7400),
        joined: false,
      );
      await Future<void>.delayed(Duration.zero);

      final SegmentPlan plan = cubit.state.plan!;
      expect(plan.segments[2].end, const Duration(milliseconds: 7400));
      expect(plan.segments[3].start, const Duration(seconds: 8));
      expect(plan.gapAfter(2), const Duration(milliseconds: 600));
      // Still four segments, still publishable: a gap is not a mismatch.
      expect(cubit.state.decision, isA<PublishAllowed>());
    });

    test('the same for a start and the segment before it', () async {
      final AdminCubit cubit = await splitSurah2(_Preview());

      cubit.moveEdge(
        2,
        SegmentEdge.start,
        const Duration(milliseconds: 4500),
        joined: false,
      );
      await Future<void>.delayed(Duration.zero);

      final SegmentPlan plan = cubit.state.plan!;
      expect(plan.segments[2].start, const Duration(milliseconds: 4500));
      expect(plan.segments[1].end, const Duration(seconds: 4));
      expect(plan.gapAfter(1), const Duration(milliseconds: 500));
    });

    test('a nudge is measured from the edge being edited, even across a '
        'gap', () async {
      final AdminCubit cubit = await splitSurah2(_Preview());

      cubit.moveEdge(
        2,
        SegmentEdge.end,
        const Duration(milliseconds: 7000),
        joined: false,
      );
      await Future<void>.delayed(Duration.zero);
      // From 7.0 s — this segment's end — not from 8.0 s, its neighbour's start.
      cubit.nudgeEdge(
        2,
        SegmentEdge.end,
        const Duration(milliseconds: 100),
        joined: false,
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        cubit.state.plan!.segments[2].end,
        const Duration(milliseconds: 7100),
      );
    });

    test('a new split stops whatever was playing', () async {
      final _Preview preview = _Preview();
      final AdminCubit cubit = await splitSurah2(preview);

      await cubit.previewSegment(0);
      await cubit.split();

      expect(preview.stops, greaterThan(0));
      expect(cubit.state.previewingIndex, isNull);
    });
  });

  test(
    'changing what the recording holds drops the split made before',
    () async {
      final AdminCubit cubit = open();
      await cubit.load();
      await cubit.selectSurah(
        cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
      );
      cubit
        ..setReciterId('shaheen')
        ..selectSource(recording.path);
      await cubit.split();
      expect(cubit.state.plan, isNotNull);

      // Segments counted under one answer must not be published under another.
      cubit.setRecordingHasIstiadhah(true);
      expect(cubit.state.plan, isNull);
    },
  );

  test(
    'Al-Fatiha expects no basmala segment, so segment 0 is ayah 1',
    () async {
      final AdminCubit cubit = open();
      await cubit.load();
      // Surah 1 in the fixture catalog is `first_ayah`, like Al-Fatiha.
      await cubit.selectSurah(
        cubit.state.surahs.firstWhere((Surah s) => s.number == 1),
      );
      cubit
        ..setReciterId('shaheen')
        ..selectSource(recording.path);

      await cubit.split();

      expect(cubit.state.plan!.expectsBasmala, isFalse);
      expect(cubit.state.plan!.expectedCount, 3);
      expect(cubit.state.plan!.planned.first.ayahNumber, 1);
      expect(cubit.state.decision, isA<PublishAllowed>());

      await cubit.publish();

      expect(uploaded.first, endsWith('001001.mp3'));
      expect(uploaded, isNot(contains(endsWith('001000.mp3'))));
    },
  );

  group('choosing a recording', () {
    test('the panel answers a path, and the tool takes it', () async {
      final _Picker picker = _Picker(recording.path);
      final AdminCubit cubit = open(picker: picker);
      await cubit.load();

      await cubit.chooseSource();

      expect(picker.calls, 1);
      expect(cubit.state.sourcePath, recording.path);
      expect(cubit.state.errorMessage, isNull);
    });

    test('cancelling keeps the recording already chosen', () async {
      final AdminCubit cubit = open(picker: _Picker(null));
      await cubit.load();
      cubit.selectSource(recording.path);

      await cubit.chooseSource();

      // A stray Escape must not cost the operator the path they picked.
      expect(cubit.state.sourcePath, recording.path);
      expect(cubit.state.errorMessage, isNull);
    });

    test('choosing another surah drops the split too', () async {
      final AdminCubit cubit = open(picker: _Picker(recording.path));
      await cubit.load();
      await cubit.selectSurah(cubit.state.surahs.first);
      cubit
        ..setReciterId('shaheen')
        ..selectSource(recording.path);
      await cubit.split();
      expect(cubit.state.plan, isNotNull);

      await cubit.selectSurah(cubit.state.surahs.last);

      // Segments cut from another surah's recording must never be published
      // under this one's numbers.
      expect(cubit.state.plan, isNull);
    });

    test(
      'choosing a new recording drops the split made from the old one',
      () async {
        final AdminCubit cubit = open(picker: _Picker(recording.path));
        await cubit.load();
        await cubit.selectSurah(cubit.state.surahs.first);
        cubit
          ..setReciterId('shaheen')
          ..selectSource(recording.path);
        await cubit.split();
        expect(cubit.state.plan, isNotNull);

        await cubit.chooseSource();

        expect(cubit.state.plan, isNull, reason: 'a new file is a new split');
        expect(cubit.state.stage, AdminStage.idle);
      },
    );

    test('a build with no panel says so instead of failing silently', () async {
      final AdminCubit cubit = open(
        picker: _Picker(MissingPluginException('no channel')),
      );
      await cubit.load();

      await cubit.chooseSource();

      expect(cubit.state.sourcePath, isNull);
      expect(cubit.state.errorMessage, contains('run_admin.sh'));
    });
  });

  test('nothing is uploaded when the credentials would be needed but the '
      'split is empty', () async {
    final AdminCubit cubit = open(silenceOutput: '');
    await cubit.load();
    await cubit.selectSurah(cubit.state.surahs.first);
    cubit
      ..setReciterId('shaheen')
      ..selectSource(recording.path);
    await cubit.split();
    await cubit.publish();

    expect(uploaded, isEmpty);
  });
}
