// Publishes one or more surah recordings: split, verify, upload, manifest.
//
// The same services the macOS admin tool drives, without the window — for a
// batch of recordings that all split cleanly. Anything that does not match its
// expected segment count is reported and skipped; fix those in the admin tool,
// where the segments can be seen beside their ayahs.
//
//   dart run tool/publish_surah.dart --dry-run 001 112 113
//   dart run tool/publish_surah.dart --reciter ahmed_khalil_shaheen 112
//   dart run tool/publish_surah.dart --replace 103        # a path published
//                                                          but never named in
//                                                          a live manifest
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:mirqat/admin/config/admin_config.dart';
import 'package:mirqat/admin/services/ffmpeg_runner.dart';
import 'package:mirqat/admin/services/pack_publisher.dart';
import 'package:mirqat/admin/services/publish_guard.dart';
import 'package:mirqat/admin/services/r2_client.dart';
import 'package:mirqat/admin/services/recitation_weight.dart';
import 'package:mirqat/admin/services/segment_audit.dart';
import 'package:mirqat/admin/services/segment_planner.dart';
import 'package:mirqat/admin/services/surah_splitter.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database_opener.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final bool dryRun = args.contains('--dry-run');
  final bool replace = args.contains('--replace');
  final int reciterFlag = args.indexOf('--reciter');
  final String reciterId = reciterFlag == -1
      ? 'ahmed_khalil_shaheen'
      : args[reciterFlag + 1];
  final int silenceFlag = args.indexOf('--min-silence');
  final int minimumSilenceMs = silenceFlag == -1
      ? 350
      : int.parse(args[silenceFlag + 1]);
  final bool autoTune = args.contains('--auto');
  final bool alignToText = args.contains('--align');
  // Re-publish a surah the manifest already lists, for when its objects have
  // been removed from the bucket and a better cut is going up in their place.
  // Deliberately not --replace: that one turns off the no-overwrite guard as
  // well, and the guard is exactly what should still fire if a deletion was
  // missed. This only says "do not skip it for being in the manifest".
  final bool recut = args.contains('--recut');
  // What the recordings hold besides the ayahs. Some reciters' files start
  // straight at ayah 1; others open with the isti'adhah.
  final bool noBasmala = args.contains('--no-basmala');
  final bool hasIstiadhah = args.contains('--has-istiadhah');
  // Cut and encode, then stop: the clips are left in build/recut/<NNN>/ so
  // they can be measured (tool/audit_audio.py --dir) before anything is
  // uploaded or deleted.
  final bool exportOnly = args.contains('--export-only');
  final int exportDirFlag = args.indexOf('--export-dir');
  final String exportDir = exportDirFlag == -1
      ? p.join('build', 'recut')
      : args[exportDirFlag + 1];
  // Upload clips that were exported and audited earlier, instead of cutting
  // again: <dir>/<NNN>/<NNN><AAA>.mp3. What was measured is then, byte for
  // byte, what goes live — a re-cut at upload time is only the same cut for
  // as long as nobody has touched the aligner in between.
  final int publishFromFlag = args.indexOf('--publish-from');
  final String? publishFrom = publishFromFlag == -1
      ? null
      : args[publishFromFlag + 1];
  // Where the whole-surah recordings are: <dir>/<NNN>.mp3.
  final int sourceDirFlag = args.indexOf('--source-dir');
  final String sourceDir = sourceDirFlag == -1
      ? p.join(Platform.environment['HOME']!, 'Downloads', reciterId)
      : args[sourceDirFlag + 1];
  final int alignMinFlag = args.indexOf('--align-min');
  final int alignMinimumMs = alignMinFlag == -1
      ? 180
      : int.parse(args[alignMinFlag + 1]);
  // Surahs whose ayahs are in the bucket but whose pack is not — an upload
  // that died between the last ayah and the zip. The pack is rebuilt from the
  // published ayahs themselves, so the repair needs nothing left over from the
  // run that failed.
  final int repairFlag = args.indexOf('--repair-pack');
  final Set<int> repairPack = repairFlag == -1
      ? const <int>{}
      : _parseRange(args[repairFlag + 1]);

  // Surahs whose objects are already in the bucket and are known good, but
  // which never reached a manifest — a run that uploaded and then died before
  // writing one. Adopting reads the published pack back and records the digest
  // of the bytes that are actually up there, rather than re-cutting audio that
  // is already correct and can never be overwritten anyway.
  final int adoptFlag = args.indexOf('--adopt');
  final Set<int> adopt = adoptFlag == -1
      ? const <int>{}
      : _parseRange(args[adoptFlag + 1]);

  final List<int> named = surahArguments(args);
  // `--all` means every surah with a recording, minus anything the published
  // manifest already has: re-cutting a surah that is live would change its
  // audio under a name people have already downloaded.
  final List<int> surahNumbers = args.contains('--all')
      ? <int>[for (int n = 1; n <= 114; n++) n]
      : named;
  if (surahNumbers.isEmpty) {
    stderr.writeln('Name at least one surah number, or pass --all.');
    exit(2);
  }

  final AdminConfig config = _config();
  final FfmpegRunner ffmpeg = FfmpegRunner();
  stdout.writeln(await ffmpeg.version());

  final QuranRepository quran = QuranRepositoryImpl(
    QuranLocalDataSourceImpl(const _FileAssets(), _RepoDatabase()),
  );
  final List<Reciter> catalog = (await quran.getReciters()).getOrElse(
    () => throw StateError('reciters.json did not load'),
  );
  final Reciter reciter = catalog.firstWhere(
    (Reciter r) => r.id == reciterId,
    orElse: () => throw StateError('no reciter "$reciterId" in the catalog'),
  );

  final R2Client r2 = R2Client(adminConfig: config);
  final PackPublisher publisher = PackPublisher();

  final Set<int> alreadyPublished = <int>{
    for (final Object? entry
        in ((await publisher.fetchManifest())['reciters'] as List<dynamic>? ??
            <dynamic>[]))
      if (entry is Map<String, dynamic> && entry['id'] == reciterId)
        for (final Object? s
            in entry['surahs'] as List<dynamic>? ?? <dynamic>[])
          (s! as Map<String, dynamic>)['n'] as int,
  };
  if (alreadyPublished.isNotEmpty) {
    stdout.writeln(
      'already published for $reciterId: '
      '${(alreadyPublished.toList()..sort()).join(', ')}',
    );
  }

  // Fetched once and merged into across the whole batch. Re-fetching per
  // surah would start from the published manifest every time, so each write
  // would drop the surah before it — a batch that ends with one entry.
  Map<String, dynamic> manifest = await publisher.fetchManifest();
  final List<String> published = <String>[];
  final List<String> skipped = <String>[];

  for (final int number in surahNumbers) {
    final String fileName = '${number.toString().padLeft(3, '0')}.mp3';
    // One directory, named or defaulted, and nowhere else. This used to fall
    // back to a loose NNN.mp3 in ~/Downloads, which is how a run meant for one
    // reciter quietly cut fourteen files that had been dropped there for a
    // different purpose: a number is not an identity, and any reciter's
    // surah 33 is called 033.mp3.
    final File source = File(p.join(sourceDir, fileName));
    if (publishFrom == null && !source.existsSync()) {
      skipped.add('$number: no $fileName in $sourceDir');
      continue;
    }

    // A dry run writes nothing, so a surah already live is still worth
    // examining — that is how a bad split gets diagnosed after the fact.
    if (!dryRun && !recut && !exportOnly && alreadyPublished.contains(number)) {
      continue;
    }

    final Surah surah = (await quran.getSurah(
      number,
    )).getOrElse(() => throw StateError('no surah $number'));

    if (publishFrom != null) {
      final String line = await _publishExported(
        directory: Directory(p.join(publishFrom, _pad3(number))),
        surah: surah,
        reciter: reciter,
        config: config,
        publisher: publisher,
        r2: r2,
        ffmpeg: ffmpeg,
        quran: quran,
        replace: replace,
        onMerge: (int packBytes, String packSha, bool hasBasmala) =>
            manifest = publisher.mergeSurah(
              manifest: manifest,
              reciter: reciter,
              surah: surah,
              bitrate: config.bitrate,
              baseUrl: config.publicBase,
              packBytes: packBytes,
              packSha256: packSha,
              hasBasmala: hasBasmala,
            ),
      );
      if (line.startsWith('!')) {
        skipped.add('$number: ${line.substring(1)}');
        stdout.writeln('\n$number ${surah.nameAr}  ${line.substring(1)}');
      } else {
        published.add('$number ${surah.nameAr} ($line)');
        stdout.writeln('\n$number ${surah.nameAr}  published: $line');
      }
      continue;
    }

    if (repairPack.contains(number)) {
      final String line = await _repairPack(
        surah: surah,
        reciter: reciter,
        config: config,
        publisher: publisher,
        r2: r2,
        onMerge: (int packBytes, String packSha) =>
            manifest = publisher.mergeSurah(
              manifest: manifest,
              reciter: reciter,
              surah: surah,
              bitrate: config.bitrate,
              baseUrl: config.publicBase,
              packBytes: packBytes,
              packSha256: packSha,
              hasBasmala: surah.bismillahMode == BismillahMode.separatePreamble,
            ),
      );
      if (line.startsWith('!')) {
        skipped.add('$number: ${line.substring(1)}');
        stdout.writeln('\n$number ${surah.nameAr}  ${line.substring(1)}');
      } else {
        published.add('$number ${surah.nameAr} ($line)');
        stdout.writeln('\n$number ${surah.nameAr}  pack repaired: $line');
      }
      continue;
    }

    if (adopt.contains(number)) {
      final String line = await _adopt(
        surah: surah,
        reciter: reciter,
        config: config,
        publisher: publisher,
        onMerge: (int packBytes, String packSha) =>
            manifest = publisher.mergeSurah(
              manifest: manifest,
              reciter: reciter,
              surah: surah,
              bitrate: config.bitrate,
              baseUrl: config.publicBase,
              packBytes: packBytes,
              packSha256: packSha,
              hasBasmala: surah.bismillahMode == BismillahMode.separatePreamble,
            ),
      );
      if (line.startsWith('!')) {
        skipped.add('$number: ${line.substring(1)}');
        stdout.writeln('\n$number ${surah.nameAr}  ${line.substring(1)}');
      } else {
        published.add('$number ${surah.nameAr} ($line)');
        stdout.writeln('\n$number ${surah.nameAr}  adopted: $line');
      }
      continue;
    }

    final Duration total = await ffmpeg.durationOf(source);
    stdout.writeln(
      '\n${surah.number} ${surah.nameAr}  ${_mmss(total)}  '
      '${surah.ayahCount} ayahs, ${surah.bismillahMode.name}',
    );

    // What this recording holds besides the ayahs — the operator's to say,
    // because recordings differ (see SegmentPlan).
    final List<int> weights = await _weightsFor(
      quran,
      surah,
      hasBasmala: !noBasmala,
      hasIstiadhah: hasIstiadhah,
    );

    SegmentPlan plan;
    int usedMs = minimumSilenceMs;

    if (alignToText) {
      // The same service the admin screen's Split button calls, so a surah
      // cut from here and one cut from there are cut the same way.
      final SplitResult result = await SurahSplitter(ffmpeg: ffmpeg).split(
        source: source,
        surah: surah,
        weights: weights,
        thresholdDb: FfmpegRunner.defaultThresholdDb,
        minimumSilence: Duration(milliseconds: minimumSilenceMs),
        recordingHasBasmala: !noBasmala,
        recordingHasIstiadhah: hasIstiadhah,
        candidateMinimum: Duration(milliseconds: alignMinimumMs),
      );
      plan = result.plan;
      stdout.writeln(
        result.method == SplitMethod.aligned
            ? '  aligned to the text from ${result.candidates.length} '
                  'candidate pauses, widest stretch without one '
                  '${(result.widestStretchWithoutAPause.inMilliseconds / 1000).toStringAsFixed(1)}s'
            : '  threshold split kept (${result.candidates.length} candidate '
                  'pauses were available)',
      );
    } else {
      plan = await _planAt(
        ffmpeg: ffmpeg,
        source: source,
        surah: surah,
        total: total,
        minimumSilenceMs: minimumSilenceMs,
        hasBasmala: !noBasmala,
        hasIstiadhah: hasIstiadhah,
      );
      if (!plan.countMatches && autoTune) {
        final _Tuning? tuned = await _tune(
          ffmpeg: ffmpeg,
          source: source,
          surah: surah,
          total: total,
        );
        if (tuned != null) {
          plan = tuned.plan;
          usedMs = tuned.minimumSilenceMs;
          stdout.writeln(
            '  tuned: ${tuned.thresholdDb.toStringAsFixed(0)}dB / '
            '${tuned.minimumSilenceMs}ms '
            '(holds across ${tuned.windowMs}ms of settings)',
          );
        }
      }
    }

    stdout.writeln(
      '  ${plan.actualCount} segments, expected ${plan.expectedCount}'
      '${usedMs == minimumSilenceMs ? '' : ' at ${usedMs}ms'}',
    );

    final PublishDecision decision = const PublishGuard().decide(plan: plan);
    if (decision is PublishBlocked) {
      skipped.add('$number: ${decision.reason}');
      stdout.writeln('  SKIPPED — ${decision.reason}');
      continue;
    }

    // A count that matches can still be wrong, so the shape is printed rather
    // than assumed: a segment far shorter than a second is a fragment of
    // silence, and one much longer than its text warrants holds two ayahs.
    final List<AudioSegment> byLength = <AudioSegment>[...plan.segments]
      ..sort(
        (AudioSegment a, AudioSegment b) => a.duration.compareTo(b.duration),
      );
    stdout.writeln(
      '  shortest ${(byLength.first.duration.inMilliseconds / 1000).toStringAsFixed(2)}s, '
      'longest ${(byLength.last.duration.inMilliseconds / 1000).toStringAsFixed(2)}s',
    );
    _reportFit(plan, weights);

    if (dryRun) continue;

    // The bucket never overwrites (A.7), so a surah whose objects are already
    // up would fail on its first PUT — after re-cutting and re-encoding every
    // ayah. Asking first turns twenty wasted minutes into one HEAD, and keeps
    // a batch of a hundred surahs from dying on one of them.
    // Both the ayahs and the pack: deleting one and not the other leaves a
    // surah that re-cuts fine, uploads every ayah, and only then fails on the
    // zip — which would strand a fresh set of orphans exactly like the ones
    // this check exists to report.
    // Everything but the isti'adhah, which is cut and not published.
    final List<PlannedSegment> publishedSegments = plan.published;

    final String firstKey = config.audioKey(
      reciterId: reciter.id,
      surah: surah.number,
      ayah: publishedSegments.first.ayahNumber,
    );
    final String packK = config.packKey(
      reciterId: reciter.id,
      surah: surah.number,
    );
    final List<String> occupied = <String>[
      if (!exportOnly && !replace && await r2.head(firstKey) != null) firstKey,
      if (!exportOnly && !replace && await r2.head(packK) != null) packK,
    ];
    if (occupied.isNotEmpty) {
      skipped.add(
        '$number: still in the bucket but not in the manifest — delete '
        '${occupied.join(' and ')} from the R2 dashboard, then re-run it',
      );
      stdout.writeln(
        '  still in the bucket (${occupied.length} keys), '
        'left alone',
      );
      continue;
    }

    final Directory staging = Directory(
      exportOnly
          ? p.join(exportDir, _pad3(number))
          : p.join(Directory.systemTemp.path, 'mirqat_publish', '$number'),
    );
    // A stale clip from an earlier cut must not be measured as part of this
    // one, so the directory starts empty.
    if (exportOnly && staging.existsSync()) staging.deleteSync(recursive: true);
    staging.createSync(recursive: true);
    final List<File> exported = <File>[];
    for (final PlannedSegment item in publishedSegments) {
      final File out = File(
        p.join(
          staging.path,
          '${_pad3(surah.number)}${_pad3(item.ayahNumber)}.mp3',
        ),
      );
      await ffmpeg.exportSegment(
        source: source,
        destination: out,
        segment: item.segment,
        bitrate: config.bitrate,
      );
      exported.add(out);
    }

    if (exportOnly) {
      published.add(
        '$number ${surah.nameAr} (${exported.length} clips, not uploaded)',
      );
      stdout.writeln('  exported ${exported.length} clips to ${staging.path}');
      continue;
    }

    final List<int> pack;
    try {
      for (int i = 0; i < exported.length; i++) {
        await r2.putFile(
          key: config.audioKey(
            reciterId: reciter.id,
            surah: surah.number,
            ayah: publishedSegments[i].ayahNumber,
          ),
          file: exported[i],
          replace: replace,
        );
      }

      pack = publisher.buildPack(exported);
      await r2.putObject(
        key: config.packKey(reciterId: reciter.id, surah: surah.number),
        bytes: pack,
        contentType: 'application/zip',
        replace: replace,
      );
    } on Object catch (e) {
      // One surah's upload failing is not a reason to abandon the ninety
      // behind it. The surah is left out of the manifest, so nothing half
      // uploaded can be reached by the app, and the run reports it at the end.
      //
      // Deliberately every error, not just UploadException: this caught only
      // that at first, and a reset socket — which is not an UploadException —
      // ended a sixteen-surah run after six. R2Client retries transport
      // failures now, so reaching here means they did not come back; the rest
      // of the batch is still worth finishing.
      skipped.add('$number: upload failed — $e');
      stdout.writeln('  upload failed, moving on: $e');
      continue;
    }

    // Merged one surah at a time, against the manifest as it now stands, so a
    // batch builds up rather than each run overwriting the last.
    manifest = publisher.mergeSurah(
      manifest: manifest,
      reciter: reciter,
      surah: surah,
      bitrate: config.bitrate,
      baseUrl: config.publicBase,
      packBytes: pack.length,
      packSha256: PackPublisher.digestOf(pack),
      hasBasmala: plan.expectsBasmala,
    );
    published.add('$number ${surah.nameAr} (${exported.length} objects)');
    stdout.writeln('  published ${exported.length} objects + pack');
  }

  if (published.isNotEmpty) {
    final Directory out = Directory('build')..createSync(recursive: true);
    // An export uploads nothing, so there is no manifest change to write.
    if (!dryRun && !exportOnly) {
      stdout.writeln(
        '\nwrote ${publisher.writeManifest(manifest: manifest, directory: out).path}',
      );
    }
    final File report = File(p.join(out.path, 'review.md'));
    _writeReviewReport(report);
    stdout.writeln('wrote ${report.path}');
  }

  stdout.writeln('\n--- published ---');
  for (final String line in published) {
    stdout.writeln('  $line');
  }
  if (skipped.isNotEmpty) {
    stdout.writeln('--- needs the admin tool ---');
    for (final String line in skipped) {
      stdout.writeln('  $line');
    }
  }

  r2.close();
  publisher.close();
}

