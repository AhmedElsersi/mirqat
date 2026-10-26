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
import 'mushaf_download_state.dart';

/// The whole-mushaf download: one reciter, every surah they have.
///
/// A convenience over the per-surah download and nothing more — the same
/// service, the same verification, the same rows — so nothing here can break
/// playback or reading. The run lives in `AudioPackService`, not in this
/// cubit, so leaving the screen does not stop it; coming back finds it where
/// it was.
class MushafDownloadCubit extends Cubit<MushafDownloadState> {
  MushafDownloadCubit({
    required AudioPackService packService,
    required ReciterCatalog reciterCatalog,
    QuranRepository? quranRepository,
  }) : _packs = packService,
       _reciters = reciterCatalog,
       _quran = quranRepository,
       super(const MushafDownloadState());

  final AudioPackService _packs;
  final ReciterCatalog _reciters;

  /// Where the surah being fetched gets its name. Optional: without it the
  /// running card names the surah by its number.
  final QuranRepository? _quran;

  StreamSubscription<BulkDownload>? _runs;
  StreamSubscription<PackDownload>? _downloads;
  StreamSubscription<void>? _installs;

  Future<void> load() async {
    emit(state.copyWith(status: LoadStatus.loading));
    // As on the saved-recitations screen: a reciter who has re-cut a surah
    // publishes a new `version`, and the rows fetched at the old one are
    // marked stale here — which is what puts those surahs back into what a
    // whole-mushaf run would fetch.
    await _packs.reconcile();
    await _read();

    _runs ??= _packs.runChanges.listen(_onRun);
    _downloads ??= _packs.changes.listen(_onDownload);
    // A surah freed from the saved-recitations screen, or downloaded from a
    // reader, changes what is left here.
    _installs ??= _packs.installChanges.listen((_) {
      if (!state.anyRunning) _read();
    });
  }

  /// Downloads every surah this reciter offers that is not already here.
  ///
  /// The result is not read: every step of the run arrives on the run stream,
  /// failures included, and that is what this screen renders.
  Future<void> downloadWhole(Reciter reciter) async {
    if (state.anyRunning) return;
    await _packs.downloadWhole(reciter: reciter);
    if (isClosed) return;
    await _read();
  }

  Future<void> cancel(Reciter reciter) => _packs.cancelWhole(reciter.id);

  void _onRun(BulkDownload run) {
    if (isClosed) return;
    emit(
      state.copyWith(
        reciters: <ReciterOffline>[
          for (final ReciterOffline entry in state.reciters)
            if (entry.reciter.id == run.reciterId)
              entry.copyWith(run: run, clearCurrent: !run.isRunning)
            else
              entry,
        ],
      ),
    );
  }

  /// A single surah's progress, kept only for the reciter whose run is going.
  ///
  /// Otherwise a download started from a reader would redraw rows this screen
  /// is not showing progress for.
  void _onDownload(PackDownload download) {
    if (isClosed) return;
    final ReciterOffline? entry = state.reciters
        .where((ReciterOffline r) => r.reciter.id == download.reciterId)
        .firstOrNull;
    if (entry == null || !entry.isRunning) return;
    emit(
      state.copyWith(
        reciters: <ReciterOffline>[
          for (final ReciterOffline r in state.reciters)
            if (r.reciter.id == download.reciterId)
              r.copyWith(current: download)
            else
              r,
        ],
      ),
    );
  }

  Future<void> _read() async {
    final result = await _reciters.reciters();
    if (isClosed) return;

    final List<Reciter>? all = result.fold((Failure f) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: f.message));
      return null;
    }, (List<Reciter> r) => r);
    if (all == null) return;

    final List<ReciterOffline> rows = <ReciterOffline>[];
    for (final Reciter reciter in all) {
      // A reciter with nothing to fetch — no manifest entry at all — has no
      // row here: there is no action to offer, and a row with a disabled
      // button says less than no row.
      if (reciter.remoteSurahs.isEmpty) continue;
      final PendingDownloads plan = (await _packs.pending(
        reciter,
      )).getOrElse(() => PendingDownloads.none(reciter.id));
      if (isClosed) return;
      rows.add(
        ReciterOffline(
          reciter: reciter,
          pending: plan,
          run: _packs.runFor(reciter.id),
        ),
      );
    }

    Map<int, String> names = state.surahNames;
    if (names.isEmpty && _quran != null) {
      names = (await _quran.getSurahs()).fold(
        (_) => const <int, String>{},
        (List<Surah> surahs) => <int, String>{
          for (final Surah s in surahs) s.number: s.nameAr,
        },
      );
      if (isClosed) return;
    }

    emit(
      MushafDownloadState(
        status: LoadStatus.ready,
        reciters: List<ReciterOffline>.unmodifiable(rows),
        surahNames: names,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _runs?.cancel();
    await _downloads?.cancel();
    await _installs?.cancel();
    return super.close();
  }
}
