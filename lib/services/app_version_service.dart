import 'package:package_info_plus/package_info_plus.dart';

/// The version of the app that is running, as the store knows it.
class InstalledVersion {
  const InstalledVersion({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;
}

/// Reads the running app's own version. Behind a class so that a test can say
/// which version is installed.
class AppVersionService {
  AppVersionService();

  Future<InstalledVersion?>? _read;

  /// Null where the platform will not say. Nothing depends on it: no version
  /// means no update prompt and no line at the foot of Settings.
  Future<InstalledVersion?> read() => _read ??= _fromPlatform();

  static Future<InstalledVersion?> _fromPlatform() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return InstalledVersion(
        version: info.version,
        buildNumber: info.buildNumber,
      );
    } on Object {
      return null;
    }
  }
}
