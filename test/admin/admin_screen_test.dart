/// The review list: what an operator can do to a clip once it is cut.
///
/// The cubit's own tests cover what each control *does*; these cover that the
/// control is there, is wired to the right segment, and is offered only when
/// it means something — which is the half that a cubit test cannot see and
/// that a tool used by one person is most likely to lose.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/cubit/admin_cubit.dart';
import 'package:mirqat/admin/cubit/admin_state.dart';
import 'package:mirqat/admin/screen/admin_screen.dart';
import 'package:mirqat/admin/screen/admin_text_scale.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/pack_publisher.dart';
import 'package:mirqat/admin/services/pages_publisher.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:mirqat/admin/services/segment_preview.dart';
import 'package:mirqat/admin/services/timecode.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mirqat/core/constants/app_constants.dart';
import 'package:mirqat/core/theme/app_theme.dart';
import 'package:mirqat/data/models/surah.dart';

import '../quran_db_fixtures.dart';

const AdminConfig config = AdminConfig(
  accountId: 'acc',
  accessKey: 'key',
  secretKey: 'secret',
  bucket: 'iqra-cdn',
  endpoint: 'https://acc.r2.cloudflarestorage.com',
  publicBase: 'https://pub-example.r2.dev',
  bitrate: 64,
);

/// Two pauses in a twelve-second recording: basmala, then three ayahs.
const String silences = '''
[silencedetect] silence_start: 3.9
[silencedetect] silence_end: 4.1 | silence_duration: 0.2
[silencedetect] silence_start: 7.9
[silencedetect] silence_end: 8.1 | silence_duration: 0.2
''';

class _Ffmpeg extends FfmpegRunner {
  _Ffmpeg()
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
          if (filter.isEmpty) return ProcessResult(0, 0, '', '');
          // The candidate sweep asks at -45 dB and finds one more, shorter
          // quiet moment — the third cut a four-segment surah needs.
          return ProcessResult(
            0,
            0,
            '',
            filter.contains('=-45')
                ? '$silences'
                      '[silencedetect] silence_start: 2.9\n'
                      '[silencedetect] silence_end: 3.1 | silence_duration: 0.2\n'
                : silences,
          );
        },
      );
}

/// Stands in for the audio device. Injected rather than left to the cubit's
/// lazy one: building a real player in a test opens a platform channel that
/// is not there, and the test hangs instead of failing.
class _Preview implements SegmentPreview {
  final StreamController<bool> _playing = StreamController<bool>.broadcast();
  final StreamController<Duration> _position =
      StreamController<Duration>.broadcast();

  @override
  Future<void> play(
    File source, {
    required Duration from,
    required Duration to,
  }) async => _playing.add(true);

  @override
  Future<void> stop() async => _playing.add(false);

  @override
  Stream<bool> get playing => _playing.stream;

  @override
  Stream<Duration> get position => _position.stream;

  @override
  Future<void> dispose() async {
    await _position.close();
    await _playing.close();
  }
}

