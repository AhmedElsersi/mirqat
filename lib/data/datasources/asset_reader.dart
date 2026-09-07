import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/error/exceptions.dart';

/// Indirection over the asset bundle so the loaders can be pointed at
/// deliberately corrupted fixtures in tests.
abstract class AssetReader {
  Future<String> loadString(String path);
}

/// Reads from the app bundle.
class BundleAssetReader implements AssetReader {
  BundleAssetReader([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  @override
  Future<String> loadString(String path) async {
    try {
      return await _bundle.loadString(path);
    } on FlutterError catch (e) {
      throw AssetNotFoundException(
        path,
        'Asset "$path" is not in the bundle. Check that the file exists and '
        'that its directory is listed under "assets:" in pubspec.yaml — '
        'Flutter only bundles the direct children of a declared directory. '
        '($e)',
      );
    }
  }
}
