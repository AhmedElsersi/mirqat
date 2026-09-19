import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/audio_pack.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../services/audio/audio_pack_service.dart';

/// One surah's offline-audio state for one reciter.
class AudioPackState {
  const AudioPackState({
    required this.download,
    this.installed,
    this.isBundled = false,
    this.canDownload = false,
  });

  /// Nothing known yet — the shape before [AudioPackCubit.watch] has read.
  const AudioPackState.unknown()
    : download = const PackDownload.idle(reciterId: '', surahNumber: 0),
      installed = null,
      isBundled = false,
      canDownload = false;

  final PackDownload download;

  /// The recorded install, when there is one.
  final InstalledPack? installed;

  /// The surah's audio ships inside the app, so there is nothing to download
  /// and nothing to free.
  final bool isBundled;

  /// The manifest offers this surah, so a pack exists to fetch.
  final bool canDownload;

  bool get isInstalled => installed != null;

  AudioPackState copyWith({
    PackDownload? download,
    InstalledPack? installed,
    bool clearInstalled = false,
    bool? isBundled,
    bool? canDownload,
  }) => AudioPackState(
    download: download ?? this.download,
    installed: clearInstalled ? null : (installed ?? this.installed),
    isBundled: isBundled ?? this.isBundled,
    canDownload: canDownload ?? this.canDownload,
  );
}

/// Drives the offline-audio control for the surah on screen.
///
/// Deliberately small and per-control rather than folded into `ReaderCubit`:
/// a download outlives the screen that started it, and the reader has no
/// business re-emitting its whole state every time a progress tick arrives.
class AudioPackCubit extends Cubit<AudioPackState> {
  AudioPackCubit({required AudioPackService packService})
    : _packs = packService,
      super(const AudioPackState.unknown());

  final AudioPackService _packs;

  StreamSubscription<PackDownload>? _progress;
  StreamSubscription<void>? _installs;
  Reciter? _reciter;
  Surah? _surah;

  /// Reads the state of [surah] for [reciter] and follows it from then on.
  Future<void> watch({required Reciter reciter, required Surah surah}) async {
    _reciter = reciter;
    _surah = surah;

    await _progress?.cancel();
    await _installs?.cancel();

    emit(
      AudioPackState(
        download: _packs.stateFor(
          reciterId: reciter.id,
          surahNumber: surah.number,
        ),
        isBundled: reciter.isBundledSurah(surah.number),
        canDownload:
            reciter.remote != null &&
            reciter.remoteSurahs.contains(surah.number),
      ),
    );
    await _readInstalled();

    _progress = _packs.changes
        .where(
          (PackDownload d) =>
              d.reciterId == reciter.id && d.surahNumber == surah.number,
        )
        .listen((PackDownload d) {
          if (!isClosed) emit(state.copyWith(download: d));
        });
    _installs = _packs.installChanges.listen((_) => _readInstalled());
  }

  Future<void> download() async {
    final Reciter? reciter = _reciter;
    final Surah? surah = _surah;
    if (reciter == null || surah == null) return;
    // The result is not read here: every step of it arrives on the progress
    // stream, failure included, and that is what this control renders.
    await _packs.download(reciter: reciter, surahNumber: surah.number);
    // The install record is read back directly rather than waited for on
    // `installChanges`: this control started the download, so it should not
    // learn the outcome by overhearing a broadcast it may reach a frame later.
    await _readInstalled();
  }

  Future<void> cancel() async {
    final Reciter? reciter = _reciter;
    final Surah? surah = _surah;
    if (reciter == null || surah == null) return;
    await _packs.cancel(reciterId: reciter.id, surahNumber: surah.number);
  }

  Future<void> delete() async {
    final InstalledPack? pack = state.installed;
    if (pack == null) return;
    await _packs.delete(
      reciterId: pack.reciterId,
      surahNumber: pack.surahNumber,
      bitrate: pack.bitrate,
    );
    if (!isClosed) {
      emit(
        state.copyWith(
          clearInstalled: true,
          download: PackDownload.idle(
            reciterId: pack.reciterId,
            surahNumber: pack.surahNumber,
          ),
        ),
      );
    }
  }

  Future<void> _readInstalled() async {
    final Reciter? reciter = _reciter;
    final Surah? surah = _surah;
    if (reciter == null || surah == null) return;

    final result = await _packs.installed();
    if (isClosed) return;
    final InstalledPack? pack = result
        .getOrElse(() => const <InstalledPack>[])
        .where(
          (InstalledPack p) =>
              p.reciterId == reciter.id && p.surahNumber == surah.number,
        )
        .firstOrNull;
    emit(
      pack == null
          ? state.copyWith(clearInstalled: true)
          : state.copyWith(installed: pack),
    );
  }

  @override
  Future<void> close() async {
    await _progress?.cancel();
    await _installs?.cancel();
    return super.close();
  }
}
