import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/core/state/load_status.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/features/reader/cubit/reader_cubit.dart';
import 'package:mirqat/features/reader/cubit/reader_state.dart';
import 'package:mirqat/services/audio/audio_availability.dart';
import 'package:mirqat/services/audio/reciter_catalog.dart';
import 'package:mirqat/services/audio/ayah_duration_service.dart';

import '../quran_db_fixtures.dart';

/// Surah fixtures: 1 is recorded by reciters a and b, 2 only by b, 3 by
/// nobody.
void main() {
  late QuranRepository quran;
  late _Settings settings;

  setUp(() => quran = fixtureRepository());

  Future<ReaderCubit> open(
    int surahNumber, {
    String? reciterId,
    bool measurable = true,
  }) async {
    settings = _Settings(AppSettings(reciterId: reciterId));
    final ReciterCatalog catalog = ReciterCatalog(
      quranRepository: quran,
      manifestService: fixtureManifestService(),
    );
    addTearDown(catalog.dispose);
    final ReaderCubit cubit = ReaderCubit(
      quranRepository: quran,
      settingsRepository: settings,
      reciterCatalog: catalog,
      audioAvailability: AudioAvailability(reciterCatalog: catalog),
      durationService: _Durations(measurable: measurable),
      planBuilder: const RepetitionPlanBuilder(),
    );
    addTearDown(cubit.close);
    await cubit.load(surahNumber);
    return cubit;
  }

  group('a surah nobody has recorded', () {
    test('loads for reading, with the session blocked up front', () async {
      final ReaderState state = (await open(3, reciterId: 'a')).state;

      expect(state.status, LoadStatus.ready);
      expect(state.ayahs, hasLength(3), reason: 'reading never needs audio');
      expect(state.sessionBlock, SessionBlock.noAudio);
      expect(state.reciter, isNull);
      expect(state.availableReciters, isEmpty);
      expect(state.canStart, isFalse);
      expect(state.estimatedDuration, isNull);
    });
  });

  group('a surah whose clips are not on the device', () {
    test('reads and starts, with no duration rather than an error', () async {
      // Streamed audio is not measured up front, so the summary has no
      // duration to show — but the session is still ready to start.
      final ReaderState state = (await open(
        1,
        reciterId: 'a',
        measurable: false,
      )).state;

      expect(state.status, LoadStatus.ready);
      expect(state.sessionBlock, isNull);
      expect(state.reciter?.id, 'a');
      expect(state.canStart, isTrue);
      expect(state.plan, isNotNull);
      expect(state.estimatedDuration, isNull);
    });
  });

  group('the chosen reciter lacks the surah but another has it', () {
    test('blocks and offers the reciters that have it', () async {
      final ReaderState state = (await open(2, reciterId: 'a')).state;

      expect(state.status, LoadStatus.ready);
      expect(state.sessionBlock, SessionBlock.reciterLacksSurah);
      expect(state.chosenReciter?.id, 'a');
      expect(state.availableReciters.map((Reciter r) => r.id), <String>['b']);
      expect(state.reciter, isNull);
      expect(state.canStart, isFalse);
    });

    test('switching unblocks this screen without changing the saved '
        'reciter', () async {
      final ReaderCubit cubit = await open(2, reciterId: 'a');
      final ReaderState blocked = cubit.state;

      await cubit.switchReciter(blocked.availableReciters.single);

      expect(cubit.state.sessionBlock, isNull);
      expect(cubit.state.reciter?.id, 'b');
      expect(cubit.state.canStart, isTrue);
      expect(cubit.state.estimatedDuration, isNotNull);
      expect(settings.saved, isEmpty, reason: 'the choice in settings stands');
    });

    test('refuses a switch to a reciter who lacks the surah too', () async {
      final ReaderCubit cubit = await open(2, reciterId: 'a');
      final ReaderState blocked = cubit.state;

      await cubit.switchReciter(blocked.chosenReciter!);

      expect(cubit.state.sessionBlock, SessionBlock.reciterLacksSurah);
      expect(cubit.state.canStart, isFalse);
    });
  });

  group('nothing blocks', () {
    test('the chosen reciter is used when it has the surah', () async {
      final ReaderState state = (await open(1, reciterId: 'a')).state;

      expect(state.sessionBlock, isNull);
      expect(state.reciter?.id, 'a');
      expect(state.canStart, isTrue);
    });

    test('with no choice made, the first reciter that has it', () async {
      final ReaderState state = (await open(2)).state;

      expect(state.sessionBlock, isNull);
      expect(state.reciter?.id, 'b');
    });

    test('a choice no longer in the catalog counts as no choice', () async {
      final ReaderState state = (await open(2, reciterId: 'retired')).state;

      expect(state.sessionBlock, isNull);
      expect(state.reciter?.id, 'b');
    });
  });
}

class _Settings implements SettingsRepository {
  _Settings(this._current);

  final AppSettings _current;
  final List<AppSettings> saved = <AppSettings>[];

  @override
  Future<Either<Failure, AppSettings>> read() async =>
      Right<Failure, AppSettings>(_current);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings settings) async {
    saved.add(settings);
    return Right<Failure, AppSettings>(settings);
  }
}

/// One second per ayah — the reader only needs a measurement to exist.
class _Durations implements AyahDurationService {
  _Durations({this.measurable = true});

  /// False stands in for a surah whose clips are not on the device: the real
  /// service leaves those unmeasured rather than streaming them to time them.
  final bool measurable;

  @override
  AudioPlayer? probe;

  @override
  Future<Map<int, Duration>> durationsFor({
    required Reciter reciter,
    required Surah surah,
  }) async => measurable
      ? <int, Duration>{
          for (int a = 1; a <= surah.ayahCount; a++)
            a: const Duration(seconds: 1),
        }
      : const <int, Duration>{};

  @override
  Future<void> dispose() async {}
}
