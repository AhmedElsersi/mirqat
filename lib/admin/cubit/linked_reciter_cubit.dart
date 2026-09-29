import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';
import '../config/admin_config.dart';
import '../services/admin_file_picker.dart';
import '../services/ffmpeg_runner.dart';
import '../services/link_file.dart';
import '../services/pack_publisher.dart';
import '../services/pages_publisher.dart';
import '../services/r2_client.dart';

/// What asking the host about a surah's first ayah answered.
enum ProbeOutcome { untried, ok, notFound, error }

/// One surah of the catalog, against what the file lists and what the host
/// holds.
class SurahPlan extends Equatable {
  const SurahPlan({
    required this.number,
    required this.nameAr,
    required this.ayahCount,
    required this.separate,
    required this.listed,
    this.probe = ProbeOutcome.untried,
    this.basmala,
  });

  final int number;
  final String nameAr;

  /// From `quran.db`, never from the file (CLAUDE.md A.2 rule 2).
  final int ayahCount;

  /// Whether the surah's basmala is its own file, `000`, if it exists at all.
  final bool separate;

  /// The ayah numbers the file lists for this surah. Empty: not in the file.
  final Set<int> listed;

  final ProbeOutcome probe;

  /// Whether the host holds a `000` for this surah — answered by the probe,
  /// only for a [separate] surah, and written into the manifest as
  /// `hasBasmala`, because the app has no other way to know.
  final bool? basmala;

  bool get inFile => listed.isNotEmpty;

  List<int> get missing => <int>[
    for (int a = 1; a <= ayahCount; a++)
      if (!listed.contains(a)) a,
  ];

  List<int> get extra => <int>[
    for (final int a in listed)
      if (a < 0 || a > ayahCount) a,
  ];

  /// Every ayah `quran.db` counts is listed, and nothing that is not.
  bool get complete => inFile && missing.isEmpty && extra.isEmpty;

  /// Complete, present on the host, and its basmala settled: what may go
  /// into the manifest.
  bool get publishable =>
      complete && probe == ProbeOutcome.ok && (!separate || basmala != null);

  SurahPlan copyWith({ProbeOutcome? probe, bool? basmala}) => SurahPlan(
    number: number,
    nameAr: nameAr,
    ayahCount: ayahCount,
    separate: separate,
    listed: listed,
    probe: probe ?? this.probe,
    basmala: basmala ?? this.basmala,
  );

  @override
  List<Object?> get props => <Object?>[
    number,
    nameAr,
    ayahCount,
    separate,
    listed,
    probe,
    basmala,
  ];
}

/// Who the reciter is, as the operator types it.
class LinkedReciterDraft extends Equatable {
  const LinkedReciterDraft({
    this.id = '',
    this.nameAr = '',
    this.nameEn = '',
    this.riwayah = '',
    this.version = '1',
    this.bitrate,
    this.imagePath,
    this.attributionAr = '',
    this.attributionEn = '',
  });

  final String id;
  final String nameAr;
  final String nameEn;
  final String riwayah;
  final String version;
  final int? bitrate;

  /// The portrait's path on the bucket, relative to the manifest's `baseUrl`.
  final String? imagePath;

  /// Who to credit for the recordings, shown under the name in the app.
  final String attributionAr;
  final String attributionEn;

  LinkedReciterDraft copyWith({
    String? id,
    String? nameAr,
    String? nameEn,
    String? riwayah,
    String? version,
    int? bitrate,
    String? imagePath,
    bool clearImage = false,
    String? attributionAr,
    String? attributionEn,
  }) => LinkedReciterDraft(
    id: id ?? this.id,
    nameAr: nameAr ?? this.nameAr,
    nameEn: nameEn ?? this.nameEn,
    riwayah: riwayah ?? this.riwayah,
    version: version ?? this.version,
    bitrate: bitrate ?? this.bitrate,
    imagePath: clearImage ? null : (imagePath ?? this.imagePath),
    attributionAr: attributionAr ?? this.attributionAr,
    attributionEn: attributionEn ?? this.attributionEn,
  );

  static final RegExp idShape = RegExp(r'^[a-z0-9_]+$');

  @override
  List<Object?> get props => <Object?>[
    id,
    nameAr,
    nameEn,
    riwayah,
    version,
    bitrate,
    imagePath,
    attributionAr,
    attributionEn,
  ];
}

