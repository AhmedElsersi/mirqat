import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import 'reciter_catalog.dart';

/// Which reciters have audio for a surah.
///
/// A lookup beside the surah list, never a filter on it: every surah is
/// readable whether or not anyone has recorded it, and the catalog knows
/// nothing about audio.
class AudioAvailability {
  const AudioAvailability({required ReciterCatalog reciterCatalog})
    : _reciters = reciterCatalog;

  final ReciterCatalog _reciters;

  /// The reciters who have [surah] — bundled or from the manifest — in catalog
  /// order. Empty when nobody has it.
  Future<Either<Failure, List<Reciter>>> recitersFor(Surah surah) async =>
      (await _reciters.reciters()).map(
        (List<Reciter> reciters) => List<Reciter>.unmodifiable(
          reciters.where((Reciter r) => r.hasSurah(surah.number)),
        ),
      );
}