/// Flags whose next argument is their value, not a surah number.
///
/// Named rather than guessed at, because both guesses are wrong in a way that
/// costs a publish: "a number is a surah unless it follows any --flag" eats
/// the 35 in `--align 35`, and "every number is a surah" publishes the 350 in
/// `--min-silence 350` as surah 350.
const Set<String> kFlagsTakingAValue = <String>{
  '--reciter',
  '--min-silence',
  '--align-threshold',
  '--align-min',
  '--adopt',
  '--repair-pack',
  '--export-dir',
  '--source-dir',
  '--publish-from',
};

/// The surah numbers named on the command line, in the order given.
List<int> surahArguments(List<String> args) => <int>[
  for (int i = 0; i < args.length; i++)
    if (int.tryParse(args[i]) != null &&
        args[i].length <= 3 &&
        (i == 0 || !kFlagsTakingAValue.contains(args[i - 1])))
      int.parse(args[i]),
];

/// Expands "3-34,40,42" into the numbers it names.
Set<int> _parseRange(String spec) {
  final Set<int> out = <int>{};
  for (final String part in spec.split(',')) {
    final List<String> ends = part.split('-');
    if (ends.length == 2) {
      for (int n = int.parse(ends[0]); n <= int.parse(ends[1]); n++) {
        out.add(n);
      }
    } else {
      out.add(int.parse(part));
    }
  }
  return out;
}

