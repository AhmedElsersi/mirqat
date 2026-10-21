import 'dart:convert';
import 'dart:developer' as developer;

import '../../core/constants/asset_paths.dart';
import '../datasources/asset_reader.dart';
import '../models/mutashabihat.dart';

/// The bundled index of ayahs that share a phrase, read once and kept.
///
/// No `Either`: there is no failure the reader could act on. A file that is
/// missing — the data not yet imported — or that cannot be read gives the
/// empty index, and the feature simply does not appear.
class MutashabihatRepository {
  MutashabihatRepository(this._assets);

  final AssetReader _assets;
  Future<MutashabihatIndex>? _index;

  Future<MutashabihatIndex> index() => _index ??= _load();

  Future<MutashabihatIndex> _load() async {
    try {
      return MutashabihatIndex.fromJson(
        jsonDecode(await _assets.loadString(AssetPaths.mutashabihat)),
      );
    } catch (e) {
      developer.log(
        'No mutashabihat index ($e); similar ayahs are not offered.',
        name: 'mutashabihat',
      );
      return MutashabihatIndex.empty;
    }
  }
}
