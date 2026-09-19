import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../core/state/load_status.dart';
import '../../data/models/ayah.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';
import '../config/admin_config.dart';
import '../services/recitation_weight.dart';
import '../services/segment_audit.dart';
import '../services/admin_file_picker.dart';
import '../services/ffmpeg_runner.dart';
import '../services/publish_guard.dart';
import '../services/pack_publisher.dart';
import '../services/pages_publisher.dart';
import '../services/r2_client.dart';
import '../services/segment_planner.dart';
import '../services/segment_preview.dart';
import '../services/surah_splitter.dart';
import 'admin_state.dart';

/// One of a segment's two edges.
enum SegmentEdge { start, end }

/// Which part of a segment to listen to.
enum PreviewPart {
  whole,

  /// The first few seconds: does it begin on the ayah's first word?
  opening,

  /// The last few seconds: does it end on the ayah's last word?
  ending,

  /// A few seconds either side of the end boundary.
  acrossEnd,
}

/// Drives the split-review-publish pipeline.
///
/// Every Quranic fact in here comes from [QuranRepository] — the surah list,
/// the ayah count, `basmala_mode`, the ayah text beside each segment. Nothing
/// about a surah is written down in the admin tool, and no text is touched on
/// its way to the screen (CLAUDE.md A.2 rules 1 and 2).
class AdminCubit extends Cubit<AdminState> {
  AdminCubit({
    required QuranRepository quranRepository,
    required AdminConfig adminConfig,
    required FfmpegRunner ffmpegRunner,
    required R2Client r2Client,
    PackPublisher? packPublisher,
    PagesPublisher? pagesPublisher,
    AdminFilePicker filePicker = const NativeAdminFilePicker(),
    SegmentPlanner segmentPlanner = const SegmentPlanner(),
    SegmentPreview? segmentPreview,
  }) : _packs = packPublisher ?? PackPublisher(),
       _preview = segmentPreview,
       _pages = pagesPublisher ?? PagesPublisher(adminConfig: adminConfig),
       _quran = quranRepository,
       _config = adminConfig,
       _ffmpeg = ffmpegRunner,
       _r2 = r2Client,
       _files = filePicker,
       _planner = segmentPlanner,
       super(const AdminState());

  final QuranRepository _quran;
  final AdminConfig _config;
  final FfmpegRunner _ffmpeg;
  final R2Client _r2;
  final AdminFilePicker _files;
  final PackPublisher _packs;
  final PagesPublisher _pages;

  /// The manifest as this session has built it: fetched once, then merged into
  /// by every reciter added and every surah published.
  ///
  /// Held rather than re-fetched, because without a GitHub token nothing is
  /// published and the live manifest never catches up — a reciter added five
  /// minutes ago would vanish from the dropdown on the next read, which is
  /// exactly what happened.
  Map<String, dynamic>? _manifest;

  Future<Map<String, dynamic>> _workingManifest() async =>
      _manifest ??= await _packs.fetchManifest();
  final SegmentPlanner _planner;