class LinkedReciterState extends Equatable {
  const LinkedReciterState({
    this.loading = true,
    this.manifest = const <String, dynamic>{},
    this.manifestLive = false,
    this.filePath,
    this.file,
    this.plan = const <SurahPlan>[],
    this.draft = const LinkedReciterDraft(),
    this.probing = false,
    this.probeProgress,
    this.probed = false,
    this.measuredBitrate,
    this.busy = false,
    this.message,
    this.error,
  });

  final bool loading;

  /// The manifest as it is live, which the entry is merged into.
  final Map<String, dynamic> manifest;
  final bool manifestLive;

  final String? filePath;
  final LinkFile? file;

  /// Every surah of the catalog, in order, whether or not the file has it.
  final List<SurahPlan> plan;
  final LinkedReciterDraft draft;

  final bool probing;
  final double? probeProgress;

  /// The host has been asked, for this file.
  final bool probed;

  /// The bitrate read off one clip the probe fetched, in kbps.
  final int? measuredBitrate;

  /// Uploading a portrait, or publishing.
  final bool busy;
  final String? message;
  final String? error;

  /// The manifest's row for the draft's id, if there is one.
  Map<String, dynamic>? get existingRow {
    for (final Object? r
        in manifest['reciters'] as List<dynamic>? ?? const []) {
      if (r is Map<String, dynamic> && r['id'] == draft.id) return r;
    }
    return null;
  }

  /// Whether the existing row is a reciter published with packs, whose packs
  /// a linked entry would take away.
  bool get idBelongsToPackedReciter =>
      '${existingRow?['packPath'] ?? ''}'.isNotEmpty;

  List<SurahPlan> get publishable =>
      plan.where((SurahPlan s) => s.publishable).toList();

  /// What stops a publish, in the order it is worth fixing.
  List<String> get problems => <String>[
    if (file == null) 'Choose a file of links.',
    if (draft.id.isEmpty)
      'The reciter needs an id (lower-case letters, digits and underscores).'
    else if (!LinkedReciterDraft.idShape.hasMatch(draft.id))
      '"${draft.id}" is not an id: lower-case letters, digits and underscores '
          'only.',
    if (idBelongsToPackedReciter)
      '"${draft.id}" is a reciter published with packs. A linked entry would '
          'take their packs away; use another id.',
    if (draft.nameAr.trim().isEmpty) 'The Arabic name is empty.',
    if (draft.nameEn.trim().isEmpty) 'The English name is empty.',
    if (draft.version.trim().isEmpty) 'The version is empty.',
    if (draft.bitrate == null || draft.bitrate! <= 0)
      'The bitrate is not known: probe the host to measure it, or type it.',
    if (file != null && !probed)
      'Probe the host: it decides which surahs are there and which have a '
          'basmala.',
    if (file != null && probed && publishable.isEmpty)
      'No surah is complete in the file and present on the host.',
  ];

  /// What is worth knowing and does not stop a publish.
  List<String> get warnings {
    if (file == null) return const <String>[];
    final List<int> absent = <int>[
      for (final SurahPlan s in plan)
        if (!s.inFile) s.number,
    ];
    final List<SurahPlan> incomplete = <SurahPlan>[
      for (final SurahPlan s in plan)
        if (s.inFile && !s.complete) s,
    ];
    final List<int> unreachable = <int>[
      for (final SurahPlan s in plan)
        if (s.complete &&
            (s.probe == ProbeOutcome.notFound || s.probe == ProbeOutcome.error))
          s.number,
    ];
    return <String>[
      if (absent.isNotEmpty)
        '${absent.length} surah(s) are not in the file and will not be '
            'offered: ${_list(absent)}.',
      for (final SurahPlan s in incomplete)
        'Surah ${s.number} is incomplete in the file'
            '${s.missing.isEmpty ? '' : ' (missing ayah ${_list(s.missing)})'}'
            '${s.extra.isEmpty ? '' : ' (extra ayah ${_list(s.extra)})'}'
            ' and will not be offered.',
      if (unreachable.isNotEmpty)
        '${unreachable.length} surah(s) are listed but not on the host, and '
            'will not be offered: ${_list(unreachable)}.',
      if (existingRow != null && !idBelongsToPackedReciter)
        '"${draft.id}" is already in the manifest; publishing replaces that '
            'entry. Bump the version if the recordings changed.',
    ];
  }

