import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/datasources/quran_local_data_source.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';

import '../app_harness.dart' show FileAssetReader;
import '../quran_db_fixtures.dart';

/// The recitation weight a hifz plan is cut by, read from the shipped
/// quran.db's derived search column.
void main() {
  late QuranLocalDataSource source;
  setUp(
    () => source = QuranLocalDataSourceImpl(
      const FileAssetReader(),
      RepoQuranDatabase(),
    ),
  );

  test('every ayah of the range, in order, each with a weight', () async {
    final List<({AyahRef ref, int weight})> w = await source.ayahWeights(
      const AyahRef(1, 1),
      const AyahRef(1, 7),
    );
    expect(w.map((x) => x.ref.ayah), <int>[1, 2, 3, 4, 5, 6, 7]);
    expect(w.every((x) => x.weight > 5), isTrue);
    // Al-Fatiha's last ayah is its longest, by far.
    expect(
      w.last.weight,
      greaterThan(
        w.take(6).map((x) => x.weight).reduce((a, b) => a > b ? a : b),
      ),
    );
  });

  test('a range across surahs runs on through them', () async {
    final List<({AyahRef ref, int weight})> w = await source.ayahWeights(
      const AyahRef(112, 4),
      const AyahRef(114, 1),
    );
    expect(w.first.ref, const AyahRef(112, 4));
    expect(w.last.ref, const AyahRef(114, 1));
    expect(w, hasLength(1 + 5 + 1));
  });

  test('an end the text does not have gives nothing, not an error', () async {
    expect(
      await source.ayahWeights(const AyahRef(1, 1), const AyahRef(1, 99)),
      isEmpty,
    );
  });
}
