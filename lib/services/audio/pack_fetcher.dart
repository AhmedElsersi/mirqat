import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path/path.dart' as p;

import '../../core/error/exceptions.dart';

/// One file of an ayah-by-ayah download: where from, where to, and the id the
/// platform tracks it under.
typedef FileRequest = ({Uri url, File destination, String taskId});

/// Fetches one pack zip to a file, reporting progress — or, for a reciter
/// published without packs, every ayah file of a surah.
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

  /// Downloads every one of [requests], replacing anything already at each
  /// destination, and answers which did **not** arrive: task id to reason.
  ///
  /// A surah without a pack is up to a few hundred of these, so they go to
  /// the platform as one batch — queued, resumed and retried by it, not by a
  /// Dart loop — and [onProgress] is the fraction of files settled, success
  /// or failure. Never throws over one file: the caller decides what a
  /// missing ayah means. Cancellation shows up as failures like everything
  /// else, so a cancelled batch still returns.
  Future<Map<String, String>> fetchAll({
    required List<FileRequest> requests,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  });

  /// Stops every download in [taskIds] that is still running.
  Future<void> cancelAll(List<String> taskIds);
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
    final DownloadTask task = _task(
      url: url,
      destination: destination,
      taskId: taskId,
      requiresWiFi: requiresWiFi,
      updates: Updates.statusAndProgress,
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

  @override
  Future<Map<String, String>> fetchAll({
    required List<FileRequest> requests,
    bool requiresWiFi = false,
    void Function(double progress)? onProgress,
  }) async {
    if (requests.isEmpty) return const <String, String>{};
    final List<DownloadTask> tasks = <DownloadTask>[
      for (final FileRequest request in requests)
        _task(
          url: request.url,
          destination: request.destination,
          taskId: request.taskId,
          requiresWiFi: requiresWiFi,
          // A batch is followed by files settled, not by bytes: a per-file
          // percentage across three hundred small files is noise.
          updates: Updates.status,
        ),
    ];

    final Batch batch = await _downloader.downloadBatch(
      tasks,
      batchProgressCallback: (int succeeded, int failed) =>
          onProgress?.call((succeeded + failed) / tasks.length),
    );

    // Judged by what succeeded, not by what reported: a task the platform
    // lost without a status is a file that did not arrive.
    final Set<String> arrived = <String>{
      for (final Task task in batch.succeeded) task.taskId,
    };
    final Map<String, TaskStatus> outcomes = <String, TaskStatus>{
      for (final MapEntry<Task, TaskStatus> entry in batch.results.entries)
        entry.key.taskId: entry.value,
    };
    return <String, String>{
      for (final FileRequest request in requests)
        if (!arrived.contains(request.taskId))
          request.taskId: outcomes[request.taskId]?.name ?? 'no result',
    };
  }

  @override
  Future<void> cancelAll(List<String> taskIds) async {
    if (taskIds.isEmpty) return;
    await _downloader.cancelTasksWithIds(taskIds);
  }

  /// The task writes into a directory of its own choosing, so it is given the
  /// destination's directory and file name rather than a path.
  static DownloadTask _task({
    required Uri url,
    required File destination,
    required String taskId,
    required bool requiresWiFi,
    required Updates updates,
  }) => DownloadTask(
    taskId: taskId,
    url: url.toString(),
    filename: p.basename(destination.path),
    directory: p.dirname(destination.path),
    baseDirectory: BaseDirectory.root,
    updates: updates,
    // The platform holds the task until Wi-Fi is available rather than the
    // app refusing to start it: a download queued on the train then runs by
    // itself at home.
    requiresWiFi: requiresWiFi,
    // A pack is tens of megabytes: worth resuming, and worth retrying a
    // flaky connection a few times before telling the user it failed. An
    // ayah file is small, but the same flaky connection drops it just as
    // readily.
    allowPause: true,
    retries: 2,
  );
}