  /// The manifest entry the draft would publish, or null while [problems]
  /// stand.
  Map<String, dynamic>? get row {
    final LinkFile? links = file;
    if (links == null || problems.isNotEmpty) return null;
    final String? image = draft.imagePath;
    return <String, dynamic>{
      'id': draft.id,
      'nameAr': draft.nameAr.trim(),
      'nameEn': draft.nameEn.trim(),
      'riwayah': draft.riwayah.trim(),
      'bitrate': draft.bitrate,
      'version': draft.version.trim(),
      'audioPath': links.template,
      if (image != null && image.isNotEmpty) 'imagePath': image,
      if (draft.attributionAr.trim().isNotEmpty ||
          draft.attributionEn.trim().isNotEmpty)
        'attribution': <String, String>{
          'ar': draft.attributionAr.trim(),
          'en': draft.attributionEn.trim(),
        },
      'totalBytes': 0,
      'surahs': <Map<String, dynamic>>[
        for (final SurahPlan s in publishable)
          <String, dynamic>{
            'n': s.number,
            'ayahs': s.ayahCount,
            if (s.separate) 'hasBasmala': s.basmala,
          },
      ],
    };
  }

  static String _list(List<int> numbers, {int keep = 10}) =>
      numbers.length <= keep
      ? numbers.join(', ')
      : '${numbers.take(keep).join(', ')} … (${numbers.length})';

  LinkedReciterState copyWith({
    bool? loading,
    Map<String, dynamic>? manifest,
    bool? manifestLive,
    String? filePath,
    LinkFile? file,
    bool clearFile = false,
    List<SurahPlan>? plan,
    LinkedReciterDraft? draft,
    bool? probing,
    double? probeProgress,
    bool clearProbeProgress = false,
    bool? probed,
    int? measuredBitrate,
    bool? busy,
    String? message,
    String? error,
  }) => LinkedReciterState(
    loading: loading ?? this.loading,
    manifest: manifest ?? this.manifest,
    manifestLive: manifestLive ?? this.manifestLive,
    filePath: clearFile ? null : (filePath ?? this.filePath),
    file: clearFile ? null : (file ?? this.file),
    plan: plan ?? this.plan,
    draft: draft ?? this.draft,
    probing: probing ?? this.probing,
    probeProgress: clearProbeProgress
        ? null
        : (probeProgress ?? this.probeProgress),
    probed: probed ?? this.probed,
    measuredBitrate: measuredBitrate ?? this.measuredBitrate,
    busy: busy ?? this.busy,
    // Both are about the last thing that happened, so both are replaced.
    message: message,
    error: error,
  );

  @override
  List<Object?> get props => <Object?>[
    loading,
    manifest,
    manifestLive,
    filePath,
    file,
    plan,
    draft,
    probing,
    probeProgress,
    probed,
    measuredBitrate,
    busy,
    message,
    error,
  ];
}

/// Adds a reciter from a file of links: a recitation someone else already cut
/// and hosts, per ayah, which the app streams and downloads from that host
/// without a byte of it passing through the bucket (CLAUDE.md A.5, *a reciter
/// without packs*).
///
/// The file is reduced to one template; `quran.db` decides what a complete
/// surah is; the host is asked which surahs it holds and which have a basmala;
/// and the entry is merged into the live manifest and published. Nothing is
/// cut, nothing is uploaded but a portrait, and the split flow is untouched.
class LinkedReciterCubit extends Cubit<LinkedReciterState> {
  LinkedReciterCubit({
    required PagesPublisher pagesPublisher,
    required PackPublisher packPublisher,
    required R2Client r2Client,
    required AdminFilePicker filePicker,
    required QuranRepository quranRepository,
    required FfmpegRunner ffmpegRunner,
    required AdminConfig adminConfig,
    http.Client? client,
    this.bundledCopy,
  }) : _pages = pagesPublisher,
       _packs = packPublisher,
       _r2 = r2Client,
       _files = filePicker,
       _quran = quranRepository,
       _ffmpeg = ffmpegRunner,
       _config = adminConfig,
       _client = client ?? http.Client(),
       super(const LinkedReciterState());