/// Uploads clips that were exported earlier (`--export-only`) and audited.
///
/// Checked again here rather than trusted: every ayah `quran.db` lists must be
/// present, nothing else may be, a `000` file is only allowed where the surah
/// has a basmala of its own, and no clip may be out of line with its text. A
/// directory that fails any of those is refused whole.
///
/// Returns a one-line summary, or a line starting with `!` on refusal.
Future<String> _publishExported({
  required Directory directory,
  required Surah surah,
  required Reciter reciter,
  required AdminConfig config,
  required PackPublisher publisher,
  required R2Client r2,
  required FfmpegRunner ffmpeg,
  required QuranRepository quran,
  required bool replace,
  required void Function(int packBytes, String packSha, bool hasBasmala)
  onMerge,
}) async {
  if (!directory.existsSync()) return '!no exported clips at ${directory.path}';

  final String prefix = _pad3(surah.number);
  final Map<int, File> clips = <int, File>{
    for (final File file in directory.listSync().whereType<File>())
      if (RegExp('^$prefix\\d{3}\\.mp3\$').hasMatch(p.basename(file.path)))
        int.parse(p.basename(file.path).substring(3, 6)): file,
  };

  final bool hasBasmala = clips.containsKey(0);
  if (hasBasmala && surah.bismillahMode != BismillahMode.separatePreamble) {
    return '!a ${prefix}000.mp3 is there, but this surah has no basmala of its own';
  }
  final List<int> missing = <int>[
    for (int a = 1; a <= surah.ayahCount; a++)
      if (!clips.containsKey(a)) a,
  ];
  if (missing.isNotEmpty) return '!ayahs missing: ${missing.take(10).toList()}';
  final List<int> extra = <int>[
    for (final int a in clips.keys)
      if (a < 0 || a > surah.ayahCount) a,
  ];
  if (extra.isNotEmpty) return '!unexpected files for ayahs $extra';

  final List<int> order = clips.keys.toList()..sort();
  final List<int> weights = await _weightsFor(
    quran,
    surah,
    hasBasmala: hasBasmala,
  );
  final List<double> durations = <double>[
    for (final int a in order)
      (await ffmpeg.durationOf(clips[a]!)).inMilliseconds / 1000,
  ];
  final List<int> suspects = suspectSegments(durations, weights);
  if (suspects.isNotEmpty) {
    return '!not clean — clips out of line with their text: '
        '${<int>[for (final int i in suspects) order[i]]}';
  }

  final String packK = config.packKey(
    reciterId: reciter.id,
    surah: surah.number,
  );
  final String firstKey = config.audioKey(
    reciterId: reciter.id,
    surah: surah.number,
    ayah: order.first,
  );
  // Replacing is the operator's explicit decision (--replace), and this is
  // the one place it is safe to honour without a second thought: everything
  // above has already established that what is about to go up is complete
  // and clean. A surah's clips always carry the same names, so writing over
  // them replaces the surah whole — one copy, no orphans, nothing deleted.
  final List<String> occupied = <String>[
    if (!replace && await r2.head(firstKey) != null) firstKey,
    if (!replace && await r2.head(packK) != null) packK,
  ];
  if (occupied.isNotEmpty) {
    return '!already published (${occupied.join(', ')}) — pass --replace to '
        'put these audited clips in its place';
  }
  // The one leftover replacing cannot cover: an old basmala clip when the new
  // cut has none. It is never requested once the manifest says hasBasmala:
  // false, but it is worth saying that it is there.
  final bool staleBasmala =
      replace &&
      !hasBasmala &&
      await r2.head(
            config.audioKey(
              reciterId: reciter.id,
              surah: surah.number,
              ayah: 0,
            ),
          ) !=
          null;

  final List<File> files = <File>[for (final int a in order) clips[a]!];
  try {
    for (final int a in order) {
      await r2.putFile(
        key: config.audioKey(
          reciterId: reciter.id,
          surah: surah.number,
          ayah: a,
        ),
        file: clips[a]!,
        replace: replace,
      );
    }
    final List<int> pack = publisher.buildPack(files);
    await r2.putObject(
      key: packK,
      bytes: pack,
      contentType: 'application/zip',
      replace: replace,
    );
    onMerge(pack.length, PackPublisher.digestOf(pack), hasBasmala);
    return '${files.length} clips + pack, ${pack.length} bytes'
        '${staleBasmala ? ' (an old ${prefix}000.mp3 is left, unreferenced)' : ''}';
  } on Object catch (e) {
    return '!upload failed — $e';
  }
}