  /// Loads the catalog and checks that ffmpeg is there before anything else
  /// can be started.
  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));

    final String? version = await _ffmpegVersion();
    if (version == null) return;

    final surahsResult = await _quran.getSurahs();
    final List<Surah>? surahs = surahsResult.fold((Failure f) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: f.message));
      return null;
    }, (List<Surah> s) => s);
    if (surahs == null) return;

    final List<AdminReciter> reciters = await _readReciters();
    emit(
      state.copyWith(
        status: LoadStatus.ready,
        surahs: surahs,
        reciters: reciters,
        reciterId: state.reciterId.isEmpty && reciters.isNotEmpty
            ? reciters.first.id
            : state.reciterId,
        ffmpegVersion: version,
        log: _logged(
          'ffmpeg: $version · ${reciters.length} reciter(s) · '
          '${_config.canPublishManifest ? 'manifest publishes to '
                    '${_config.githubRepo}' : 'manifest is written to disk only'}',
        ),
      ),
    );
  }

  /// Everyone the tool can publish for: the manifest's reciters first, then
  /// any the app bundles that the manifest has not caught up with.
  Future<List<AdminReciter>> _readReciters() async {
    final Map<String, dynamic> manifest = await _workingManifest();
    final List<AdminReciter> reciters = <AdminReciter>[
      for (final Object? entry
          in (manifest['reciters'] as List<dynamic>? ?? <dynamic>[]))
        if (entry is Map<String, dynamic>)
          AdminReciter(
            id: '${entry['id']}',
            nameAr: '${entry['nameAr'] ?? entry['id']}',
            nameEn: '${entry['nameEn'] ?? entry['id']}',
            riwayah: '${entry['riwayah'] ?? ''}',
            imagePath: entry['imagePath'] as String?,
            surahCount: (entry['surahs'] as List<dynamic>?)?.length ?? 0,
            inManifest: true,
          ),
    ];

    final List<Reciter> bundled = (await _quran.getReciters()).getOrElse(
      () => const <Reciter>[],
    );
    for (final Reciter reciter in bundled) {
      if (reciters.any((AdminReciter r) => r.id == reciter.id)) continue;
      reciters.add(
        AdminReciter(
          id: reciter.id,
          nameAr: reciter.nameAr,
          nameEn: reciter.nameEn,
        ),
      );
    }
    return List<AdminReciter>.unmodifiable(reciters);
  }

  /// Adds a reciter to the manifest — name, riwayah and portrait — and
  /// publishes it.
  ///
  /// No app release: the app merges the manifest's reciters into its own
  /// catalog at runtime, so this is the whole job. Their surahs come later,
  /// one publish at a time.
  Future<void> addReciter({
    required String id,
    required String nameAr,
    required String nameEn,
    String riwayah = '',
    String? imageFilePath,
  }) async {
    final String trimmedId = id.trim();
    if (trimmedId.isEmpty || nameAr.trim().isEmpty || nameEn.trim().isEmpty) {
      emit(
        state.copyWith(errorMessage: 'A reciter needs an id and both names.'),
      );
      return;
    }

    emit(state.copyWith(stage: AdminStage.uploading, errorMessage: null));
    try {
      String? imagePath;
      if (imageFilePath != null && imageFilePath.isNotEmpty) {
        final File image = File(imageFilePath);
        imagePath = PackPublisher.imageKeyFor(
          trimmedId,
          p.extension(image.path),
        );
        final UploadResult uploaded = await _r2.putFile(
          key: imagePath,
          file: image,
          contentType: _imageTypeFor(image.path),
          // A portrait is not a recitation: replacing one changes nobody's
          // audio, and a reciter sending a better photo is routine.
          replace: true,
        );
        emit(state.copyWith(log: _logged('uploaded ${uploaded.url}')));
      }

      final Map<String, dynamic> merged = _packs.mergeReciter(
        manifest: await _workingManifest(),
        id: trimmedId,
        nameAr: nameAr.trim(),
        nameEn: nameEn.trim(),
        riwayah: riwayah.trim(),
        bitrate: _config.bitrate,
        baseUrl: _config.publicBase,
        imagePath: imagePath,
      );

      _manifest = merged;
      await _publishManifest(merged, what: 'reciter "$trimmedId"');

      final List<AdminReciter> reciters = await _readReciters();
      emit(
        state.copyWith(
          stage: AdminStage.idle,
          reciters: reciters,
          // Selected only if they are really in the list. A selection the
          // dropdown has no item for is an assertion, not a nicety.
          reciterId: reciters.any((AdminReciter r) => r.id == trimmedId)
              ? trimmedId
              : state.reciterId,
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(stage: AdminStage.idle, errorMessage: e.message));
    }
  }

  static String _imageTypeFor(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        _ => 'image/jpeg',
      };

  Future<String?> _ffmpegVersion() async {
    try {
      return await _ffmpeg.version();
    } on ToolMissingException catch (e) {
      emit(
        state.copyWith(
          status: LoadStatus.failure,
          errorMessage:
              'ffmpeg is not on PATH, so nothing can be split.\n'
              '    brew install ffmpeg\n\n'
              '(${e.message})',
        ),
      );
      return null;
    }
  }

  Future<void> selectSurah(Surah surah) async {
    emit(
      state.copyWith(
        surah: surah,
        clearPlan: true,
        stage: AdminStage.idle,
        errorMessage: null,
      ),
    );
    final ayahsResult = await _quran.getAyahs(surah.number);
    ayahsResult.fold(
      (Failure f) => emit(state.copyWith(errorMessage: f.message)),
      // Straight from quran.db to the screen: no trimming, no normalising,
      // nothing (A.2 rule 1).
      (List<Ayah> ayahs) => emit(state.copyWith(ayahs: ayahs)),
    );
  }

  void selectSource(String path) => emit(
    state.copyWith(
      sourcePath: path,
      clearPlan: true,
      stage: AdminStage.idle,
      errorMessage: null,
    ),
  );

  /// Opens the system file panel and takes whatever comes back.
  ///
  /// Cancelling is not a failure and leaves the current choice alone — the
  /// operator re-splitting the same recording after a tweak is the common
  /// case, and losing the path on a stray Escape would be a small cruelty.
  /// Opens the panel for a reciter's portrait.
  Future<String?> chooseImage() async {
    try {
      return await _files.pickImage();
    } on PlatformException {
      return null;
    }
  }

  Future<void> chooseSource() async {
    try {
      final String? path = await _files.pickRecording();
      if (path == null || path.isEmpty) return;
      selectSource(path);
    } on MissingPluginException {
      emit(
        state.copyWith(
          errorMessage:
              'The file panel is a macOS-only channel, and it is not there in '
              'this build. Run the tool with ./run_admin.sh.',
        ),
      );
    } on PlatformException catch (e) {
      emit(
        state.copyWith(
          errorMessage: 'Could not open the file panel: ${e.message}',
        ),
      );
    }
  }

  void setReciterId(String value) => emit(state.copyWith(reciterId: value));

  void setOverrideReason(String value) =>
      emit(state.copyWith(overrideReason: value));

  void setReplaceExisting(bool value) =>
      emit(state.copyWith(replaceExisting: value));

  void setThresholdDb(double value) => emit(state.copyWith(thresholdDb: value));

  void setMinimumSilenceMs(int value) =>
      emit(state.copyWith(minimumSilenceMs: value));

  /// How long each segment should be, relative to the others: the letters of
  /// the ayah it will hold.
  ///
  /// Letters, not words or bytes: recitation time tracks how much there is to
  /// pronounce, and diacritics and spaces do not add syllables. The basmala's
  /// own weight is the bismillah text's, so a `separate` surah's first segment
  /// is sized like what it holds rather than guessed at.
  Future<List<int>> _weightsFor(SegmentPlan plan) async {
    final List<Ayah> ayahs = state.ayahs.isNotEmpty
        ? state.ayahs
        : (await _quran.getAyahs(
            plan.surah.number,
          )).getOrElse(() => const <Ayah>[]);
    if (ayahs.length != plan.surah.ayahCount) return const <int>[];

    // Al-Fatiha's ayah 1 *is* the basmala, so the text is in the catalog
    // rather than in a constant here (CLAUDE.md A.2 rule 2).
    String basmalaText = '';
    if (plan.expectsBasmala) {
      final List<Ayah> fatiha = (await _quran.getAyahRange(
        1,
        startAyah: 1,
        endAyah: 1,
      )).getOrElse(() => const <Ayah>[]);
      basmalaText = fatiha.isEmpty ? '' : fatiha.first.text;
    }

    return segmentWeights(
      ayahTexts: <String>[for (final Ayah ayah in ayahs) ayah.text],
      basmalaText: basmalaText,
      hasBasmala: plan.expectsBasmala,
      hasIstiadhah: plan.expectsIstiadhah,
    );
  }

  /// The segments of [plan] whose length does not fit their text.
  Future<List<int>> _suspectsIn(SegmentPlan plan) async {
    if (!plan.countMatches) return const <int>[];
    final List<int> weights = await _weightsFor(plan);
    return weights.length == plan.expectedCount
        ? suspectsIn(plan.segments, weights)
        : const <int>[];
  }

  /// What the recording holds besides the ayahs. Changing either changes how
  /// many segments are expected, so a split made under the old answer is
  /// dropped rather than reinterpreted.
  void setRecordingHasBasmala(bool value) =>
      emit(state.copyWith(recordingHasBasmala: value, clearPlan: true));

  void setRecordingHasIstiadhah(bool value) =>
      emit(state.copyWith(recordingHasIstiadhah: value, clearPlan: true));

  /// Re-cuts the current split so each segment matches its ayah's share of the
  /// text, choosing from the silences the recording actually has.
  ///
  /// For a surah long enough that no threshold produces the right count — and
  /// Al-Baqarah is — this is the only honest way to a full split: every cut
  /// still falls in a real gap, and the text decides which gaps.
  Future<void> alignToText() async {
    final SegmentPlan? plan = state.plan;
    if (plan == null) return;

    final List<int> weights = await _weightsFor(plan);
    if (weights.length != plan.expectedCount) {
      emit(
        state.copyWith(
          errorMessage:
              'The ayah text for this surah did not load, so there is nothing '
              'to size the segments against.',
        ),
      );
      return;
    }

    final List<AudioSegment> aligned = _planner.alignToWeights(
      totalDuration: state.recordingLength ?? plan.segments.last.end,
      silences: state.candidateCuts.isEmpty
          ? plan.segments
                .map((AudioSegment s) => AudioSegment(start: s.end, end: s.end))
                .toList()
          : state.candidateCuts,
      weights: weights,
    );

    if (aligned.isEmpty) {
      emit(
        state.copyWith(
          errorMessage:
              'This recording has fewer pauses than it has ayahs, so no '
              'alignment can be honest. Lower the threshold or the minimum '
              'silence and split again.',
        ),
      );
      return;
    }

    final List<int> suspects = suspectsIn(aligned, weights);
    emit(
      state.copyWith(
        plan: plan.copyWith(segments: aligned),
        suspects: suspects,
        errorMessage: null,
        log: _logged(
          'aligned ${aligned.length} segments to the text; '
          '${suspects.isEmpty ? 'every clip fits its text' : '${suspects.length} clips do not fit their text'}',
        ),
      ),
    );
  }

  /// Runs silence detection and proposes one segment per ayah.
  Future<void> split() async {
    final Surah? surah = state.surah;
    final String? source = state.sourcePath;
    if (surah == null || source == null) return;

    // Whatever was playing belongs to the split that is about to be replaced.
    await stopPreview();

    emit(
      state.copyWith(
        stage: AdminStage.splitting,
        errorMessage: null,
        log: _logged('splitting ${p.basename(source)}…'),
      ),
    );

    try {
      // A throwaway plan, only to ask what this recording should hold.
      final SegmentPlan shape = SegmentPlan(
        surah: surah,
        segments: const <AudioSegment>[],
        recordingHasBasmala: state.recordingHasBasmala,
        recordingHasIstiadhah: state.recordingHasIstiadhah,
      );
      final SplitResult result =
          await SurahSplitter(ffmpeg: _ffmpeg, planner: _planner).split(
            source: File(source),
            surah: surah,
            weights: await _weightsFor(shape),
            thresholdDb: state.thresholdDb,
            minimumSilence: Duration(milliseconds: state.minimumSilenceMs),
            recordingHasBasmala: state.recordingHasBasmala,
            recordingHasIstiadhah: state.recordingHasIstiadhah,
          );
      final SegmentPlan plan = result.plan;

      emit(
        state.copyWith(
          stage: AdminStage.reviewing,
          plan: plan,
          candidateCuts: result.candidates,
          suspects: result.suspects,
          recordingLength: result.total,
          log: _logged(
            '${result.method == SplitMethod.aligned ? 'aligned to the text: ' : 'found '}'
            '${plan.actualCount} segments, expected ${plan.expectedCount} '
            '(${surah.ayahCount} ayahs'
            '${plan.expectsBasmala ? ' + basmala' : ''}'
            '${plan.expectsIstiadhah ? " + isti'adhah" : ''}); '
            '${result.suspects.isEmpty ? 'every clip fits its text' : '${result.suspects.length} clips do not fit their text'}',
          ),
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(stage: AdminStage.idle, errorMessage: e.message));
    }
  }

  /// Emits an edited plan, then re-checks it against the text: a hand edit is
  /// exactly when the operator wants to know whether the clip now adds up.
  Future<void> _emitEdited(SegmentPlan plan) async {
    emit(state.copyWith(plan: plan, errorMessage: null));
    final List<int> suspects = await _suspectsIn(plan);
    // Only if nothing has replaced the plan while the text was being read.
    if (state.plan == plan) emit(state.copyWith(suspects: suspects));
  }

  /// Made on first use: opening an audio device is not something a session
  /// that never listens to anything should pay for, and a test should not need
  /// one at all.
  SegmentPreview? _preview;
  StreamSubscription<bool>? _previewSub;

  SegmentPreview _previewPlayer() {
    final SegmentPreview preview = _preview ??= JustAudioSegmentPreview();
    _previewSub ??= preview.playing.listen((bool playing) {
      if (!playing && state.previewingIndex != null) {
        emit(state.copyWith(clearPreview: true));
      }
    });
    return preview;
  }

  /// Plays part of segment [index] straight from the recording, so a cut can
  /// be judged by ear before anything is encoded. Asking for the segment that
  /// is already playing stops it.
  Future<void> previewSegment(
    int index, {
    PreviewPart part = PreviewPart.whole,
  }) async {
    final SegmentPlan? plan = state.plan;
    final String? source = state.sourcePath;
    if (plan == null || source == null) return;
    if (index < 0 || index >= plan.segments.length) return;

    if (state.previewingIndex == index && part == PreviewPart.whole) {
      await stopPreview();
      return;
    }

    final AudioSegment segment = plan.segments[index];
    final Duration total = state.recordingLength ?? plan.segments.last.end;
    Duration clamp(Duration d) =>
        d < Duration.zero ? Duration.zero : (d > total ? total : d);

    final (Duration from, Duration to) = switch (part) {
      PreviewPart.whole => (segment.start, segment.end),
      PreviewPart.opening => (
        segment.start,
        clamp(segment.start + previewWindow) < segment.end
            ? clamp(segment.start + previewWindow)
            : segment.end,
      ),
      PreviewPart.ending => (
        clamp(segment.end - previewWindow) > segment.start
            ? clamp(segment.end - previewWindow)
            : segment.start,
        segment.end,
      ),
      // Across the cut: the end of this ayah and the start of the next, which
      // is how a boundary that is a word early or late actually sounds.
      PreviewPart.acrossEnd => (
        clamp(segment.end - previewWindow),
        clamp(segment.end + previewWindow),
      ),
    };

    try {
      await _previewPlayer().play(File(source), from: from, to: to);
      emit(state.copyWith(previewingIndex: index, errorMessage: null));
    } on Object catch (e) {
      emit(
        state.copyWith(
          clearPreview: true,
          errorMessage: 'That stretch of the recording would not play: $e',
        ),
      );
    }
  }

  Future<void> stopPreview() async {
    await _preview?.stop();
    if (state.previewingIndex != null) {
      emit(state.copyWith(clearPreview: true));
    }
  }

  /// How much of a segment "the opening" and "the ending" are.
  static const Duration previewWindow = Duration(seconds: 3);

  /// Moves a boundary to an exact time — the edit for a cut that has no pause
  /// to land on. See [SegmentPlan.movingBoundary] for how boundaries are
  /// numbered and what [to] is held to.
  void moveBoundary(int boundary, Duration to) {
    final SegmentPlan? plan = state.plan;
    if (plan == null) return;
    final SegmentPlan moved = plan.movingBoundary(
      boundary,
      to,
      recordingLength: state.recordingLength ?? plan.segments.last.end,
    );
    if (moved != plan) unawaited(_emitEdited(moved));
  }

  /// [moveBoundary] by an amount rather than to a time.
  void nudgeBoundary(int boundary, Duration by) {
    final SegmentPlan? plan = state.plan;
    if (plan == null || boundary < 0 || boundary > plan.segments.length) return;
    final Duration current = boundary == plan.segments.length
        ? plan.segments.last.end
        : plan.segments[boundary].start;
    moveBoundary(boundary, current + by);
  }

  /// Moves one edge of segment [index] to [to].
  ///
  /// [joined] is the default and keeps the neighbour attached: the end of one
  /// segment is the start of the next. With it off only this segment changes,
  /// and whatever is left between the two is cut out of both — see
  /// [SegmentPlan.trimmingEdge].
  void moveEdge(
    int index,
    SegmentEdge edge,
    Duration to, {
    bool joined = true,
  }) {
    final SegmentPlan? plan = state.plan;
    if (plan == null || index < 0 || index >= plan.segments.length) return;
    final Duration length = state.recordingLength ?? plan.segments.last.end;

    final SegmentPlan moved = joined
        ? plan.movingBoundary(
            edge == SegmentEdge.start ? index : index + 1,
            to,
            recordingLength: length,
          )
        : plan.trimmingEdge(
            index,
            start: edge == SegmentEdge.start ? to : null,
            end: edge == SegmentEdge.end ? to : null,
            recordingLength: length,
          );
    if (moved != plan) unawaited(_emitEdited(moved));
  }

  /// [moveEdge] by an amount. Measured from the edge being edited, not from
  /// its neighbour's: once a gap has been cut the two are no longer the same
  /// time, and a nudge has to mean "a little from where this one is".
  void nudgeEdge(
    int index,
    SegmentEdge edge,
    Duration by, {
    bool joined = true,
  }) {
    final SegmentPlan? plan = state.plan;
    if (plan == null || index < 0 || index >= plan.segments.length) return;
    final AudioSegment segment = plan.segments[index];
    moveEdge(
      index,
      edge,
      (edge == SegmentEdge.start ? segment.start : segment.end) + by,
      joined: joined,
    );
  }

  @override
  Future<void> close() async {
    await _previewSub?.cancel();
    await _preview?.dispose();
    return super.close();
  }

  void adjustSegment(int index, AudioSegment segment) {
    final SegmentPlan? plan = state.plan;
    if (plan == null) return;
    unawaited(_emitEdited(plan.replacing(index, segment)));
  }

  void removeSegment(int index) {
    final SegmentPlan? plan = state.plan;
    if (plan == null) return;
    unawaited(_emitEdited(plan.removing(index)));
  }

  /// Splits [index] at the quietest moment inside it, or at [at] when one is
  /// given.
  void splitSegment(int index, [Duration? at]) {
    final SegmentPlan? plan = state.plan;
    if (plan == null) return;

    final Duration? cut = at ?? plan.bestCutFor(index, state.candidateCuts);
    if (cut == null) {
      emit(
        state.copyWith(
          errorMessage:
              'No quiet moment inside that segment to cut at. Lower the '
              'threshold or the minimum silence and split again, or trim the '
              'boundaries by hand.',
        ),
      );
      return;
    }
    unawaited(_emitEdited(plan.splitting(index, cut)));
  }

  /// Exports every segment and uploads it.
  ///
  /// The guard decides first, and a blocked decision stops here: a mismatched
  /// split published is every later ayah filed under the wrong number.
  Future<void> publish({bool? replaceExisting}) async {
    final bool replace = replaceExisting ?? state.replaceExisting;
    final SegmentPlan? plan = state.plan;
    final String? source = state.sourcePath;
    if (plan == null || source == null) return;

    final PublishDecision decision = state.decision;
    switch (decision) {
      case PublishBlocked(reason: final String reason):
        emit(state.copyWith(errorMessage: reason));
        return;
      case PublishOverridden(summary: final String summary):
        emit(
          state.copyWith(
            log: _logged(
              'OVERRIDE: $summary reason: "${state.overrideReason.trim()}"',
            ),
          ),
        );
      case PublishAllowed():
        break;
    }

    final Directory staging = Directory(
      p.join(Directory.systemTemp.path, 'mirqat_admin', state.reciterId),
    )..createSync(recursive: true);

    try {
      emit(state.copyWith(stage: AdminStage.exporting, progress: 0));

      // Everything but the isti'adhah: it is cut so that it stays out of the
      // basmala, and it belongs to no surah, so no file is made for it.
      final List<PlannedSegment> planned = plan.published;
      final List<File> exported = <File>[];
      for (int i = 0; i < planned.length; i++) {
        final PlannedSegment item = planned[i];
        exported.add(
          await _ffmpeg.exportSegment(
            source: File(source),
            destination: File(
              p.join(
                staging.path,
                '${_pad3(plan.surah.number)}${_pad3(item.ayahNumber)}.mp3',
              ),
            ),
            segment: item.segment,
            bitrate: _config.bitrate,
          ),
        );
        emit(state.copyWith(progress: (i + 1) / planned.length));
      }

      emit(state.copyWith(stage: AdminStage.uploading, progress: 0));
      final String reciterId = state.reciterId.trim();
      for (int i = 0; i < exported.length; i++) {
        final String key = _config.audioKey(
          reciterId: reciterId,
          surah: plan.surah.number,
          ayah: planned[i].ayahNumber,
        );
        final UploadResult result = await _r2.putFile(
          key: key,
          file: exported[i],
          replace: replace,
        );
        emit(
          state.copyWith(
            progress: (i + 1) / exported.length,
            log: _logged(
              result.outcome == UploadOutcome.unchanged
                  ? 'already there, unchanged: ${result.url}'
                  : 'uploaded ${result.url}',
            ),
          ),
        );
      }

      // The pack, without which the surah can be streamed but never
      // downloaded — and the manifest, without which the app cannot see it at
      // all.
      final List<int> pack = _packs.buildPack(exported);
      final UploadResult packResult = await _r2.putObject(
        key: _config.packKey(reciterId: reciterId, surah: plan.surah.number),
        bytes: pack,
        contentType: 'application/zip',
        replace: replace,
      );
      emit(
        state.copyWith(
          log: _logged(
            packResult.outcome == UploadOutcome.unchanged
                ? 'pack already there, unchanged: ${packResult.url}'
                : 'uploaded pack ${packResult.url} '
                      '(${pack.length} bytes)',
          ),
        ),
      );

      final Map<String, dynamic> merged = await _mergedManifest(
        plan: plan,
        reciterId: reciterId,
        pack: pack,
      );
      _manifest = merged;
      await _publishManifest(merged, what: 'surah ${plan.surah.number}');

      emit(
        state.copyWith(
          stage: AdminStage.published,
          clearProgress: true,
          reciters: await _readReciters(),
        ),
      );
    } on AppException catch (e) {
      emit(
        state.copyWith(
          stage: AdminStage.reviewing,
          clearProgress: true,
          errorMessage: e.message,
        ),
      );
    }
  }

  /// Merges this surah into the live manifest and writes it beside the
  /// recording.
  ///
  /// The reciter's names come from the bundled catalog when the id matches one
  /// there, so a manifest entry and the app's own reciter list never disagree
  /// about who is reciting.
  Future<Map<String, dynamic>> _mergedManifest({
    required SegmentPlan plan,
    required String reciterId,
    required List<int> pack,
  }) async {
    final List<Reciter> catalog = (await _quran.getReciters()).getOrElse(
      () => const <Reciter>[],
    );
    final Reciter reciter =
        catalog.where((Reciter r) => r.id == reciterId).firstOrNull ??
        Reciter(
          id: reciterId,
          nameAr: reciterId,
          nameEn: reciterId,
          audioMode: AudioMode.perAyahFiles,
          basePath: '',
          bundled: false,
          availableSurahs: const <int>[],
          hasIstiadhah: false,
          hasBismillah: false,
        );

    return _packs.mergeSurah(
      manifest: await _workingManifest(),
      reciter: reciter,
      surah: plan.surah,
      bitrate: _config.bitrate,
      baseUrl: _config.publicBase,
      packBytes: pack.length,
      packSha256: PackPublisher.digestOf(pack),
      hasBasmala: plan.expectsBasmala,
    );
  }

  /// Writes the manifest where the operator can find it and, when the tool is
  /// configured for it, publishes it to the Pages site.
  ///
  /// Written first either way: a publish that fails must still leave the file
  /// on disk, because that file is the whole record of what was just uploaded.
  Future<void> _publishManifest(
    Map<String, dynamic> manifest, {
    required String what,
    Directory? directory,
  }) async {
    final File file = _packs.writeManifest(
      manifest: manifest,
      directory:
          directory ??
          (state.sourcePath == null
              ? (Directory('build')..createSync(recursive: true))
              : File(state.sourcePath!).parent),
    );
    emit(state.copyWith(log: _logged('wrote ${file.path}')));

    if (!_config.canPublishManifest) {
      emit(
        state.copyWith(
          log: _logged(
            'Publish that file to the Pages site — until it is live the app '
            'cannot see $what. (Add GITHUB_TOKEN and GITHUB_REPO to admin.env '
            'and the tool will do it.)',
          ),
        ),
      );
      return;
    }

    final String commit = await _pages.publish(manifest);
    emit(
      state.copyWith(
        log: _logged(
          'published the manifest to ${_config.githubRepo}'
          '${commit.isEmpty ? '' : ' (${commit.substring(0, 7)})'} — '
          '$what is live once Pages rebuilds, with no app release.',
        ),
      ),
    );
  }

  List<String> _logged(String line) => <String>[...state.log, line];

  static String _pad3(int n) => n.toString().padLeft(3, '0');
}
