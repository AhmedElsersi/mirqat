import '../../core/error/exceptions.dart';

/// Indirection over the asset bundle so the loaders can be pointed at
/// deliberately corrupted fixtures in tests.
///
/// Deliberately Flutter-free: [BundleAssetReader] in `bundle_asset_reader.dart`
/// is the app's implementation, but keeping this interface pure Dart lets a
/// plain `dart run` tool drive the real loaders over the file system — which
/// is how `tools/verify_assets.dart` validates a bundle before it is committed.
abstract class AssetReader {
  Future<String> loadString(String path);
}

/// The message every implementation should give when a path is not there, so
/// the pubspec trap reads the same from a test, the CLI and the running app.
String assetMissingMessage(String path, Object cause) =>
    'Asset "$path" is not available. Check that the file exists and that its '
    'directory is listed under "assets:" in pubspec.yaml — Flutter only '
    'bundles the direct children of a declared directory. ($cause)';

/// Thrown shape shared by the readers.
AssetNotFoundException assetMissing(String path, Object cause) =>
    AssetNotFoundException(path, assetMissingMessage(path, cause));
