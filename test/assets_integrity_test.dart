import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/bundle_asset_reader.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';

import '../tools/asset_checks.dart';

/// Checks 1–22 of the asset audit, run against the bundle the app would ship.
///
/// The audit that produced these was a one-off; this is the same checker
/// (`tools/asset_checks.dart`) wired to the real loader, so it re-runs on every
/// `flutter test`. It iterates `surahs.json`: **the next surah added is checked
/// with no new test code**, which is the entire point. A hardcoded list of
/// surah numbers anywhere in this file would defeat it.
///
/// Existence is probed against the working tree, not the built bundle:
/// `flutter test` syncs `build/unit_test_assets` on add and edit but never
/// removes a stale copy, so a deleted clip would keep answering "present". The
/// separate question — whether a file that exists is actually *declared*, and
/// so reaches the bundle at all — is what [pubspecChecks] covers, and it is how
/// a reciter-level `bismillah.mp3` sat unreachable in the tree while looking
/// perfectly present.
///
/// JSON still goes through the real loader over the real bundle, so a loader
/// bug fails here rather than hiding behind a direct file read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranLocalDataSource loader;
  late AssetProbe probe;
  late AssetReader reader;

  setUp(() {
    reader = BundleAssetReader();
    loader = QuranLocalDataSourceImpl(reader);
    probe = RepoAssetProbe(Directory.current.path);
  });

  test('every shipped asset passes the audit', () async {
    final List<CheckResult> results = await runAssetChecks(
      loader: loader,
      probe: probe,
      readRaw: reader.loadString,
    );

    expect(
      results,
      isNotEmpty,
      reason: 'the checker ran nothing — the catalog failed to load',
    );

    final List<CheckResult> failures =
        results.where((CheckResult r) => !r.passed).toList();

    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} of ${results.length} asset checks failed, '
          'grouped by what they were checking:\n${_bySubject(failures)}',
    );
  });

  test('every asset directory is declared in pubspec.yaml', () {
    final List<CheckResult> failures = pubspecChecks(Directory.current.path)
        .where((CheckResult r) => !r.passed)
        .toList();

    expect(
      failures,
      isEmpty,
      reason:
          'a file that is not declared never reaches the bundle, however '
          'present it looks in the repo:\n${failures.join('\n')}',
    );
  });

  group('the audit is load-bearing, not decorative', () {
    test('a catalog entry with no assets behind it fails rather than '
        'crashing at runtime', () async {
      // A fake surah 99 with no ayah file, no audio and no timings — the shape
      // a half-finished bundle takes.
      final QuranLocalDataSource fake = QuranLocalDataSourceImpl(
        _PatchedReader(reader, <String, String>{
          'assets/data/surahs.json': '''
[
  {"number": 1, "nameAr": "الفاتحة", "nameEn": "Al-Fatiha", "ayahCount": 7,
   "revelationPlace": "makkah", "bismillahMode": "counted_as_ayah_1"},
  {"number": 99, "nameAr": "س", "nameEn": "Fake", "ayahCount": 3,
   "revelationPlace": "makkah", "bismillahMode": "separate_preamble"}
]''',
        }),
      );

      final List<CheckResult> results = await runAssetChecks(
        loader: fake,
        probe: probe,
        readRaw: reader.loadString,
      );

      final List<CheckResult> failures =
          results.where((CheckResult r) => !r.passed).toList();
      expect(
        failures,
        isNotEmpty,
        reason: 'a surah with no assets behind it must not pass the audit',
      );
      expect(
        failures.map((CheckResult r) => r.subject).join(' '),
        contains('99'),
        reason: 'the failure must name the surah that is missing its assets',
      );
    });

    test('a missing ayah clip is reported by name', () async {
      const String hidden = 'assets/audio/ahmed_khalil_shaheen/001/003.mp3';
      final List<CheckResult> caused = await _failuresCausedBy(
        loader: loader,
        reader: reader,
        baseline: probe,
        altered: _HidingProbe(probe, hidden),
      );

      expect(
        caused,
        isNotEmpty,
        reason: 'removing $hidden must be caught by something',
      );
      expect(
        caused.map((CheckResult r) => '$r').join('\n'),
        contains('001/003.mp3'),
        reason: 'the message must name the file that went missing',
      );
    });

    test('reverting the refactor — a bismillah back under a surah '
        'directory — fails', () async {
      final List<CheckResult> caused = await _failuresCausedBy(
        loader: loader,
        reader: reader,
        baseline: probe,
        altered: _AddingProbe(
          probe,
          'assets/audio/ahmed_khalil_shaheen/112/bismillah.mp3',
        ),
      );

      expect(caused, isNotEmpty);
      expect(
        caused.map((CheckResult r) => '$r').join('\n'),
        contains('112/bismillah.mp3'),
        reason: 'surah directories hold ayahs only',
      );
    });
  });

  group('reciter portraits', () {
    test('every catalogued imagePath exists and is declared', () async {
      final List<Reciter> reciters = await loader.getReciters();
      expect(reciters, isNotEmpty, reason: 'the reciter catalog failed to load');

      // Iterates the catalog: a second reciter's photo is checked with no new
      // test code, and a reciter with no photo is skipped rather than failed —
      // imagePath is nullable on purpose.
      int checked = 0;
      for (final Reciter reciter in reciters) {
        final String? path = reciter.imagePath;
        if (path == null) continue;
        checked++;

        // On disk. Probed against the working tree for the same reason the
        // clips are: `flutter test` never removes a stale copy from
        // build/unit_test_assets, so a deleted file would keep answering
        // "present" through the bundle.
        expect(
          await probe.exists(path),
          isTrue,
          reason:
              'reciter "${reciter.id}" declares imagePath "$path", which is '
              'not in the repo',
        );

        // And reachable from the bundle, which is the separate question: an
        // undeclared directory leaves the file present in the repo and absent
        // from the app, which is exactly how the reciter-level bismillah sat
        // unreachable for a phase.
        await expectLater(
          rootBundle.load(path),
          completes,
          reason:
              'reciter "${reciter.id}" declares imagePath "$path", which is '
              'not declared in pubspec.yaml and so never reaches the bundle',
        );
      }

      // Guards the guard: if every entry were null this test would pass
      // without asserting anything, and that is a state worth noticing rather
      // than a green tick.
      expect(
        checked,
        greaterThan(0),
        reason:
            'no reciter in the catalog has an imagePath, so this check '
            'asserted nothing — is that intended?',
      );
    });

    test('a portrait directory that is not declared is caught', () {
      // The failure mode this guards against, stated directly: the file is in
      // the repo, so `exists` passes, and only the pubspec declaration decides
      // whether it ships.
      final List<String> declared = File('pubspec.yaml')
          .readAsLinesSync()
          .map((String l) => l.trim())
          .where((String l) => l.startsWith('- assets/'))
          .map((String l) => l.substring(2))
          .toList();

      expect(
        declared,
        contains('assets/images/reciters/'),
        reason: 'reciter portraits live here and must be bundled',
      );

      // Nothing under assets/ is exempt from check 23 any more: the icon
      // generator's inputs and the editing masters moved to brand/, outside
      // assets/, so the rule needs no hole carved in it.
      expect(
        buildTimeOnlyAssetDirs,
        isEmpty,
        reason:
            'an exemption means some directory under assets/ is unchecked; '
            'prefer moving build-time inputs out of assets/ entirely',
      );
      expect(
        declared.any((String d) => buildTimeOnlyAssetDirs.contains(d)),
        isFalse,
        reason:
            'a build-time-only directory must not also be declared — that '
            'ships the generator inputs to users',
      );
    });
  });

  group('preamble layout', () {
    test('both preambles are reciter-level and reachable from the '
        'bundle', () async {
      for (final Reciter reciter in await loader.getReciters()) {
        if (reciter.hasIstiadhah) {
          await rootBundle.load('${reciter.basePath}/istiadhah.mp3');
        }
        if (reciter.hasBismillah) {
          await rootBundle.load('${reciter.basePath}/bismillah.mp3');
        }
      }
    });

    test('no surah directory holds a preamble', () async {
      final List<Surah> surahs = await loader.getSurahs();
      for (final Reciter reciter in await loader.getReciters()) {
        for (final Surah surah in surahs) {
          final String dir =
              '${reciter.basePath}/${surah.number.toString().padLeft(3, '0')}';
          for (final String name in <String>['bismillah.mp3', 'istiadhah.mp3']) {
            expect(
              await probe.exists('$dir/$name'),
              isFalse,
              reason:
                  '$dir/$name duplicates the reciter-level clip at '
                  '${reciter.basePath}/$name',
            );
          }
        }
      }
    });

    test('every surah that needs a bismillah has one, whatever its '
        'mode', () async {
      for (final Surah surah in await loader.getSurahs()) {
        for (final Reciter reciter in await loader.getReciters()) {
          if (!reciter.hasSurah(surah.number)) continue;
          final bool needs =
              surah.bismillahMode == BismillahMode.separatePreamble;
          if (!needs) continue;
          expect(
            reciter.hasBismillah,
            isTrue,
            reason:
                'surah ${surah.number} is separate_preamble but '
                '"${reciter.id}" declares no bismillah',
          );
          expect(
            await probe.exists('${reciter.basePath}/bismillah.mp3'),
            isTrue,
          );
        }
      }
    });
  });
}

