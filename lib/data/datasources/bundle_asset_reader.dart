import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'asset_reader.dart';

/// Reads from the app bundle.
class BundleAssetReader implements AssetReader {
  BundleAssetReader([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  @override
  Future<String> loadString(String path) async {
    try {
      return await _bundle.loadString(path);
    } on FlutterError catch (e) {
      throw assetMissing(path, e);
    }
  }
}
