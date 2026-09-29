import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../data/models/audio_manifest.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';
import 'manifest_service.dart';

/// Every reciter the app can offer: the bundled catalog, extended by the audio
/// manifest.
///
/// The bundled catalog and the manifest are two halves of one list, and this
/// is the only place they are joined. A manifest entry whose id matches a
/// bundled reciter extends that reciter — its bundled surahs keep playing from
/// assets — and an id nobody ships becomes a reciter of its own (CLAUDE.md
/// A.5). Order is the bundled catalog's, then the manifest's, so a network
/// answer never reshuffles the list a user has been looking at.
///
/// A manifest surah is offered only when its ayah count matches `quran.db`.
/// The manifest is data from the network and the text is not: a recording cut
/// to another count would line ayah 7's audio up with ayah 8's text, so it is
/// dropped rather than played (CLAUDE.md A.2 rule 1). A dropped surah is
/// silent, not an error — the surah stays readable, and another reciter may
/// still have it.
class ReciterCatalog {
  ReciterCatalog({
    required QuranRepository quranRepository,
    required ManifestService manifestService,
  }) : _quran = quranRepository,
       _manifest = manifestService {
    // The manifest refreshes in the background, so the merge cannot be built
    // once and kept: a newer manifest has to be able to add a reciter without
    // a restart.
    _changes = _manifest.changes.listen((AudioManifest _) => _merged = null);
  }

  final QuranRepository _quran;
  final ManifestService _manifest;
  late final StreamSubscription<AudioManifest> _changes;

  List<Reciter>? _merged;

  /// The merged catalog. A `Left` here means the *bundled* data could not be
  /// read, which is a broken build; a manifest that could not be fetched is
  /// not a failure, it is simply a shorter list.
  Future<Either<Failure, List<Reciter>>> reciters() async {
    final List<Reciter>? cached = _merged;
    if (cached != null) return Right<Failure, List<Reciter>>(cached);

    // `load` answers with the manifest on disk and only guarantees that one
    // has been read; a refresh that has landed since is in `current`, which is
    // what this merge has to be built from.
    await _manifest.load();
    final AudioManifest manifest = _manifest.current;
    final Either<Failure, List<Reciter>> bundled = await _quran.getReciters();
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();

    return bundled.bind(
      (List<Reciter> catalog) => surahs.map(
        (List<Surah> text) =>
            _merged = _merge(catalog: catalog, text: text, manifest: manifest),
      ),
    );
  }

  List<Reciter> _merge({
    required List<Reciter> catalog,
    required List<Surah> text,
    required AudioManifest manifest,
  }) {
    final Map<int, int> ayahCounts = <int, int>{
      for (final Surah surah in text) surah.number: surah.ayahCount,
    };
    // The surah whose ayah 1 is the basmala, read off the catalog: what a
    // manifest reciter with no `000` files borrows theirs from.
    final int? basmalaSurah = text
        .where((Surah s) => s.bismillahMode == BismillahMode.countedAsAyah1)
        .firstOrNull
        ?.number;
    final Map<String, ManifestReciter> remote = <String, ManifestReciter>{};
    for (final ManifestReciter entry in manifest.reciters) {
      // A duplicated id keeps the first entry rather than the last, so the
      // list does not change shape with the order the CDN happens to serve.
      remote.putIfAbsent(entry.id, () => entry);
    }

    /// The portrait on the CDN, resolved against the manifest's own baseUrl.
    /// Null where the manifest names none, which leaves a bundled portrait or
    /// the initial standing.
    String? portraitOf(ManifestReciter entry) {
      final String? path = entry.imagePath;
      return path == null ? null : manifest.urlFor(path).toString();
    }

    final List<Reciter> merged = <Reciter>[];
    for (final Reciter reciter in catalog) {
      final ManifestReciter? entry = remote.remove(reciter.id);
      merged.add(
        entry == null
            ? reciter
            : reciter.withRemote(
                entry,
                surahs: _playable(entry, ayahCounts),
                imageUrl: portraitOf(entry),
                basmalaAyahSurah: basmalaSurah,
              ),
      );
    }
    for (final ManifestReciter entry in manifest.reciters) {
      if (!remote.containsKey(entry.id)) continue;
      remote.remove(entry.id);
      final Set<int> surahs = _playable(entry, ayahCounts);
      // A reciter with nothing playable is not offered at all: picking them
      // would leave every surah blocked with no way to tell why.
      if (surahs.isEmpty) continue;
      merged.add(
        Reciter.remoteOnly(
          entry,
          surahs: surahs,
          imageUrl: portraitOf(entry),
          basmalaAyahSurah: basmalaSurah,
        ),
      );
    }
    return List<Reciter>.unmodifiable(merged);
  }

  Set<int> _playable(ManifestReciter entry, Map<int, int> ayahCounts) => <int>{
    for (final ManifestSurah surah in entry.surahs)
      if (ayahCounts[surah.number] == surah.ayahs) surah.number,
  };

  Future<void> dispose() => _changes.cancel();
}
