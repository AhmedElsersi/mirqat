import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/features/weak_spots/cubit/weak_spots_cubit.dart';

import '../quran_db_fixtures.dart';

/// Surah fixtures, three ayahs each.
void main() {
  late _Progress progress;

  setUp(() => progress = _Progress());

  Future<WeakSpotsCubit> open() async {
    final WeakSpotsCubit cubit = WeakSpotsCubit(
      quranRepository: fixtureRepository(),
      progressRepository: progress,
    );
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  test(
    'lists each stumbled ayah with its surah, in the order stored',
    () async {
      progress.records = <MemorizationProgress>[
        const MemorizationProgress(surahNumber: 2, ayahNumber: 3, stumbles: 2),
        const MemorizationProgress(surahNumber: 1, ayahNumber: 1, stumbles: 1),
      ];
      final WeakSpotsCubit cubit = await open();
      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.spots.map((WeakSpot s) => s.ref), <AyahRef>[
        const AyahRef(2, 3),
        const AyahRef(1, 1),
      ]);
      expect(cubit.state.spots.first.surah.number, 2);
    },
  );

  test('an ayah the catalog does not hold is not shown', () async {
    progress.records = <MemorizationProgress>[
      const MemorizationProgress(surahNumber: 1, ayahNumber: 40, stumbles: 1),
      const MemorizationProgress(surahNumber: 200, ayahNumber: 1, stumbles: 1),
      const MemorizationProgress(surahNumber: 1, ayahNumber: 2, stumbles: 1),
    ];
    final WeakSpotsCubit cubit = await open();
    expect(cubit.state.spots.single.ref, const AyahRef(1, 2));
  });

  test('clearing one takes it off the list', () async {
    progress.records = <MemorizationProgress>[
      const MemorizationProgress(surahNumber: 1, ayahNumber: 2, stumbles: 1),
    ];
    final WeakSpotsCubit cubit = await open();
    await cubit.clear(cubit.state.spots.single);
    expect(progress.cleared, <AyahRef>[const AyahRef(1, 2)]);
    expect(cubit.state.spots, isEmpty);
  });

  test(
    'storage that cannot be read says so, rather than an empty list',
    () async {
      progress.fail = true;
      final WeakSpotsCubit cubit = await open();
      expect(cubit.state.status, LoadStatus.failure);
    },
  );
}

class _Progress implements ProgressRepository {
  List<MemorizationProgress> records = <MemorizationProgress>[];
  final List<AyahRef> cleared = <AyahRef>[];
  bool fail = false;

  @override
  Future<Either<Failure, List<MemorizationProgress>>> stumbled() async => fail
      ? const Left<Failure, List<MemorizationProgress>>(
          StorageFailure('unreadable'),
        )
      : Right<Failure, List<MemorizationProgress>>(records);

  @override
  Future<Either<Failure, Unit>> clearStumble(
    int surahNumber,
    int ayahNumber,
  ) async {
    cleared.add(AyahRef(surahNumber, ayahNumber));
    records = <MemorizationProgress>[
      for (final MemorizationProgress r in records)
        if (r.surahNumber != surahNumber || r.ayahNumber != ayahNumber) r,
    ];
    return const Right<Failure, Unit>(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
