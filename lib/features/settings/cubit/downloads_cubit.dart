import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/audio_pack.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../services/audio/audio_pack_service.dart';
import '../../../services/audio/reciter_catalog.dart';
import 'downloads_state.dart';

/// The saved-recitations list: what is on the device, and the one action that
/// changes it.
///
/// Nothing here can break playback. Freeing a surah returns it to streaming,
/// and it stays readable either way, so this screen is only ever about disk
/// space.
class DownloadsCubit extends Cubit<DownloadsState> {
  DownloadsCubit({
    required AudioPackService packService,
    required QuranRepository quranRepository,
    required ReciterCatalog reciterCatalog,
  }) : _packs = packService,
       _quran = quranRepository,
       _reciters = reciterCatalog,
       super(const DownloadsState());

  final AudioPackService _packs;
  final QuranRepository _quran;
  final ReciterCatalog _reciters;

  StreamSubscription<void>? _installs;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));
    // Checked on the way in rather than on a timer: a reciter who re-cuts a
    // surah publishes a new `version`, and the rows fetched at the old one are
    // marked stale here so this screen can offer the re-download.
    await _packs.reconcile();
    await _read();
    // A download started from a reader drawer while this screen is open
    // belongs in the list without a pull-to-refresh.
    _installs ??= _packs.installChanges.listen((_) => _read());
  }

  /// Frees one saved surah.
  Future<void> delete(SavedRecitation saved) async {
    final InstalledPack pack = saved.pack;
    final result = await _packs.delete(
      reciterId: pack.reciterId,
      surahNumber: pack.surahNumber,
      bitrate: pack.bitrate,
    );
    if (isClosed) return;
    result.fold(
      (Failure f) => emit(state.copyWith(errorMessage: f.message)),
      // The install stream fires on a successful forget, so the list reloads
      // through the same path as any other change.
      (_) {},
    );
  }

  /// Frees every surah saved for one reciter.
  Future<void> deleteReciter(String reciterId) async {
    emit(state.copyWith(busy: true));
    final result = await _packs.deleteReciter(reciterId);
    if (isClosed) return;
    emit(
      state.copyWith(
        busy: false,
        errorMessage: result.fold((Failure f) => f.message, (_) => null),
      ),
    );
    await _read();
  }

  /// Re-fetches this reciter's stale surahs, and only theirs.
  ///
  /// Only the stale ones: a reciter with forty surahs on the device and two
  /// superseded takes should cost two downloads, not forty.
  Future<void> redownloadStale(String reciterId) => _downloadEach(
    state.saved
        .where(
          (SavedRecitation s) =>
              s.pack.reciterId == reciterId && s.pack.isStale,
        )
        .toList(),
  );

  /// Re-attempts every failed download.
  ///
  /// Through the service rather than this cubit's own loop: "which downloads
  /// failed" is the service's record, and asking it twice invites the two
  /// answers to drift.
  Future<void> retryFailed() async {
    if (state.failed.isEmpty) return;
    emit(state.copyWith(busy: true));

    final List<Reciter> reciters = (await _reciters.reciters()).getOrElse(
      () => const <Reciter>[],
    );
    final result = await _packs.retryFailed(reciters: reciters);
    if (isClosed) return;

    emit(
      state.copyWith(
        busy: false,
        errorMessage: result.fold((Failure f) => f.message, (_) => null),
      ),
    );
    await _read();
  }

  /// Downloads [items] one after another.
  ///
  /// Sequential on purpose: packs are tens of megabytes each, and three at
  /// once on a phone's connection is slower than three in a row as well as
  /// harder to read.
  Future<void> _downloadEach(List<SavedRecitation> items) async {
    if (items.isEmpty) return;
    emit(state.copyWith(busy: true));

    final List<Reciter> reciters = (await _reciters.reciters()).getOrElse(
      () => const <Reciter>[],
    );
    String? failure;
    for (final SavedRecitation item in items) {
      final Reciter? reciter = reciters
          .where((Reciter r) => r.id == item.pack.reciterId)
          .firstOrNull;
      // A reciter the catalog no longer lists cannot be re-fetched; the row
      // stays so it can still be cleared.
      if (reciter == null) continue;
      final result = await _packs.download(
        reciter: reciter,
        surahNumber: item.pack.surahNumber,
      );
      if (isClosed) return;
      failure ??= result.fold((Failure f) => f.message, (_) => null);
    }

    emit(state.copyWith(busy: false, errorMessage: failure));
    await _read();
  }

  Future<void> _read() async {
    final installedResult = await _packs.installed();
    if (isClosed) return;

    final List<InstalledPack>? packs = installedResult.fold((Failure f) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: f.message));
      return null;
    }, (List<InstalledPack> p) => p);
    if (packs == null) return;

    final List<InstalledPack> failures = (await _packs.failed()).getOrElse(
      () => const <InstalledPack>[],
    );
    if (isClosed) return;

    // Names are decoration here: a pack whose reciter or surah cannot be
    // resolved is still listed, still sized, and still deletable.
    final List<Surah> surahs = (await _quran.getSurahs()).getOrElse(
      () => const <Surah>[],
    );
    final List<Reciter> reciters = (await _reciters.reciters()).getOrElse(
      () => const <Reciter>[],
    );
    if (isClosed) return;

    SavedRecitation describe(InstalledPack pack) => SavedRecitation(
      pack: pack,
      surah: surahs
          .where((Surah s) => s.number == pack.surahNumber)
          .firstOrNull,
      reciter: reciters
          .where((Reciter r) => r.id == pack.reciterId)
          .firstOrNull,
    );

    emit(
      DownloadsState(
        status: LoadStatus.ready,
        saved: List<SavedRecitation>.unmodifiable(packs.map(describe)),
        failed: List<SavedRecitation>.unmodifiable(failures.map(describe)),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _installs?.cancel();
    return super.close();
  }
}