/// A probe with one asset removed, to prove a deletion is caught.
class _HidingProbe implements AssetProbe {
  _HidingProbe(this._inner, this._hidden);

  final AssetProbe _inner;
  final String _hidden;

  @override
  Future<bool> exists(String path) async =>
      path != _hidden && await _inner.exists(path);

  @override
  Future<List<String>> childrenOf(String directory) async {
    final List<String> all = await _inner.childrenOf(directory);
    return all
        .where((String name) => '$directory/$name' != _hidden)
        .toList();
  }

  @override
  Future<List<int>> head(String path, int count) =>
      path == _hidden ? Future<List<int>>.value(const <int>[])
          : _inner.head(path, count);
}

/// A probe with one extra asset, to prove a regression is caught.
class _AddingProbe implements AssetProbe {
  _AddingProbe(this._inner, this._extra);

  final AssetProbe _inner;
  final String _extra;

  @override
  Future<bool> exists(String path) async =>
      path == _extra || await _inner.exists(path);

  @override
  Future<List<String>> childrenOf(String directory) async {
    final List<String> all = await _inner.childrenOf(directory);
    final String prefix = '$directory/';
    if (_extra.startsWith(prefix) &&
        !_extra.substring(prefix.length).contains('/')) {
      return <String>[...all, _extra.substring(prefix.length)];
    }
    return all;
  }