/// Rebuilds and uploads the pack for a surah whose ayahs are already
/// published but whose zip never made it.
///
/// The ayahs are fetched back from the CDN rather than taken from whatever the
/// failed run left in a temp directory: the published bytes are the ones the
/// pack has to agree with, and they are still there whether or not anything
/// local survived. Every ayah must be present — a pack assembled around a hole
/// would install a surah missing an ayah, and the count is the only thing
/// standing between that and a session.
///
/// Returns a one-line summary, or a line starting with `!` on refusal.
Future<String> _repairPack({
  required Surah surah,
  required Reciter reciter,
  required AdminConfig config,
  required PackPublisher publisher,
  required R2Client r2,
  required void Function(int packBytes, String packSha) onMerge,
}) async {
  final String packK = config.packKey(
    reciterId: reciter.id,
    surah: surah.number,
  );
  if (await r2.head(packK) != null) {
    return '!a pack is already there; nothing to repair';
  }

  final bool separate = surah.bismillahMode == BismillahMode.separatePreamble;
  final Directory staging = Directory(
    p.join(Directory.systemTemp.path, 'mirqat_repair', '${surah.number}'),
  )..createSync(recursive: true);

  final List<File> files = <File>[];
  for (int ayah = separate ? 0 : 1; ayah <= surah.ayahCount; ayah++) {
    final Uri url = config.publicUrlFor(
      config.audioKey(reciterId: reciter.id, surah: surah.number, ayah: ayah),
    );
    final http.Response response = await http.get(url);
    if (response.statusCode != 200) {
      return '!ayah $ayah is not published (HTTP ${response.statusCode}) — '
          'republish the surah instead';
    }
    final File out = File(
      p.join(staging.path, '${_pad3(surah.number)}${_pad3(ayah)}.mp3'),
    )..writeAsBytesSync(response.bodyBytes);
    files.add(out);
  }

  final List<int> pack = publisher.buildPack(files);
  await r2.putObject(key: packK, bytes: pack, contentType: 'application/zip');
  onMerge(pack.length, PackPublisher.digestOf(pack));
  return '${files.length} files, ${pack.length} bytes';
}

