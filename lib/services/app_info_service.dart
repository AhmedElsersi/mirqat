import '../core/constants/asset_paths.dart';
import '../data/datasources/asset_reader.dart';
import '../data/models/app_info.dart';

/// What the app says about itself — About us, Our goal, the developer's card.
///
/// Today this is the copy bundled with the app. It is a service rather than a
/// constant because the same file is to be published beside the audio
/// manifest and edited from the admin tool, so that the words can change
/// without a release; the screens ask here and never learn where the answer
/// came from.
///
/// It never fails: a file that is missing or unreadable reads as
/// [AppInfo.empty], and the screens show what they have.
class AppInfoService {
  AppInfoService(this._assets);

  final AssetReader _assets;

  Future<AppInfo>? _loaded;

  Future<AppInfo> load() => _loaded ??= _read();

  Future<AppInfo> _read() async {
    try {
      return AppInfo.parse(await _assets.loadString(AssetPaths.bundledAppInfo));
    } on Object {
      return AppInfo.empty;
    }
  }
}
