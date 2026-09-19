import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/bundle_asset_reader.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';

import '../tools/asset_checks.dart';
import 'quran_db_fixtures.dart';

/// Checks 1–22 of the asset audit, run against the bundle the app would ship.
///
/// The audit that produced these was a one-off; this is the same checker
/// (`tools/asset_checks.dart`) wired to the real loader, so it re-runs on every
/// `flutter test`. It iterates `quran.db` and `reciters.json`: **the next
/// recording added is checked with no new test code**, which is the entire
/// point. A hardcoded list of surah numbers anywhere in this file would defeat
/// it.
///
/// Existence is probed against the working tree, not the built bundle:
/// `flutter test` syncs `build/unit_test_assets` on add and edit but never
/// removes a stale copy, so a deleted clip would keep answering "present". The
/// separate question — whether a file that exists is actually *declared*, and
/// so reaches the bundle at all — is what [pubspecChecks] covers, and it is how
/// a reciter-level `bismillah.mp3` sat unreachable in the tree while looking
/// perfectly present.
///
/// Reciter JSON still goes through the real loader over the real bundle, so a
/// loader bug fails here rather than hiding behind a direct file read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuranLocalDataSource loader;
  late AssetProbe probe;
  late AssetReader reader;

  setUp(() {
    reader = BundleAssetReader();
    loader = QuranLocalDataSourceImpl(reader, RepoQuranDatabase());
    probe = RepoAssetProbe(Directory.current.path);
  });

  test('every shipped asset passes the audit', () async {
    final List<CheckResult> results = await runAssetChecks(
      loader: loader,
      probe: probe,
    );

    expect(
      results,
      isNotEmpty,
      reason: 'the checker ran nothing — the catalog failed to load',
    );

    final List<CheckResult> failures = results
        .where((CheckResult r) => !r.passed)
        .toList();

    expect(
      failures,
      isEmpty,
      reason:
          '${failures.length} of ${results.length} asset checks failed, '
          'grouped by what they were checking:\n${_bySubject(failures)}',
    );
  });

  test('every asset directory is declared in pubspec.yaml', () {
    final List<CheckResult> failures = pubspecChecks(
      Directory.current.path,
    ).where((CheckResult r) => !r.passed).toList();

    expect(
      failures,
      isEmpty,
      reason:
          'a file that is not declared never reaches the bundle, however '
          'present it looks in the repo:\n${failures.join('\n')}',
    );
  });

  group('the audit is load-bearing, not decorative', () {
    test(
      'no surah audio ships: the bundle holds preambles and nothing else',
      () {
        // The 11 MB of per-ayah clips moved to the CDN, and the app now streams
        // or downloads every surah. Re-adding a surah directory here would put
        // that weight back into every install without anyone deciding to.
        final Directory reciters = Directory('assets/audio');
        final List<String> surahDirectories = <String>[
          for (final FileSystemEntity reciter in reciters.listSync())
            if (reciter is Directory)
              for (final FileSystemEntity child in reciter.listSync())
                if (child is Directory) child.path,
        ];

        expect(
          surahDirectories,
          isEmpty,
          reason: 'surah audio belongs on the CDN, not in the bundle',
        );
        expect(
          Directory('assets/data/timings').existsSync(),
          isFalse,
          reason:
              'timings describe a bundled whole-surah recording, and none '
              'ships any more',
        );
        // What stays is small and load-bearing: the two preambles and the
        // spacer, 137 KB that let a session open before a byte is fetched.
        for (final String path in <String>[
          'assets/audio/ahmed_khalil_shaheen/bismillah.mp3',
          'assets/audio/ahmed_khalil_shaheen/istiadhah.mp3',
          AssetPaths.silenceSpacer,
        ]) {
          expect(File(path).existsSync(), isTrue, reason: path);
        }
      },
    );

    test('a reciter declaring a surah with no audio behind it fails rather '
        'than crashing at runtime', () async {
      // The last surah in the mushaf the reciter does not already claim — by
      // position, never by number — added to availableSurahs with no clips.
      final List<Reciter> reciters = await loader.getReciters();
      final Reciter reciter = reciters.first;
      final int unrecorded = (await loader.getSurahs())
          .map((Surah s) => s.number)
          .lastWhere((int n) => !reciter.hasSurah(n));

      final List<dynamic> catalog =
          jsonDecode(await reader.loadString(AssetPaths.recitersCatalog))
              as List<dynamic>;
      final Map<String, dynamic> entry = catalog.first as Map<String, dynamic>;
      entry['availableSurahs'] = <int>[
        ...(entry['availableSurahs'] as List<dynamic>).cast<int>(),
        unrecorded,
      ];

      final QuranLocalDataSource fake = QuranLocalDataSourceImpl(
        _PatchedReader(reader, <String, String>{
          AssetPaths.recitersCatalog: jsonEncode(catalog),
        }),
        RepoQuranDatabase(),
      );

      final List<CheckResult> caused = await _failuresCausedBy(
        loader: loader,
        baseline: probe,
        altered: probe,
        alteredLoader: fake,
      );
      expect(
        caused,
        isNotEmpty,
        reason: 'a declared surah with no audio must not pass the audit',
      );
      expect(
        caused.map((CheckResult r) => r.subject).join(' '),
        contains('surah $unrecorded'),
        reason: 'the failure must name the surah that is missing its audio',
      );
    });
  });

  group('reciter portraits', () {
    test('every catalogued imagePath exists and is declared', () async {
      final List<Reciter> reciters = await loader.getReciters();
      expect(
        reciters,
        isNotEmpty,
        reason: 'the reciter catalog failed to load',
      );

      // Iterates the catalog: a second reciter's photo is checked with no new
      // test code, and a reciter with no photo is skipped rather than failed —
      // imagePath is nullable on purpose.
      for (final Reciter reciter in reciters) {
        final String? path = reciter.imagePath;
        if (path == null) continue;

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

      // `checked` is allowed to be zero now, and usually is: portraits moved
      // to the CDN, where a reciter added to the manifest can have one without
      // an app release. The loop stays because a bundled portrait remains
      // legal — a reciter whose licence forbids a CDN copy would have one —
      // and it must still be declared if it exists.
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

      // A portrait directory is optional now, but if one exists it has to be
      // declared — a file in the repo that never reaches the bundle is the
      // failure this whole audit exists for.
      final Directory portraits = Directory('assets/images/reciters');
      if (portraits.existsSync() &&
          portraits.listSync().whereType<File>().isNotEmpty) {
        expect(
          declared,
          contains('assets/images/reciters/'),
          reason: 'portraits are in the repo but nothing declares them',
        );
      }

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
          for (final String name in <String>[
            'bismillah.mp3',
            'istiadhah.mp3',
          ]) {
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

/// Failures that [altered] (and [alteredLoader], when given) causes and the
/// baseline does not.
///
/// A delta, not an absolute count: these are negative controls, and they must
/// report on the change they injected rather than on the state of the repo
/// around them. Asserting a total would make an unrelated broken asset show up
/// here as a second, misleading failure.
Future<List<CheckResult>> _failuresCausedBy({
  required QuranLocalDataSource loader,
  required AssetProbe baseline,
  required AssetProbe altered,
  QuranLocalDataSource? alteredLoader,
}) async {
  String key(CheckResult r) => '${r.number}|${r.subject}';

  final Set<String> before = <String>{
    for (final CheckResult r in await runAssetChecks(
      loader: loader,
      probe: baseline,
    ))
      if (!r.passed) key(r),
  };

  return <CheckResult>[
    for (final CheckResult r in await runAssetChecks(
      loader: alteredLoader ?? loader,
      probe: altered,
    ))
      if (!r.passed && !before.contains(key(r))) r,
  ];
}
