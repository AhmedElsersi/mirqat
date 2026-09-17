import 'dart:io';

import 'package:mirqat/core/constants/asset_paths.dart';
import 'package:mirqat/data/datasources/asset_reader.dart';
import 'package:mirqat/data/datasources/quran_database_opener.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'asset_checks.dart';

/// Validates an asset bundle *before* it is committed.
///
///     dart run tools/verify_assets.dart [repo root]
///
/// Same checks as `test/assets_integrity_test.dart`, same implementation
/// (`asset_checks.dart`), down to the probe and the pubspec pass — the only
/// difference is that this one reads the catalog off disk — `quran.db` opened
/// in place, read-only, through the ffi sqlite engine — instead of through the
/// asset bundle, so it runs on a tree that has never been built.
///
/// Exits 0 when everything passes, 1 otherwise.
Future<void> main(List<String> args) async {
  final Directory root = Directory(
    args.isEmpty ? Directory.current.path : args.first,
  );
  if (!root.existsSync()) {
    stderr.writeln('No such directory: ${root.path}');
    exit(2);
  }

  sqfliteFfiInit();
  final AssetReader reader = _FileAssetReader(root);
  final QuranLocalDataSource loader = QuranLocalDataSourceImpl(
    reader,
    _RepoDatabase('${root.path}/${AssetPaths.quranDatabase}'),
  );

  List<CheckResult> results;
  try {
    results = await runAssetChecks(
      loader: loader,
      probe: RepoAssetProbe(root.path),
    );
  } on Object catch (e) {
    stderr.writeln('The catalog itself did not load, so nothing could be '
        'checked:\n  $e');
    exit(1);
  }

  results.addAll(pubspecChecks(root.path));

  final int width = results
      .map((CheckResult r) => r.subject.length)
      .fold(7, (int a, int b) => a > b ? a : b);

  stdout.writeln('${'#'.padRight(4)} ${'SUBJECT'.padRight(width)} RESULT  REASON');
  stdout.writeln('-' * (width + 40));
  for (final CheckResult r in results) {
    stdout.writeln(
      '${r.number.toString().padRight(4)} ${r.subject.padRight(width)} '
      '${r.passed ? 'PASS' : 'FAIL'}    ${r.passed ? '' : r.reason}',
    );
  }

  final int failed = results.where((CheckResult r) => !r.passed).length;
  stdout.writeln('-' * (width + 40));
  stdout.writeln(
    '${results.length} checks, ${results.length - failed} PASS, $failed FAIL',
  );
  exit(failed == 0 ? 0 : 1);
}

/// Reads asset paths straight off the working tree.
class _FileAssetReader implements AssetReader {
  _FileAssetReader(this._root);

  final Directory _root;

  @override
  Future<String> loadString(String path) async {
    final File file = File('${_root.path}/$path');
    if (!file.existsSync()) throw assetMissing(path, 'no such file');
    return file.readAsString();
  }
}

/// The repo's own `quran.db`, opened where it lies. Read-only: the audit must
/// never be the thing that changes the file it audits.
class _RepoDatabase implements QuranDatabaseOpener {
  _RepoDatabase(this._path);

  final String _path;
  Future<Database>? _opening;

  @override
  Future<Database> open() => _opening ??= databaseFactoryFfi.openDatabase(
    _path,
    options: OpenDatabaseOptions(readOnly: true),
  );
}