  final PagesPublisher _pages;
  final PackPublisher _packs;
  final R2Client _r2;
  final AdminFilePicker _files;
  final QuranRepository _quran;
  final FfmpegRunner _ffmpeg;
  final AdminConfig _config;
  final http.Client _client;

  /// The app's own bundled `manifest.json`, written after a publish so a
  /// fresh install starts from what is live. Null when the checkout is not
  /// known.
  final File? bundledCopy;

  /// How many addresses are asked of the host at once.
  static const int _probeWidth = 8;

  List<Surah> _surahs = const <Surah>[];

  /// Starts from the live manifest, so the entry is merged into what the app
  /// reads now — and from the catalog, which is what a complete surah means.
  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final Map<String, dynamic> manifest = await _packs.fetchManifest();
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    if (isClosed) return;
    _surahs = surahs.getOrElse(() => const <Surah>[]);
    emit(
      state.copyWith(
        loading: false,
        manifest: manifest,
        manifestLive: '${manifest['baseUrl'] ?? ''}'.isNotEmpty,
        error: surahs.isLeft() ? 'The surah catalog could not be read.' : null,
      ),
    );
  }

  Future<void> chooseFile() async {
    final String? path;
    try {
      path = await _files.pickLinkFile();
    } on Object catch (e) {
      emit(state.copyWith(error: 'The file panel could not be opened: $e'));
      return;
    }
    if (path == null) return;
    await useFile(path);
  }

  /// Reads [path] as a file of links and lays it against the catalog. A file
  /// that does not reduce to one template is refused whole, and what was
  /// chosen before stays.
  Future<void> useFile(String path) async {
    final LinkFile file;
    try {
      file = LinkFile.parse(await File(path).readAsString());
    } on LinkFileException catch (e) {
      emit(state.copyWith(error: 'Not a usable file of links:\n$e'));
      return;
    } on FileSystemException catch (e) {
      emit(
        state.copyWith(
          error: 'Could not read ${p.basename(path)}: ${e.message}',
        ),
      );
      return;
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        filePath: path,
        file: file,
        plan: <SurahPlan>[
          for (final Surah s in _surahs)
            SurahPlan(
              number: s.number,
              nameAr: s.nameAr,
              ayahCount: s.ayahCount,
              separate: s.bismillahMode == BismillahMode.separatePreamble,
              listed: file.ayahs[s.number] ?? const <int>{},
            ),
        ],
        probed: false,
        clearProbeProgress: true,
        message:
            '${p.basename(path)}: ${file.ayahCount} ayahs across '
            '${file.surahs.length} surah(s), all at ${file.template}',
      ),
    );
  }

  void edit(LinkedReciterDraft Function(LinkedReciterDraft draft) change) {
    final LinkedReciterDraft next = change(state.draft);
    emit(state.copyWith(draft: _adopting(next)));
  }

  /// A draft whose id names a linked reciter already in the manifest takes
  /// that entry's names, version and portrait where the draft has none — so
  /// re-publishing after the host changed is a matter of choosing the file.
  LinkedReciterDraft _adopting(LinkedReciterDraft draft) {
    if (draft.id == state.draft.id) return draft;
    final Map<String, dynamic>? row = state.copyWith(draft: draft).existingRow;
    if (row == null || '${row['packPath'] ?? ''}'.isNotEmpty) return draft;
    return draft.copyWith(
      nameAr: draft.nameAr.isEmpty ? '${row['nameAr'] ?? ''}' : null,
      nameEn: draft.nameEn.isEmpty ? '${row['nameEn'] ?? ''}' : null,
      riwayah: draft.riwayah.isEmpty ? '${row['riwayah'] ?? ''}' : null,
      version: '${row['version'] ?? draft.version}',
      bitrate: draft.bitrate ?? row['bitrate'] as int?,
      imagePath: draft.imagePath ?? row['imagePath'] as String?,
      attributionAr: draft.attributionAr.isEmpty
          ? '${(row['attribution'] as Map<String, dynamic>?)?['ar'] ?? ''}'
          : null,
      attributionEn: draft.attributionEn.isEmpty
          ? '${(row['attribution'] as Map<String, dynamic>?)?['en'] ?? ''}'
          : null,
    );
  }

  /// Asks the host: the first ayah of every complete surah, and `000` of
  /// every complete `separate` surah, which is the only way the manifest can
  /// say `hasBasmala` for a host that was not built to our layout. Then one
  /// clip is fetched whole to read its bitrate.
  Future<void> probe() async {
    final LinkFile? file = state.file;
    if (file == null || state.probing) return;

    final List<SurahPlan> plan = <SurahPlan>[...state.plan];
    final List<int> targets = <int>[
      for (int i = 0; i < plan.length; i++)
        if (plan[i].complete) i,
    ];
    emit(state.copyWith(probing: true, probeProgress: 0));

    int done = 0;
    for (int start = 0; start < targets.length; start += _probeWidth) {
      final List<int> batch = targets.sublist(
        start,
        (start + _probeWidth).clamp(0, targets.length),
      );
      await Future.wait(<Future<void>>[
        for (final int i in batch)
          () async {
            final SurahPlan s = plan[i];
            final ProbeOutcome first = await _exists(file.urlFor(s.number, 1));
            bool? basmala;
            if (s.separate && first == ProbeOutcome.ok) {
              basmala =
                  await _exists(file.urlFor(s.number, 0)) == ProbeOutcome.ok;
            }
            plan[i] = s.copyWith(probe: first, basmala: basmala);
          }(),
      ]);
      done += batch.length;
      if (isClosed) return;
      emit(
        state.copyWith(
          plan: List<SurahPlan>.unmodifiable(plan),
          probeProgress: targets.isEmpty ? 1 : done / targets.length,
        ),
      );
    }

    final SurahPlan? sample = plan
        .where((SurahPlan s) => s.probe == ProbeOutcome.ok)
        .firstOrNull;
    final int? measured = sample == null
        ? null
        : await _measureBitrate(file.urlFor(sample.number, 1));
    if (isClosed) return;
    final int reachable = plan
        .where((SurahPlan s) => s.probe == ProbeOutcome.ok)
        .length;
    emit(
      state.copyWith(
        probing: false,
        probed: true,
        clearProbeProgress: true,
        measuredBitrate: measured,
        draft: state.draft.bitrate == null && measured != null
            ? state.draft.copyWith(bitrate: measured)
            : null,
        message:
            'The host holds $reachable of ${targets.length} complete surah(s)'
            '${measured == null ? '; the bitrate could not be measured, type it' : ' at about $measured kbps'}.',
      ),
    );
  }

  /// HEAD, and where the host does not allow it, the first byte by GET.
  Future<ProbeOutcome> _exists(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      http.Response response = await _client
          .head(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 405 || response.statusCode == 403) {
        response = await _client
            .get(uri, headers: const <String, String>{'range': 'bytes=0-0'})
            .timeout(const Duration(seconds: 15));
      }
      return switch (response.statusCode) {
        200 || 206 => ProbeOutcome.ok,
        404 || 410 => ProbeOutcome.notFound,
        _ => ProbeOutcome.error,
      };
    } on Object {
      return ProbeOutcome.error;
    }
  }

  /// Bytes over seconds, rounded to the encoder rates that exist. Null when
  /// the clip could not be fetched or timed; the operator types it then.
  Future<int?> _measureBitrate(String url) async {
    Directory? temp;
    try {
      final http.Response response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      temp = Directory.systemTemp.createTempSync('mirqat_probe');
      final File clip = File(p.join(temp.path, 'probe.mp3'))
        ..writeAsBytesSync(response.bodyBytes);
      final Duration length = await _ffmpeg.durationOf(clip);
      if (length.inMilliseconds <= 0) return null;
      final double kbps = response.bodyBytes.length * 8 / length.inMilliseconds;
      const List<int> rates = <int>[32, 48, 64, 96, 128, 160, 192, 256, 320];
      return rates.reduce(
        (int a, int b) => (kbps - a).abs() <= (kbps - b).abs() ? a : b,
      );
    } on Object {
      return null;
    } finally {
      temp?.deleteSync(recursive: true);
    }
  }

  /// Uploads a portrait to the bucket and points the entry at it.
  ///
  /// Named by its own contents beside the reciter's id, so a new photo is a
  /// new path and the rule against overwriting a published path is kept
  /// without an exception.
  Future<void> choosePortrait() async {
    if (state.draft.id.isEmpty) {
      emit(
        state.copyWith(
          error:
              'Give the reciter an id first; the portrait is named after it.',
        ),
      );
      return;
    }
    final String? path;
    try {
      path = await _files.pickImage();
    } on Object catch (e) {
      emit(state.copyWith(error: 'The file panel could not be opened: $e'));
      return;
    }
    if (path == null) return;

    emit(state.copyWith(busy: true));
    try {
      final List<int> bytes = await File(path).readAsBytes();
      final String key =
          'images/${state.draft.id}-'
          '${sha256.convert(bytes).toString().substring(0, 12)}'
          '${p.extension(path).toLowerCase()}';
      await _r2.putObject(
        key: key,
        bytes: bytes,
        contentType: switch (p.extension(path).toLowerCase()) {
          '.png' => 'image/png',
          '.webp' => 'image/webp',
          _ => 'image/jpeg',
        },
      );
      emit(
        state.copyWith(
          busy: false,
          draft: state.draft.copyWith(imagePath: key),
          message: 'Portrait uploaded as $key. Publish to put it on the entry.',
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    } on Object catch (e) {
      emit(
        state.copyWith(busy: false, error: 'The portrait was not uploaded: $e'),
      );
    }
  }

  void removePortrait() =>
      emit(state.copyWith(draft: state.draft.copyWith(clearImage: true)));

  /// Merges the entry into the live manifest and publishes it. Refused while
  /// [LinkedReciterState.problems] stand.
  Future<void> publish() async {
    final Map<String, dynamic>? row = state.row;
    if (row == null) {
      emit(
        state.copyWith(
          error:
              'Not published. ${state.problems.length} thing(s) to fix first.',
        ),
      );
      return;
    }

    final Map<String, dynamic> next = merged(state.manifest, row);
    emit(state.copyWith(busy: true));
    try {
      final String commit = await _pages.publishJson(
        path: _config.manifestPath,
        json: next,
        message:
            'Add linked reciter ${row['id']}: '
            '${(row['surahs'] as List<dynamic>).length} surah(s) at '
            '${row['audioPath']}',
      );
      final String bundled = await _writeBundledCopy(next);
      emit(
        state.copyWith(
          busy: false,
          manifest: next,
          manifestLive: true,
          message:
              'Published${commit.isEmpty ? '' : ' ($commit)'}: ${row['id']} '
              'with ${(row['surahs'] as List<dynamic>).length} surah(s). The '
              'app picks it up on its next launch; Pages can take a minute to '
              'serve it. $bundled',
        ),
      );
    } on AppException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  /// [manifest] with [row] in it, replacing any entry with the same id. The
  /// bucket's address is kept as it is live; a manifest built from nothing
  /// gets the configured one.
  Map<String, dynamic> merged(
    Map<String, dynamic> manifest,
    Map<String, dynamic> row,
  ) {
    final String live = '${manifest['baseUrl'] ?? ''}';
    final List<Map<String, dynamic>> reciters = <Map<String, dynamic>>[
      for (final Object? r
          in manifest['reciters'] as List<dynamic>? ?? const <dynamic>[])
        if (r is Map<String, dynamic> && r['id'] != row['id'])
          Map<String, dynamic>.from(r),
      row,
    ]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
    return <String, dynamic>{
      ...manifest,
      'schemaVersion': manifest['schemaVersion'] ?? 1,
      'baseUrl': live.isEmpty ? _config.publicBase : live,
      'mirrors': manifest['mirrors'] ?? <String>[],
      'reciters': reciters,
    };
  }

  Future<String> _writeBundledCopy(Map<String, dynamic> manifest) async {
    final File? file = bundledCopy;
    if (file == null) {
      return 'Copy the manifest into assets/data/manifest.json so that a fresh '
          'install has it too.';
    }
    try {
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
        flush: true,
      );
      return 'Also written to ${file.path} — commit it, so that a fresh '
          'install starts from the same manifest.';
    } on FileSystemException catch (e) {
      return 'Could not write ${file.path} (${e.message}); copy the manifest '
          'into it by hand.';
    }
  }

  /// The entry as it would be published, for the clipboard.
  String get json {
    final Map<String, dynamic>? row = state.row;
    return row == null
        ? ''
        : '${const JsonEncoder.withIndent('  ').convert(row)}\n';
  }

  @override
  Future<void> close() {
    _client.close();
    return super.close();
  }
}
