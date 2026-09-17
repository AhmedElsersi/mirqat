import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';

/// Which reciters have audio for a surah.
///
/// A lookup beside the surah list, never a filter on it: every surah is
/// readable whether or not anyone has recorded it, and the catalog knows
/// nothing about audio.
class AudioAvailability {
  const AudioAvailability({required QuranRepository quranRepository})
    : _quran = quranRepository;

  final QuranRepository _quran;

  /// The reciters whose `availableSurahs` include [surah], in catalog order.
  /// Empty when nobody has it.
  Future<Either<Failure, List<Reciter>>> recitersFor(Surah surah) async =>
      (await _quran.getReciters()).map(
        (List<Reciter> reciters) => List<Reciter>.unmodifiable(
          reciters.where((Reciter r) => r.hasSurah(surah.number)),
        ),
      );
}
