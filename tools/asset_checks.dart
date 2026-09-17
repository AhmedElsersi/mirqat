/// The asset audit, once, so the test suite and the pre-commit CLI cannot
/// drift apart.
///
/// Everything here is driven off `quran.db` and `reciters.json`. There is no
/// list of surah numbers in this file and there must never be one: the next
/// reciter or recording added is checked with no new code.
///
/// Text is checked for every surah, because every surah is listed and
/// readable. Audio is checked only for what a reciter declares in
/// `availableSurahs`, plus any surah directory actually present on disk —
/// never by scanning all 114 surahs for clips nobody claims to have.
///
/// Two entry points share it — `test/assets_integrity_test.dart`, which probes
/// the built asset bundle, and `tools/verify_assets.dart`, which probes the
/// working tree before a commit.
library;

import 'dart:io';

import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/ayah.dart';
import 'package:mirqat/data/models/ayah_timing.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';

/// One check's verdict.
class CheckResult {
  const CheckResult(this.number, this.subject, this.passed, [this.reason = '']);

  const CheckResult.pass(int number, String subject)
    : this(number, subject, true);

  const CheckResult.fail(int number, String subject, String reason)
    : this(number, subject, false, reason);

  /// The check number from the audit table, so a failure here is traceable
  /// back to the requirement that asked for it.
  final int number;

  /// What was checked: a surah, a reciter, a file.
  final String subject;

  final bool passed;

  /// Names the surah, the ayah and the exact problem. A verdict nobody can act
  /// on is not a diagnosis.
  final String reason;

  @override
  String toString() =>
      '${passed ? 'PASS' : 'FAIL'} [$number] $subject'
      '${passed ? '' : ' — $reason'}';
}

/// How the checker reaches non-JSON assets: existence, bytes, and what a
/// directory holds.
///
/// The bundle and the file system answer these differently — the bundle knows
/// only what pubspec declared, which is exactly the difference that let an
/// undeclared `bismillah.mp3` sit in the repo unreachable.
abstract class AssetProbe {
  Future<bool> exists(String path);

  /// Immediate children of [directory], file names only, unordered. Empty when
  /// the directory does not exist.
  Future<List<String>> childrenOf(String directory);

  /// Immediate subdirectories of [directory], names only, unordered. Empty
  /// when the directory does not exist.
  Future<List<String>> childrenDirsOf(String directory);

  /// First [count] bytes, for header sniffing. Empty when unreadable.
  Future<List<int>> head(String path, int count);
}

