import 'package:dartz/dartz.dart';

import '../../core/error/exceptions.dart';
import '../../core/error/failures.dart';
import '../datasources/quran_pages_local_data_source.dart';
import '../models/juz_info.dart';
import '../models/page_info.dart';
import '../models/ayah.dart';
import '../models/mushaf_line.dart';
import '../models/word.dart';

/// Page/line/word access over `quran.db`.
abstract class QuranPagesRepository {
  Future<Either<Failure, List<Ayah>>> ayahsForPage(int page);

  Future<Either<Failure, PageInfo?>> pageInfo(int page, {int? fromWordId});

  Future<Either<Failure, List<JuzInfo>>> juzList();

  Future<Either<Failure, List<MushafLine>>> linesForPage(int page);

  Future<Either<Failure, List<Word>>> wordsForLine(int page, int line);

  Future<Either<Failure, List<Word>>> wordsInRange(int firstId, int lastId);

  Future<Either<Failure, List<Word>>> wordsForAyah(
    int surahNumber,
    int ayahNumber,
  );

  Future<Either<Failure, int>> pageCount();

  Future<Either<Failure, int>> linesPerFullPage();

  Future<Either<Failure, int>> pageForAyah(int surahNumber, int ayahNumber);

  Future<Either<Failure, int?>> surahHeadingPage(int surahNumber);

  Future<Either<Failure, int>> ayahCount(int surahNumber);
}

class QuranPagesRepositoryImpl implements QuranPagesRepository {
  const QuranPagesRepositoryImpl(this._local);

  final QuranPagesLocalDataSource _local;

  @override
  Future<Either<Failure, List<Ayah>>> ayahsForPage(int page) =>
      _guard(() => _local.ayahsForPage(page));

  @override
  Future<Either<Failure, PageInfo?>> pageInfo(int page, {int? fromWordId}) =>
      _guard(() => _local.pageInfo(page, fromWordId: fromWordId));

  @override
  Future<Either<Failure, List<JuzInfo>>> juzList() => _guard(_local.juzList);

  @override
  Future<Either<Failure, List<MushafLine>>> linesForPage(int page) =>
      _guard(() => _local.linesForPage(page));

  @override
  Future<Either<Failure, List<Word>>> wordsForLine(int page, int line) =>
      _guard(() => _local.wordsForLine(page, line));

  @override
  Future<Either<Failure, List<Word>>> wordsInRange(int firstId, int lastId) =>
      _guard(() => _local.wordsInRange(firstId, lastId));

  @override
  Future<Either<Failure, List<Word>>> wordsForAyah(
    int surahNumber,
    int ayahNumber,
  ) => _guard(() => _local.wordsForAyah(surahNumber, ayahNumber));

  @override
  Future<Either<Failure, int>> pageCount() => _guard(_local.pageCount);

  @override
  Future<Either<Failure, int>> linesPerFullPage() =>
      _guard(_local.linesPerFullPage);

  @override
  Future<Either<Failure, int>> pageForAyah(int surahNumber, int ayahNumber) =>
      _guard(() => _local.pageForAyah(surahNumber, ayahNumber));

  @override
  Future<Either<Failure, int?>> surahHeadingPage(int surahNumber) =>
      _guard(() => _local.surahHeadingPage(surahNumber));

  @override
  Future<Either<Failure, int>> ayahCount(int surahNumber) =>
      _guard(() => _local.ayahCount(surahNumber));

  Future<Either<Failure, T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Right<Failure, T>(await body());
    } on AppException catch (e) {
      return Left<Failure, T>(failureFromException(e));
    }
  }
}