/// Records a surah whose objects are already in the bucket.
///
/// The pack is read back from the CDN and digested, so what lands in the
/// manifest describes the bytes that are genuinely published — not what a
/// re-cut would have produced. The entry count is checked against quran.db
/// first: adopting a short pack would name every later ayah wrongly, which is
/// the one mistake this whole tool is built to prevent.
///
/// Returns a one-line summary, or a line starting with `!` on refusal.
Future<String> _adopt({
  required Surah surah,
  required Reciter reciter,
  required AdminConfig config,
  required PackPublisher publisher,
  required void Function(int packBytes, String packSha) onMerge,
}) async {
  final String key = config.packKey(reciterId: reciter.id, surah: surah.number);
  final Uri url = config.publicUrlFor(key);

  final http.Response response = await http.get(url);
  if (response.statusCode != 200) {
    return '!no pack at $key (HTTP ${response.statusCode})';
  }

  final List<int> bytes = response.bodyBytes;
  final int expected =
      surah.ayahCount +
      (surah.bismillahMode == BismillahMode.separatePreamble ? 1 : 0);

  final int entries;
  try {
    entries = ZipDecoder().decodeBytes(bytes).files.length;
  } on Object catch (e) {
    return '!pack at $key will not open ($e)';
  }
  if (entries != expected) {
    return '!pack holds $entries files, expected $expected — leave it alone';
  }

  onMerge(bytes.length, PackPublisher.digestOf(bytes));
  return '$entries files, ${bytes.length} bytes';
}