/// Runs the audit against whatever [loader] and [probe] point at.
///
/// Checks 4, 5 and 7 (NFC, tatweel and BOM in the raw per-surah JSON) are
/// retired with that JSON: `quran.db` is a published edition that is neither
/// NFC-ordered nor tatweel-free, it is never edited, and the loader levels
/// both on read.
Future<List<CheckResult>> runAssetChecks({
  required QuranLocalDataSource loader,
  required AssetProbe probe,
}) async {
  final List<CheckResult> out = <CheckResult>[];

  final List<Surah> surahs = await loader.getSurahs();
  final Map<int, Surah> byNumber = <int, Surah>{
    for (final Surah s in surahs) s.number: s,
  };
  final List<Reciter> reciters = await loader.getReciters();

  // ---- 10: catalog shape -------------------------------------------------
  final List<int> numbers = surahs.map((Surah s) => s.number).toList();
  final List<int> sorted = List<int>.of(numbers)..sort();
  out.add(
    numbers.toSet().length == numbers.length && _sameOrder(numbers, sorted)
        ? const CheckResult.pass(10, 'quran.db')
        : CheckResult.fail(
            10,
            'quran.db',
            'surah numbers must be unique and ascending, got $numbers',
          ),
  );

  // ---- 1–3, 6, 8, 9: text integrity, every surah -------------------------
  for (final Surah surah in surahs) {
    final String subject = 'surah ${surah.number} (${surah.nameEn})';

    List<Ayah> ayahs;
    try {
      // Checks 1, 2 and 3 are enforced by the loader itself — a bad surah
      // throws rather than returning — so driving them through it means a
      // loosened validator fails here too.
      ayahs = await loader.getAyahs(surah.number);
      out.add(CheckResult.pass(1, subject));
      out.add(CheckResult.pass(2, subject));
      out.add(CheckResult.pass(3, subject));
    } on Object catch (e) {
      out.add(CheckResult.fail(1, subject, 'did not load from quran.db: $e'));
      continue;
    }

    out.add(_digitCheck(subject, ayahs));

    // 8 and 9 are enum parses the loader already made; reaching here means
    // both were one of the accepted values.
    out.add(CheckResult.pass(8, subject));
    out.add(CheckResult.pass(9, subject));
  }

  // ---- 11–18: audio wiring, declared surahs only -------------------------
  for (final Reciter reciter in reciters) {
    final Set<int> declared = reciter.availableSurahs.toSet();
    final List<int> incomplete = <int>[];

    for (final int number in reciter.availableSurahs) {
      final String subject = '${reciter.id} surah $number';
      final Surah? surah = byNumber[number];
      if (surah == null) {
        out.add(
          CheckResult.fail(
            11,
            subject,
            'availableSurahs lists surah $number, which is not in quran.db',
          ),
        );
        continue;
      }

      final List<String> missing = <String>[];
      final List<String> unreadable = <String>[];
      for (int ayah = 1; ayah <= surah.ayahCount; ayah++) {
        final String clip = AssetPaths.perAyahFile(
          reciter.basePath,
          surah.number,
          ayah,
        );
        if (!await probe.exists(clip)) {
          missing.add('ayah $ayah -> $clip');
          continue;
        }
        final String? why = _mp3Problem(await probe.head(clip, 16));
        if (why != null) unreadable.add('ayah $ayah -> $clip: $why');
      }
      if (missing.isNotEmpty) incomplete.add(number);

      out.add(
        missing.isEmpty
            ? CheckResult.pass(11, subject)
            : CheckResult.fail(
                11,
                subject,
                'surah ${surah.number} has ${surah.ayahCount} ayahs but these '
                'clips are absent: ${missing.join('; ')}',
              ),
      );
      out.add(
        unreadable.isEmpty
            ? CheckResult.pass(13, subject)
            : CheckResult.fail(13, subject, unreadable.join('; ')),
      );

      // 17: a separate-preamble surah must have a bismillah to play.
      if (surah.bismillahMode == BismillahMode.separatePreamble) {
        final String clip = AssetPaths.bismillahFile(reciter.basePath);
        if (!reciter.hasBismillah) {
          out.add(
            CheckResult.fail(
              17,
              subject,
              'the bismillah is a separate preamble but reciter '
              '"${reciter.id}" declares hasBismillah false, so ayah 1 would '
              'begin with no bismillah',
            ),
          );
        } else {
          out.add(
            await probe.exists(clip)
                ? CheckResult.pass(17, subject)
                : CheckResult.fail(
                    17,
                    subject,
                    'hasBismillah is true but $clip is not there',
                  ),
          );
        }
      }
    }

    // 14: everything declared is playable end to end.
    out.add(
      incomplete.isEmpty
          ? CheckResult.pass(14, reciter.id)
          : CheckResult.fail(
              14,
              reciter.id,
              'availableSurahs lists $incomplete, which have no complete audio '
              'directory — a session on them would fail mid-play',
            ),
    );

    // 12 and 15 look at the surah directories that are actually on disk.
    final List<int> reachableButUnlisted = <int>[];
    for (final String dirName in await probe.childrenDirsOf(reciter.basePath)) {
      if (!RegExp(r'^\d{3}$').hasMatch(dirName)) continue;
      final int number = int.parse(dirName);
      final String dir = '${reciter.basePath}/$dirName';
      final String subject = '${reciter.id} surah $number';
      final Surah? surah = byNumber[number];
      if (surah == null) {
        out.add(
          CheckResult.fail(12, subject, '$dir is not a surah in quran.db'),
        );
        continue;
      }

      // 12: nothing but ayah clips, and nothing numbered past the end.
      final List<String> strays = <String>[];
      for (final String name in await probe.childrenOf(dir)) {
        if (name == 'bismillah.mp3' || name == 'istiadhah.mp3') {
          strays.add(
            '$dir/$name (a per-surah preamble; both preambles are one per '
            'reciter, at ${reciter.basePath}/$name)',
          );
          continue;
        }
        final RegExpMatch? m = RegExp(r'^(\d{3})\.mp3$').firstMatch(name);
        if (m == null) {
          strays.add('$name (not an ayah clip)');
          continue;
        }
        final int n = int.parse(m.group(1)!);
        if (n > surah.ayahCount || n < 1) {
          strays.add('$name (outside 1..${surah.ayahCount})');
        }
      }
      out.add(
        strays.isEmpty
            ? CheckResult.pass(12, subject)
            : CheckResult.fail(
                12,
                subject,
                'surah directory holds ayahs only, but found: '
                '${strays.join(', ')}. quran.db says ${surah.ayahCount} ayahs',
              ),
      );

      if (!declared.contains(number)) {
        bool complete = true;
        for (int ayah = 1; ayah <= surah.ayahCount; ayah++) {
          if (!await probe.exists(
            AssetPaths.perAyahFile(reciter.basePath, number, ayah),
          )) {
            complete = false;
            break;
          }
        }
        if (complete) reachableButUnlisted.add(number);
      }
    }
    out.add(
      reachableButUnlisted.isEmpty
          ? CheckResult.pass(15, reciter.id)
          : CheckResult.fail(
              15,
              reciter.id,
              'surah(s) $reachableButUnlisted have complete audio but are '
              'absent from availableSurahs, so they show as reading-only and '
              'no session can reach them',
            ),
    );

    // 18: the isti'adhah, one per reciter.
    if (reciter.hasIstiadhah) {
      final String clip = AssetPaths.istiadhahFile(reciter.basePath);
      out.add(
        await probe.exists(clip)
            ? CheckResult.pass(18, reciter.id)
            : CheckResult.fail(
                18,
                reciter.id,
                'hasIstiadhah is true but $clip is not there',
              ),
      );
    }
  }

  // ---- 16: the spacer -----------------------------------------------------
  out.add(
    await probe.exists(AssetPaths.silenceSpacer)
        ? const CheckResult.pass(16, 'silence spacer')
        : const CheckResult.fail(
            16,
            'silence spacer',
            '${AssetPaths.silenceSpacer} is missing; every gap in every '
                'session is built from it',
          ),
  );

  // ---- 19–22: timings, declared surahs only -------------------------------
  for (final Reciter reciter in reciters) {
    for (final int number in reciter.availableSurahs) {
      if (!byNumber.containsKey(number)) continue; // Reported by 11.
      final String path = AssetPaths.timingsForSurah(reciter.id, number);
      if (!await probe.exists(path)) continue; // Optional in per_ayah mode.

      final String subject = 'timings ${reciter.id}/$number';
      SurahTimings timings;
      try {
        timings = await loader.getTimings(
          reciterId: reciter.id,
          surahNumber: number,
        );
        out.add(CheckResult.pass(19, subject));
      } on Object catch (e) {
        out.add(CheckResult.fail(19, subject, '$path did not load: $e'));
        continue;
      }
      final List<int> ordered = timings.ayahs.keys.toList()..sort();
      final List<String> inverted = <String>[];
      for (final int n in ordered) {
        final AyahTiming t = timings.ayahs[n]!;
        if (t.startMs >= t.endMs) {

          inverted.add('ayah $n: ${t.startMs}ms..${t.endMs}ms');
        }
      }
      out.add(
        inverted.isEmpty
            ? CheckResult.pass(20, subject)
            : CheckResult.fail(
                20,
                subject,
                'startMs must precede endMs — ${inverted.join('; ')}',
              ),
      );

      final List<String> overlaps = <String>[];
      for (int i = 1; i < ordered.length; i++) {
        final AyahTiming prev = timings.ayahs[ordered[i - 1]]!;
        final AyahTiming cur = timings.ayahs[ordered[i]]!;
        if (cur.startMs < prev.endMs) {
          overlaps.add(
            'ayah ${ordered[i]} starts ${cur.startMs}ms, inside ayah '
            '${ordered[i - 1]} which runs to ${prev.endMs}ms',
          );
        }
      }
      out.add(
        overlaps.isEmpty
            ? CheckResult.pass(21, subject)
            : CheckResult.fail(21, subject, overlaps.join('; ')),
      );

      // 22: whatever preamble the file carries must clear ayah 1.
      final AyahTiming? preamble = timings.istiadhah;
      final AyahTiming? first = timings.ayahs[ordered.isEmpty ? -1 : ordered.first];
      if (preamble == null || first == null) {
        out.add(CheckResult.pass(22, subject));
      } else {
        out.add(
          preamble.endMs <= first.startMs
              ? CheckResult.pass(22, subject)
              : CheckResult.fail(
                  22,
                  subject,
                  'the preamble runs to ${preamble.endMs}ms but ayah '
                  '${ordered.first} starts at ${first.startMs}ms, so they '
                  'overlap',
                ),
        );
      }
    }
  }

  return out;
}

