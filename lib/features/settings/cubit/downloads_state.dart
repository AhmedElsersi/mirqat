import 'package:equatable/equatable.dart';

import '../../../core/state/load_status.dart';
import '../../../data/models/audio_pack.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';

/// One saved surah, with the names needed to show it.
///
/// [surah] and [reciter] can both be null: a pack installed by a build that
/// knew a reciter the manifest has since dropped is still on disk and still
/// worth listing, because the whole point of this screen is freeing space.
class SavedRecitation extends Equatable {
  const SavedRecitation({required this.pack, this.surah, this.reciter});

  final InstalledPack pack;
  final Surah? surah;
  final Reciter? reciter;

  @override
  List<Object?> get props => <Object?>[pack, surah, reciter];
}

class DownloadsState extends Equatable {
  const DownloadsState({
    this.status = LoadStatus.initial,
    this.saved = const <SavedRecitation>[],
    this.failed = const <SavedRecitation>[],
    this.busy = false,
    this.errorMessage,
  });

  final LoadStatus status;
  final List<SavedRecitation> saved;

  /// Downloads that were asked for and did not arrive, kept so they can be
  /// retried without hunting through 114 surahs to find them.
  final List<SavedRecitation> failed;

  /// A retry or a bulk delete is running; the actions stand down while it is.
  final bool busy;
  final String? errorMessage;

  /// What every saved surah costs together, in bytes.
  int get totalBytes =>
      saved.fold<int>(0, (int sum, SavedRecitation s) => sum + s.pack.bytes);

  /// Saved surahs grouped by reciter, in list order.
  Map<String, List<SavedRecitation>> get byReciter {
    final Map<String, List<SavedRecitation>> grouped =
        <String, List<SavedRecitation>>{};
    for (final SavedRecitation item in saved) {
      grouped
          .putIfAbsent(item.pack.reciterId, () => <SavedRecitation>[])
          .add(item);
    }
    return grouped;
  }

  /// Whether any saved surah is a reading the manifest has since replaced.
  bool get hasStale => saved.any((SavedRecitation s) => s.pack.isStale);

  DownloadsState copyWith({
    LoadStatus? status,
    List<SavedRecitation>? saved,
    List<SavedRecitation>? failed,
    bool? busy,
    String? errorMessage,
  }) => DownloadsState(
    status: status ?? this.status,
    saved: saved ?? this.saved,
    failed: failed ?? this.failed,
    busy: busy ?? this.busy,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    saved,
    failed,
    busy,
    errorMessage,
  ];
}