/// A plan at one setting.
Future<SegmentPlan> _planAt({
  required FfmpegRunner ffmpeg,
  required File source,
  required Surah surah,
  required Duration total,
  required int minimumSilenceMs,
  bool hasBasmala = true,
  bool hasIstiadhah = false,
}) async => SegmentPlan(
  surah: surah,
  recordingHasBasmala: hasBasmala,
  recordingHasIstiadhah: hasIstiadhah,
  segments: const SegmentPlanner().segmentsFrom(
    totalDuration: total,
    silences: await ffmpeg.detectSilences(
      source,
      minimumSilence: Duration(milliseconds: minimumSilenceMs),
    ),
  ),
);

class _Tuning {
  const _Tuning({
    required this.plan,
    required this.minimumSilenceMs,
    required this.thresholdDb,
    required this.windowMs,
  });

  final SegmentPlan plan;
  final int minimumSilenceMs;
  final double thresholdDb;

  /// How wide the band of settings that all produce this count is.
  final int windowMs;
}

/// Finds a threshold and a minimum-silence that produce the expected count.
///
/// Two knobs, and both matter: one set of recordings sits at −25 dB and needs
/// a −35 dB threshold, another is mastered ten decibels louder and never drops
/// below −20. Sweeping only the gap length finds nothing in the second set —
/// every surah comes back as one segment.
///
/// Detection runs once per threshold, not once per combination: `silencedetect`
/// reports every gap at or above the length it was given, so asking for short
/// ones and filtering the list afterwards is the same answer for a fraction of
/// the decoding.
///
/// The *middle of the widest band* that matches is chosen. A count that appears
/// at one exact setting is a coincidence; one that holds across a range is the
/// recording's own shape.
Future<_Tuning?> _tune({
  required FfmpegRunner ffmpeg,
  required File source,
  required Surah surah,
  required Duration total,
}) async {
  const List<double> thresholds = <double>[-20, -25, -30, -35, -18, -15, -40];
  const int step = 50;
  const int from = 200;
  const int to = 2000;

  for (final double threshold in thresholds) {
    final List<AudioSegment> all = await ffmpeg.detectSilences(
      source,
      threshold: threshold,
      minimumSilence: const Duration(milliseconds: 150),
    );
    if (all.isEmpty) continue;

    final Map<int, SegmentPlan> matches = <int, SegmentPlan>{};
    for (int ms = from; ms <= to; ms += step) {
      final Duration minimum = Duration(milliseconds: ms);
      final SegmentPlan plan = SegmentPlan(
        surah: surah,
        segments: const SegmentPlanner().segmentsFrom(
          totalDuration: total,
          silences: <AudioSegment>[
            for (final AudioSegment silence in all)
              if (silence.duration >= minimum) silence,
          ],
        ),
      );
      if (plan.countMatches) matches[ms] = plan;
    }
    if (matches.isEmpty) continue;

    final List<int> settings = matches.keys.toList()..sort();
    List<int> best = <int>[settings.first];
    List<int> run = <int>[settings.first];
    for (int i = 1; i < settings.length; i++) {
      if (settings[i] - settings[i - 1] == step) {
        run.add(settings[i]);
      } else {
        run = <int>[settings[i]];
      }
      if (run.length > best.length) best = <int>[...run];
    }

    final int middle = best[best.length ~/ 2];
    return _Tuning(
      plan: matches[middle]!,
      minimumSilenceMs: middle,
      thresholdDb: threshold,
      windowMs: (best.length - 1) * step,
    );
  }
  return null;
}

