import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Hands an image, or a file, to the platform's share sheet — WhatsApp, mail, whatever
/// the device offers.
///
/// Implemented over a platform channel rather than a package, so the approved
/// dependency list is untouched (CLAUDE.md A.4), the same way the keep-awake
/// toggle and the admin tool's file panel are. Android wraps the file in a
/// `FileProvider` URI and fires `ACTION_SEND`; iOS presents a
/// `UIActivityViewController`. Nothing is uploaded by the app itself: the
/// share sheet is the user handing the image on, not a network call of ours
/// (A.2 rule 3 is about the app's own fetches).
class ShareService {
  ShareService([
    this._channel = const MethodChannel('com.mirqat.app/share'),
    this._tempDirectory = getTemporaryDirectory,
  ]);

  final MethodChannel _channel;

  /// Where the image is written before the platform is pointed at it. The
  /// temporary directory by default — on Android that is the cache dir, which
  /// is exactly what the manifest's share `FileProvider` exposes.
  final Future<Directory> Function() _tempDirectory;

  /// Whether this platform has a share sheet behind the channel at all.
  /// Callers use it to not offer a button that would do nothing.
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Opens the share sheet on a copy of the file at [path] — a backup, to
  /// save to Drive or Downloads or to send. Copied under the temp directory
  /// first, because on Android that is all the share `FileProvider` reaches.
  /// `false`, quietly, as for [shareImage].
  Future<bool> shareFile(String path, {required String mimeType}) async {
    try {
      final Directory dir = Directory(
        p.join((await _tempDirectory()).path, 'share'),
      );
      await dir.create(recursive: true);
      final File copy = await File(
        path,
      ).copy(p.join(dir.path, p.basename(path)));
      await _channel.invokeMethod<void>('shareFile', <String, String?>{
        'path': copy.path,
        'mimeType': mimeType,
      });
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      debugPrint('share failed: ${e.message}');
      return false;
    } on FileSystemException catch (e) {
      debugPrint('share failed: ${e.message}');
      return false;
    }
  }

  /// Writes [bytes] under the temp directory as [filename] and opens the
  /// share sheet on it, with [text] as the accompanying caption where the
  /// receiving app takes one.
  ///
  /// Returns whether the sheet was opened. `false` is quiet — a platform
  /// without a handler or a platform error is the caller's cue to say the
  /// share did not happen, never a crash.
  Future<bool> shareImage(
    Uint8List bytes, {
    required String filename,
    String? text,
  }) async {
    try {
      final Directory dir = Directory(
        p.join((await _tempDirectory()).path, 'share'),
      );
      await dir.create(recursive: true);
      final File file = File(p.join(dir.path, filename));
      await file.writeAsBytes(bytes, flush: true);
      await _channel.invokeMethod<void>('shareFile', <String, String?>{
        'path': file.path,
        'mimeType': 'image/png',
        'text': text,
      });
      return true;
    } on MissingPluginException {
      // No handler on this platform (desktop, web, tests).
      return false;
    } on PlatformException catch (e) {
      debugPrint('share failed: ${e.message}');
      return false;
    } on FileSystemException catch (e) {
      debugPrint('share failed: ${e.message}');
      return false;
    }
  }
}