bool _sameOrder(List<int> a, List<int> b) {
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Check 6: no ayah-number marker survives in ayah text. Markers are their
/// own rows in `quran.db`'s words table and must never leak into an ayah.
CheckResult _digitCheck(String subject, List<Ayah> ayahs) {
  for (final Ayah ayah in ayahs) {
    final String text = ayah.text;
    for (int j = 0; j < text.length; j++) {
      final int cp = text.codeUnitAt(j);
      if (cp >= 0x0660 && cp <= 0x0669) {
        return CheckResult.fail(
          6,
          subject,
          'ayah ${ayah.number} carries ${_describeAt(text, j)} — an '
          'ayah-number marker inside the ayah text',
        );
      }
    }
  }
  return CheckResult.pass(6, subject);
}

/// `U+0640 (offset 12)` — enough to locate the character, and deliberately no
/// more of the ayah than that. Quranic text is never quoted into a report.
String _describeAt(String text, int offset) {
  if (offset >= text.length) return 'the end of the text (offset $offset)';
  final int cp = text.codeUnitAt(offset);
  final String hex = cp.toRadixString(16).toUpperCase().padLeft(4, '0');
  return 'U+$hex ${_unicodeName(cp)} at offset $offset';
}

/// Names for the codepoints these checks can actually report. Anything else is
/// described by its block, which is all a reader needs to find it.
String _unicodeName(int cp) {
  const Map<int, String> known = <int, String>{
    0x0640: 'ARABIC TATWEEL',
    0x0660: 'ARABIC-INDIC DIGIT ZERO',
    0x0661: 'ARABIC-INDIC DIGIT ONE',
    0x0662: 'ARABIC-INDIC DIGIT TWO',
    0x0663: 'ARABIC-INDIC DIGIT THREE',
    0x0664: 'ARABIC-INDIC DIGIT FOUR',
    0x0665: 'ARABIC-INDIC DIGIT FIVE',
    0x0666: 'ARABIC-INDIC DIGIT SIX',
    0x0667: 'ARABIC-INDIC DIGIT SEVEN',
    0x0668: 'ARABIC-INDIC DIGIT EIGHT',
    0x0669: 'ARABIC-INDIC DIGIT NINE',
  };
  if (known.containsKey(cp)) return known[cp]!;
  if (cp >= 0x0600 && cp <= 0x06FF) return '(Arabic block)';
  if (cp >= 0x0750 && cp <= 0x077F) return '(Arabic Supplement)';
  if (cp >= 0x08A0 && cp <= 0x08FF) return '(Arabic Extended-A)';
  return '(outside the Arabic blocks)';
}

/// Null when [head] opens a decodable MP3, a reason otherwise.
///
/// Header sniffing only: the bytes are never rewritten, re-encoded or touched
/// (CLAUDE.md A.2 rule 6).
String? _mp3Problem(List<int> head) {
  if (head.isEmpty) return 'file is empty';
  int offset = 0;
  if (head.length >= 10 &&
      head[0] == 0x49 &&
      head[1] == 0x44 &&
      head[2] == 0x33) {
    // ID3v2: a syncsafe size, then the audio. Its presence is proof enough of
    // a real file; the frame sync sits past the tag, which we do not re-read.
    return null;
  }
  if (head.length < 2) return 'file is too short to hold a frame header';
  if (head[offset] != 0xFF || (head[offset + 1] & 0xE0) != 0xE0) {
    return 'no MPEG frame sync and no ID3 tag at the start of the file';
  }
  return null;
}

/// Checks 23 and 24: every directory holding a bundled asset is declared, and
/// nothing declared has gone missing.
///
/// Flutter bundles only the *direct children* of a declared directory, so a
/// nested folder nobody declared is invisible at runtime while looking
/// perfectly present in the repo — the failure mode that hid a reciter-level
/// bismillah in plain sight.
///
/// This reads pubspec.yaml rather than the built bundle on purpose: the bundle
/// under `build/` is synced on add and edit but not on delete, so it is not a
/// trustworthy witness on its own.
/// Directories under `assets/` that deliberately never reach the bundle.
///
/// Empty, and that is the intended state: everything under `assets/` is
/// something the app loads, so everything under `assets/` is declared.
///
/// `assets/brand/` used to be listed here, when it held the icon generator's
/// source artwork. It now holds only the two splash plates the app actually
/// loads and the native splash's first frame, so it is declared like any other
/// runtime directory, and the generator inputs and editing masters live in
/// `brand/` — outside `assets/` entirely, where a directory declaration cannot
/// reach them. That is a better arrangement than an exemption: the rule and
/// the layout agree instead of one carving a hole in the other.
const Set<String> buildTimeOnlyAssetDirs = <String>{};

List<CheckResult> pubspecChecks(String repoRoot) {
  final File pubspec = File('$repoRoot/pubspec.yaml');
  if (!pubspec.existsSync()) {
    return <CheckResult>[
      const CheckResult.fail(23, 'pubspec.yaml', 'pubspec.yaml is not there'),
    ];
  }

  final String text = pubspec.readAsStringSync();
  final int start = text.indexOf('  assets:');
  if (start < 0) {
    return <CheckResult>[
      const CheckResult.fail(23, 'pubspec.yaml', 'no "assets:" section'),
    ];
  }
  final int end = text.indexOf('\n  fonts:', start);
  final String section = text.substring(start, end < 0 ? text.length : end);
  final Set<String> declared = <String>{
    for (final RegExpMatch m
        in RegExp(r'^\s*-\s+(\S+)\s*$', multiLine: true).allMatches(section))
      m.group(1)!,
  };

  final List<CheckResult> out = <CheckResult>[];
  final Directory assets = Directory('$repoRoot/assets');
  final List<String> undeclared = <String>[];

  if (assets.existsSync()) {
    // listSync never yields `assets/` itself, which is deliberate: it holds
    // only README.md, and declaring it would ship documentation to users.
    for (final FileSystemEntity entity in assets.listSync(recursive: true)) {
      if (entity is! Directory) continue;
      final String rel =
          '${entity.path.substring(repoRoot.length + 1).replaceAll(r'\', '/')}/';
      // Fonts are declared file by file under "fonts:", not as a directory.
      if (rel.startsWith('assets/fonts/')) continue;
      // Build-time-only inputs. These are read off disk by the icon and splash
      // generators, which emit platform rasters; the app never loads them, and
      // declaring them would add four 1024px PNGs to every APK for nothing.
      // Narrow and explicit on purpose: the whole point of this check is that
      // "it is in the repo" and "it ships" are different questions, so an
      // exemption has to be a decision someone wrote down, not a pattern that
      // quietly swallows the next real mistake.
      if (buildTimeOnlyAssetDirs.contains(rel)) continue;
      final bool holdsFiles = entity
          .listSync()
          .whereType<File>()
          .any((File f) => !f.uri.pathSegments.last.startsWith('.'));
      if (holdsFiles && !declared.contains(rel)) undeclared.add(rel);
    }
  }
  out.add(
    undeclared.isEmpty
        ? const CheckResult.pass(23, 'pubspec.yaml')
        : CheckResult.fail(
            23,
            'pubspec.yaml',
            'these directories hold assets but are not declared, so their '
            'files never reach the bundle: ${undeclared.join(', ')}',
          ),
  );

  final List<String> stale = <String>[
    for (final String path in declared)
      if (!Directory('$repoRoot/$path').existsSync() &&
          !File('$repoRoot/$path').existsSync())
        path,
  ];
  out.add(
    stale.isEmpty
        ? const CheckResult.pass(24, 'pubspec.yaml')
        : CheckResult.fail(
            24,
            'pubspec.yaml',
            'declared but absent, which fails the build: ${stale.join(', ')}',
          ),
  );

  return out;
}

/// Existence, listing and bytes answered by the working tree.
///
/// Shared by both entry points. The test uses it rather than the built bundle
/// because `flutter test` copies assets into `build/unit_test_assets` on add
/// and edit but never deletes stale ones — so a removed clip would keep
/// answering "present" for as long as the old copy sat there. Whether a file is
/// *declared* is a separate question, and [pubspecChecks] answers that one.
class RepoAssetProbe implements AssetProbe {
  const RepoAssetProbe(this.repoRoot);

  final String repoRoot;

  @override
  Future<bool> exists(String path) async => File('$repoRoot/$path').existsSync();

  @override
  Future<List<String>> childrenOf(String directory) async {
    final Directory dir = Directory('$repoRoot/$directory');
    if (!dir.existsSync()) return const <String>[];
    return <String>[
      for (final FileSystemEntity e in dir.listSync())
        if (e is File && !e.uri.pathSegments.last.startsWith('.'))
          e.uri.pathSegments.last,
    ];
  }

  @override
  Future<List<String>> childrenDirsOf(String directory) async {
    final Directory dir = Directory('$repoRoot/$directory');
    if (!dir.existsSync()) return const <String>[];
    return <String>[
      for (final FileSystemEntity e in dir.listSync())
        if (e is Directory)
          e.uri.pathSegments.lastWhere((String s) => s.isNotEmpty),
    ];
  }

  @override
  Future<List<int>> head(String path, int count) async {
    final File file = File('$repoRoot/$path');
    if (!file.existsSync()) return const <int>[];
    final RandomAccessFile handle = file.openSync();
    try {
      return handle.readSync(count);
    } finally {
      handle.closeSync();
    }
  }
}