/// Letters per segment: the basmala, where the surah takes one, then each
/// ayah. Recitation time tracks how much there is to pronounce.
Future<List<int>> _weightsFor(
  QuranRepository quran,
  Surah surah, {
  bool hasBasmala = true,
  bool hasIstiadhah = false,
}) async {
  final List<Ayah> ayahs = (await quran.getAyahs(
    surah.number,
  )).getOrElse(() => const <Ayah>[]);
  final bool expectsBasmala =
      surah.bismillahMode == BismillahMode.separatePreamble && hasBasmala;

  // Al-Fatiha's ayah 1 *is* the basmala, so its words come out of the catalog.
  String basmalaText = '';
  if (expectsBasmala) {
    final List<Ayah> fatiha = (await quran.getAyahRange(
      1,
      startAyah: 1,
      endAyah: 1,
    )).getOrElse(() => const <Ayah>[]);
    basmalaText = fatiha.isEmpty ? '' : fatiha.first.text;
  }

  return segmentWeights(
    ayahTexts: <String>[for (final Ayah ayah in ayahs) ayah.text],
    basmalaText: basmalaText,
    hasBasmala: expectsBasmala,
    hasIstiadhah: hasIstiadhah,
  );
}

/// How well the split's durations track the text's shape.
///
/// A split can have the right number of segments and still be wrong, so the
/// evidence is printed rather than assumed: how closely each segment's length
/// follows how much text it holds, and the ones that do not.
/// What a published surah still needs a human to check.
class _Review {
  _Review({
    required this.surah,
    required this.nameAr,
    required this.r,
    required this.tooShort,
    required this.tooLong,
  });

  final int surah;
  final String nameAr;
  final double r;

  /// Zero-based segment indices, where 0 is the basmala for a `separate`
  /// surah — the same numbering the admin tool's review list shows.
  final List<int> tooShort;
  final List<int> tooLong;

  bool get needsEars => tooShort.isNotEmpty || tooLong.isNotEmpty || r < 0.85;
}

final List<_Review> _reviews = <_Review>[];

