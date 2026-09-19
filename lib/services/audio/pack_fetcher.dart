import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import '../../core/error/exceptions.dart';

/// Fetches one pack zip to a file, reporting progress.
///
/// An interface with one real implementation, for one reason: the real one is
/// a platform plugin with no implementation under `flutter test`, and the
/// verify-and-install half of a download — the half with the rules in it — has
/// to be testable without a device.
abstract class PackFetcher {
  /// Downloads [url] to [destination], replacing anything already there.
  ///
  /// [onProgress] receives 0..1, and may be called with -1 by the platform
  /// when the total size is unknown. Throws [DownloadException] on anything
  /// that is not a completed download, cancellation included.
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  });

  /// Stops the download with this id, if it is still running.
  Future<void> cancel(String taskId);
}

/// The real fetcher: `background_downloader`, so a pack keeps downloading when
/// the app goes to the background and resumes rather than restarting.
class BackgroundDownloaderPackFetcher implements PackFetcher {
  BackgroundDownloaderPackFetcher({FileDownloader? downloader})
    : _downloader = downloader ?? FileDownloader();

  final FileDownloader _downloader;

  @override
  Future<File> fetch({
    required Uri url,
    required File destination,
    required String taskId,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    // The task writes into a directory of its own choosing, so it is given
    // the destination's directory and file name rather than a path.
    final DownloadTask task = DownloadTask(
      taskId: taskId,
      url: url.toString(),
      filename: p.basename(destination.path),
      directory: p.dirname(destination.path),
      baseDirectory: BaseDirectory.root,
      updates: Updates.statusAndProgress,
      // The platform holds the task until Wi-Fi is available rather than the
      // app refusing to start it: a download queued on the train then runs by
      // itself at home.
      requiresWiFi: requiresWiFi,
      // A pack is tens of megabytes: worth resuming, and worth retrying a
      // flaky connection a few times before telling the user it failed.
      allowPause: true,
      retries: 2,
    );

    final TaskStatusUpdate result = await _downloader.download(
      task,
      onProgress: onProgress,
    );

    if (result.status != TaskStatus.complete) {
      throw DownloadException(
        url.toString(),
        'Download ended as ${result.status.name}'
        '${result.exception == null ? '' : ': ${result.exception}'}.',
      );
    }
    return destination;
  }

  @override
  Future<void> cancel(String taskId) async {
    await _downloader.cancelTaskWithId(taskId);
  }
}