void main() {
  late Directory directory;
  late _Preview preview;
  late File recording;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('mirqat_admin_screen');
    recording = File('${directory.path}/002.mp3')..writeAsStringSync('audio');
  });

  /// A window, not a phone: this is a macOS tool with a row of controls per
  /// clip, and the 800x600 a widget test defaults to is smaller than any
  /// window it runs in.
  void asAWindow(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1600, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  AdminCubit open() => AdminCubit(
    quranRepository: fixtureRepository(),
    segmentPreview: preview = _Preview(),
    adminConfig: config,
    ffmpegRunner: _Ffmpeg(),
    r2Client: R2Client(
      adminConfig: config,
      client: MockClient((http.Request _) async => http.Response('', 404)),
    ),
    packPublisher: PackPublisher(
      manifestUrl: 'https://example.invalid/manifest.json',
      client: MockClient((http.Request _) async => http.Response('', 404)),
    ),
    pagesPublisher: PagesPublisher(
      adminConfig: config,
      client: MockClient((http.Request _) async => http.Response('', 200)),
    ),
  );

  /// The screen, with surah 2 split into four segments.
  ///
  /// The cubit's work runs inside [WidgetTester.runAsync]: loading the
  /// catalog and re-checking a clip against its text are real reads of the
  /// fixture database, and a real future inside the fake clock a widget test
  /// runs on never completes — the test hangs rather than fails.
  Future<AdminCubit> pumpSplit(WidgetTester tester) async {
    asAWindow(tester);
    final AdminCubit cubit = open();
    addTearDown(() async => tester.runAsync(cubit.close));

    await tester.runAsync(() async {
      await cubit.load();
      await cubit.selectSurah(
        cubit.state.surahs.firstWhere((Surah s) => s.number == 2),
      );
      cubit
        ..setReciterId('shaheen')
        ..selectSource(recording.path);
      await cubit.split();
    });
    expect(cubit.state.plan!.actualCount, 4);

    await tester.pumpWidget(
      // ScreenUtil, as main_admin.dart does it: AyahText sizes itself with
      // `.sp`, and the review list is nothing but ayahs beside their clips.
      ScreenUtilInit(
        designSize: const Size(
          AppConstants.designWidth,
          AppConstants.designHeight,
        ),
        builder: (BuildContext context, Widget? _) => MaterialApp(
          theme: AppTheme.light,
          // The text-size scope, as main_admin.dart mounts it, so these
          // tests run the screen the operator actually gets.
          builder: (BuildContext context, Widget? child) =>
              AdminTextScaleScope(child: child!),
          home: BlocProvider<AdminCubit>.value(
            value: cubit,
            child: const AdminScreen(),
          ),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  /// Does something to the tool and lets the screen catch up. [body] runs on
  /// the real clock for the same reason [pumpSplit] does. Two pumps, not one:
  /// a burst of emits — a batch finishing — can hand BlocBuilder its last
  /// state while the first frame is already building.
  Future<void> act(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('every clip can be joined to the one after it, except the '
      'last, which has nothing after it', (WidgetTester tester) async {
    final AdminCubit cubit = await pumpSplit(tester);

    final Iterable<IconButton> joins = tester.widgetList<IconButton>(
      find.widgetWithIcon(IconButton, Icons.merge_type),
    );
    expect(joins, hasLength(4));
    expect(joins.map((IconButton b) => b.onPressed != null), <bool>[
      true,
      true,
      true,
      false,
    ]);

    await act(
      tester,
      () => tester.tap(find.widgetWithIcon(IconButton, Icons.merge_type).first),
    );

    expect(cubit.state.plan!.actualCount, 3);
  });

  testWidgets('undo is offered only once there is an edit to take back', (
    WidgetTester tester,
  ) async {
    final AdminCubit cubit = await pumpSplit(tester);

    final Finder undo = find.widgetWithText(TextButton, 'Undo');
    expect(tester.widget<TextButton>(undo).onPressed, isNull);

    await act(
      tester,
      () => tester.tap(find.widgetWithIcon(IconButton, Icons.merge_type).first),
    );
    expect(tester.widget<TextButton>(undo).onPressed, isNotNull);

    await act(tester, () => tester.tap(undo));

    expect(cubit.state.plan!.actualCount, 4);
    expect(tester.widget<TextButton>(undo).onPressed, isNull);
  });

  testWidgets('the list narrows to the clips that do not fit their text', (
    WidgetTester tester,
  ) async {
    final AdminCubit cubit = await pumpSplit(tester);

    // The fixture's split leaves one clip out of line with its text, which
    // is the whole reason the filter exists.
    expect(cubit.state.suspects, hasLength(1));
    // Counted by a control only a clip has: the checkboxes above the list
    // are ListTiles too.
    final Finder rows = find.byIcon(Icons.merge_type);
    expect(tester.widgetList(rows), hasLength(4));

    await act(tester, () => tester.tap(find.byType(FilterChip)));

    expect(cubit.state.onlySuspects, isTrue);
    expect(tester.widgetList(rows), hasLength(cubit.state.suspects.length));

    // And back: the chip stays on screen so the filter can be turned off.
    await act(tester, () => tester.tap(find.byType(FilterChip)));
    expect(tester.widgetList(rows), hasLength(4));
  });

  testWidgets('the playing row offers a cut at the playhead — the edit made '
      'entirely by ear', (WidgetTester tester) async {
    final AdminCubit cubit = await pumpSplit(tester);

    expect(find.text('Cut at the playhead'), findsNothing);

    await act(tester, () => cubit.previewSegment(1));
    expect(find.text('Cut at the playhead'), findsOneWidget);

    await act(tester, () => tester.tap(find.text('Cut at the playhead')));
    // Position stream never ticked, so the playhead is the clip's start —
    // which the plan refuses as a cut. The point here is the wiring: the
    // button is on the playing row alone and acts on the cubit.
    expect(cubit.state.previewingIndex, isNull);
  });

  testWidgets('a batch shows one chip per recording, and a chip opens its '
      'split for review', (WidgetTester tester) async {
    final AdminCubit cubit = await pumpSplit(tester);
    final Directory folder = Directory.systemTemp.createTempSync(
      'mirqat_batch_ui',
    );
    addTearDown(() => folder.deleteSync(recursive: true));
    File('${folder.path}/001.mp3').writeAsStringSync('surah one');
    File('${folder.path}/003.mp3').writeAsStringSync('surah three');

    await act(tester, () => cubit.runBatchOn(folder.path));

    // One chip per recording, and the question only the operator may answer —
    // surah 1 split clean, so there is something to publish.
    expect(find.byType(ActionChip), findsNWidgets(2));
    expect(cubit.state.batchAwaitsDecision, isTrue);
    expect(find.textContaining('Publish the 1 clean surah'), findsOneWidget);

    // Surah 3 aligned to four segments with one suspect; its chip opens it.
    await act(tester, () => tester.tap(find.widgetWithText(ActionChip, '3 ?')));
    expect(cubit.state.surah!.number, 3);
    expect(cubit.state.sourcePath, '${folder.path}/003.mp3');
    expect(cubit.state.stage, AdminStage.reviewing);
  });

  testWidgets('the row being heard is marked, not only its button', (
    WidgetTester tester,
  ) async {
    final AdminCubit cubit = await pumpSplit(tester);

    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((ListTile t) => t.tileColor),
      everyElement(isNull),
    );

    await act(tester, () => cubit.previewSegment(1));

    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
    expect(
      tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((ListTile t) => t.tileColor != null),
      hasLength(1),
    );
  });

  testWidgets('the playing row says where the playhead is, as a time in the '
      'recording — the number an edit would be typed as', (
    WidgetTester tester,
  ) async {
    final AdminCubit cubit = await pumpSplit(tester);
    await act(tester, () => cubit.previewSegment(1));

    // The player speaks clip-relative positions; the row translates them
    // into the recording's own clock.
    await act(
      tester,
      () async => preview._position.add(const Duration(milliseconds: 1500)),
    );

    final Duration inRecording =
        cubit.state.plan!.segments[1].start +
        const Duration(milliseconds: 1500);
    expect(find.text('at ${formatTimecode(inRecording)}'), findsOneWidget);
  });

  testWidgets('the app bar sets the text size: larger, and the percentage '
      'puts it back', (WidgetTester tester) async {
    await pumpSplit(tester);

    // At the design size there is nothing to put back, so no percentage.
    expect(find.text('110%'), findsNothing);

    await tester.tap(find.byTooltip('Larger text (⌘+)'));
    await tester.pump();

    final BuildContext below = tester.element(find.byType(AdminScreen));
    expect(MediaQuery.textScalerOf(below).scale(14), closeTo(15.4, 0.001));
    expect(find.text('110%'), findsOneWidget);

    await tester.tap(find.text('110%'));
    await tester.pump();

    expect(MediaQuery.textScalerOf(below).scale(14), 14);
    expect(find.text('110%'), findsNothing);
  });
}