/// Writes the list of what to listen to, worst first.
void _writeReviewReport(File file) {
  final List<_Review> needing =
      _reviews.where((_Review r) => r.needsEars).toList()
        ..sort((_Review a, _Review b) => a.r.compareTo(b.r));

  final StringBuffer out = StringBuffer()
    ..writeln('# Review list')
    ..writeln()
    ..writeln(
      'Every surah below was split by aligning the reciter\'s own pauses to '
      'the shape of the text, published, and is live. The count is right in '
      'each case; what no machine can check is whether each segment holds the '
      'ayah it is filed under.',
    )
    ..writeln()
    ..writeln(
      '`r` is how closely segment lengths follow how much text each ayah '
      'holds: above ~0.9 the split follows the surah, near 0 it does not. '
      'Segment indices are zero-based and match the admin tool\'s list, so '
      'index 0 is the basmala where a surah has one.',
    )
    ..writeln()
    ..writeln('| surah | | r | too short | too long |')
    ..writeln('|---|---|---|---|---|');

  for (final _Review review in needing) {
    out.writeln(
      '| ${review.surah} | ${review.nameAr} | ${review.r.toStringAsFixed(2)} '
      '| ${review.tooShort.isEmpty ? '—' : review.tooShort.join(', ')} '
      '| ${review.tooLong.isEmpty ? '—' : review.tooLong.join(', ')} |',
    );
  }

  final List<_Review> fine = _reviews
      .where((_Review r) => !r.needsEars)
      .toList();
  out
    ..writeln()
    ..writeln(
      '${fine.length} surah(s) came out clean by these measures: '
      '${fine.map((_Review r) => r.surah).join(', ')}. Clean means nothing '
      'looked wrong, not that anyone has listened.',
    );

  file.writeAsStringSync(out.toString());
}

void _reportFit(SegmentPlan plan, List<int> weights) {
  final List<double> durations = <double>[
    for (final AudioSegment s in plan.segments)
      s.duration.inMilliseconds / 1000,
  ];
  if (durations.length != weights.length) return;

  final double meanD =
      durations.reduce((double a, double b) => a + b) / durations.length;
  final double meanW = weights.reduce((int a, int b) => a + b) / weights.length;
  double covariance = 0;
  double varianceD = 0;
  double varianceW = 0;
  for (int i = 0; i < durations.length; i++) {
    final double dd = durations[i] - meanD;
    final double dw = weights[i] - meanW;
    covariance += dd * dw;
    varianceD += dd * dd;
    varianceW += dw * dw;
  }
  final double r = covariance / (sqrt(varianceD) * sqrt(varianceW));
  final double pace = meanD / meanW;

  final List<int> suspects = suspectSegments(durations, weights);

  // The two shapes that are always wrong, whatever the model thinks: a segment
  // too short to be an ayah, and one long enough to hold two.
  final List<int> tooShort = <int>[
    for (int i = 0; i < durations.length; i++)
      if (durations[i] < 1.5) i,
  ];
  final List<int> tooLong = <int>[
    for (int i = 0; i < durations.length; i++)
      if (durations[i] > weights[i] * pace * 2.5 && durations[i] > 20) i,
  ];

  stdout.writeln(
    '  fit: r=${r.toStringAsFixed(3)}, '
    'under 1.5s: ${tooShort.length}, over 2.5x: ${tooLong.length}'
    '${tooShort.isEmpty ? '' : ' short${tooShort.take(8).toList()}'}'
    '${tooLong.isEmpty ? '' : ' long${tooLong.take(8).toList()}'}',
  );
  stdout.writeln(
    suspects.isEmpty
        ? '  every clip is in line with its text'
        : '  SUSPECT: ${suspects.length} clips out of line with their text '
              '${suspects.take(12).toList()}',
  );

  _reviews.removeWhere((_Review r) => r.surah == plan.surah.number);
  _reviews.add(
    _Review(
      surah: plan.surah.number,
      nameAr: plan.surah.nameAr,
      r: r,
      tooShort: tooShort,
      tooLong: tooLong,
    ),
  );
}

AdminConfig _config() {
  final Map<String, String> env = <String, String>{};
  for (final String line in File('admin.env').readAsLinesSync()) {
    final String t = line.trim();
    if (t.isEmpty || t.startsWith('#') || !t.contains('=')) continue;
    final int i = t.indexOf('=');
    env[t.substring(0, i).trim()] = t.substring(i + 1).trim();
  }
  return AdminConfig(
    accountId: env['R2_ACCOUNT_ID']!,
    accessKey: env['R2_ACCESS_KEY']!,
    secretKey: env['R2_SECRET_KEY']!,
    bucket: env['R2_BUCKET']!,
    endpoint: env['R2_ENDPOINT']!,
    publicBase: env['R2_PUBLIC_BASE']!,
    bitrate: int.parse(env['AUDIO_BITRATE']!),
  );
}

String _pad3(int n) => n.toString().padLeft(3, '0');

String _mmss(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Reads the catalog off disk: this is a plain Dart program with no bundle.
class _FileAssets implements AssetReader {
  const _FileAssets();

  @override
  Future<String> loadString(String path) async => File(path).readAsStringSync();
}

class _RepoDatabase implements QuranDatabaseOpener {
  Future<Database>? _opening;

  @override
  Future<Database> open() {
    sqfliteFfiInit();
    return _opening ??= databaseFactoryFfi.openDatabase(
      File(AssetPaths.quranDatabase).absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
  }
}
