import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/quran_local_data_source.dart';
import '../models/ayah.dart';
import '../models/ayah_timing.dart';
import '../models/reciter.dart';
import '../models/surah.dart';

abstract class QuranRepository {
  Future<Either<Failure, List<Surah>>> getSurahs();

  Future<Either<Failure, Surah>> getSurah(int surahNumber);

  Future<Either<Failure, List<Ayah>>> getAyahs(int surahNumber);

  /// The ayahs of [surahNumber] between [startAyah] and [endAyah] inclusive.
  /// The range is validated against the surah's real `ayahCount`, never
  /// against a constant (CLAUDE.md A.2 rule 2).
  Future<Either<Failure, List<Ayah>>> getAyahRange(
    int surahNumber, {
    required int startAyah,
    required int endAyah,
  });

  Future<Either<Failure, List<Reciter>>> getReciters();

  Future<Either<Failure, Reciter>> getReciter(String reciterId);

  Future<Either<Failure, SurahTimings>> getTimings({
    required String reciterId,
    required int surahNumber,
  });
}

class QuranRepositoryImpl implements QuranRepository {
  const QuranRepositoryImpl(this._local);

  final QuranLocalDataSource _local;

  @override
  Future<Either<Failure, List<Surah>>> getSurahs() =>
      _guard(() => _local.getSurahs());

  @override
  Future<Either<Failure, Surah>> getSurah(int surahNumber) =>
      _guard(() => _local.getSurah(surahNumber));

  @override
  Future<Either<Failure, List<Ayah>>> getAyahs(int surahNumber) =>
      _guard(() => _local.getAyahs(surahNumber));

  @override
  Future<Either<Failure, List<Ayah>>> getAyahRange(
    int surahNumber, {
    required int startAyah,
    required int endAyah,
  }) => _guard(() async {
    final Surah surah = await _local.getSurah(surahNumber);

    if (startAyah < 1 || endAyah > surah.ayahCount) {
      throw CatalogValidationException(
        'range',
        'Ayah range $startAyah..$endAyah is outside surah $surahNumber, '
            'which has ${surah.ayahCount} ayahs.',
      );
    }
    if (startAyah > endAyah) {
      throw CatalogValidationException(
        'range',
        'Ayah range is inverted: startAyah $startAyah is after endAyah '
            '$endAyah.',
      );
    }

    final List<Ayah> all = await _local.getAyahs(surahNumber);
    return List<Ayah>.unmodifiable(all.sublist(startAyah - 1, endAyah));
  });

  @override
  Future<Either<Failure, List<Reciter>>> getReciters() =>
      _guard(() => _local.getReciters());

  @override
  Future<Either<Failure, Reciter>> getReciter(String reciterId) =>
      _guard(() => _local.getReciter(reciterId));

  @override
  Future<Either<Failure, SurahTimings>> getTimings({
    required String reciterId,
    required int surahNumber,
  }) => _guard(
    () => _local.getTimings(reciterId: reciterId, surahNumber: surahNumber),
  );

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }
}