  @override
  Future<List<int>> head(String path, int count) => path == _extra
      ? Future<List<int>>.value(const <int>[0xFF, 0xFB, 0x00, 0x00])
      : _inner.head(path, count);
}

/// Serves substitute content for named paths, everything else from the bundle.
class _PatchedReader implements AssetReader {
  _PatchedReader(this._inner, this._patches);

  final AssetReader _inner;
  final Map<String, String> _patches;

  @override
  Future<String> loadString(String path) async =>
      _patches[path] ?? await _inner.loadString(path);
}

/// Groups failures under the surah, reciter or file they belong to, so one
/// aggregate failure still reads as a per-subject report.
String _bySubject(List<CheckResult> failures) {
  final Map<String, List<CheckResult>> grouped = <String, List<CheckResult>>{};
  for (final CheckResult r in failures) {
    grouped.putIfAbsent(r.subject, () => <CheckResult>[]).add(r);
  }
  return grouped.entries
      .map(
        (MapEntry<String, List<CheckResult>> e) =>
            '${e.key}:\n  ${e.value.map((CheckResult r) => 'check ${r.number}: ${r.reason}').join('\n  ')}',
      )
      .join('\n');
}

/// Failures that [altered] causes and [baseline] does not.
///
/// A delta, not an absolute count: these are negative controls, and they must
/// report on the change they injected rather than on the state of the repo
/// around them. Asserting a total would make an unrelated broken asset show up
/// here as a second, misleading failure.
Future<List<CheckResult>> _failuresCausedBy({
  required QuranLocalDataSource loader,
  required AssetReader reader,
  required AssetProbe baseline,
  required AssetProbe altered,
}) async {
  String key(CheckResult r) => '${r.number}|${r.subject}';

  final Set<String> before = <String>{
    for (final CheckResult r in await runAssetChecks(
      loader: loader,
      probe: baseline,
      readRaw: reader.loadString,
    ))
      if (!r.passed) key(r),
  };

  return <CheckResult>[
    for (final CheckResult r in await runAssetChecks(
      loader: loader,
      probe: altered,
      readRaw: reader.loadString,
    ))
      if (!r.passed && !before.contains(key(r))) r,
  ];
}
