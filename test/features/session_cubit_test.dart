import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/session/cubit/session_state.dart';
import 'package:mirqat/services/audio/ayah_duration_service.dart';
import 'package:mirqat/services/audio/reciter_catalog.dart';
import 'package:mirqat/services/keep_awake_service.dart';

import '../fake_session_player.dart';
import '../quran_db_fixtures.dart';

/// Surah fixtures, three ayahs each: 1 is recorded by reciters a and b, 2 only
/// by b, 3 by nobody.
void main() {
  late QuranRepository quran;
  late _Settings settings;
  late FakeSessionPlayer player;
  late _Progress progress;

  setUp(() {
    quran = fixtureRepository();
    player = FakeSessionPlayer();
    progress = _Progress();
  });

  Future<SessionCubit> open({
    String? reciterId,
    bool measurable = true,
    AppSettings? stored,
  }) async {
    settings = _Settings(stored ?? AppSettings(reciterId: reciterId));
    final ReciterCatalog catalog = ReciterCatalog(
      quranRepository: quran,
      manifestService: fixtureManifestService(),
    );
    addTearDown(catalog.dispose);
    final SessionCubit cubit = SessionCubit(
      quranRepository: quran,
      settingsRepository: settings,
      reciterCatalog: catalog,
      durationService: _Durations(measurable: measurable),
      planBuilder: const RepetitionPlanBuilder(),
      playerService: player,
      progressRepository: progress,
      keepAwakeService: const KeepAwakeService(),
      pauseSettleTime: Duration.zero,
    );
    addTearDown(cubit.close);
    await cubit.load();
    return cubit;
  }

  const AyahRef s1a1 = AyahRef(1, 1);
  const AyahRef s1a3 = AyahRef(1, 3);
  const AyahRef s2a1 = AyahRef(2, 1);
  const AyahRef s2a3 = AyahRef(2, 3);

  /// Lets queued microtasks and zero-length timers run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  group('who can recite the range', () {
    test(
      'a surah nobody has recorded blocks the session, not the reading',
      () async {
        final SessionCubit cubit = await open(reciterId: 'a');
        cubit.suggestRange(const AyahRef(3, 1), const AyahRef(3, 3));

        expect(cubit.state.block, SessionBlock.noAudio);
        expect(cubit.state.reciter, isNull);
        expect(cubit.state.canStart, isFalse);
        expect(cubit.state.plan, isNotNull, reason: 'the plan needs no audio');
        expect(
          settings.saved,
          isEmpty,
          reason: 'the choice in settings stands',
        );
      },
    );

    test('the chosen reciter lacking it offers those who have it', () async {
      final SessionCubit cubit = await open(reciterId: 'a');
      cubit.suggestRange(s2a1, s2a3);

      expect(cubit.state.block, SessionBlock.reciterLacksSurah);
      expect(cubit.state.availableReciters.map((Reciter r) => r.id), <String>[
        'b',
      ]);

      cubit.setReciter(cubit.state.availableReciters.single);
      expect(cubit.state.block, isNull);
      expect(cubit.state.canStart, isTrue);
      expect(settings.saved, isEmpty, reason: 'for this reading only');
    });

    test('the chosen reciter is used when it has the range', () async {
      final SessionCubit cubit = await open(reciterId: 'a');
      cubit.suggestRange(s1a1, s1a3);
      expect(cubit.state.block, isNull);
      expect(cubit.state.reciter?.id, 'a');
    });

    test('with no choice made, the first reciter that has it', () async {
      final SessionCubit cubit = await open();
      cubit.suggestRange(s2a1, s2a3);
      expect(cubit.state.reciter?.id, 'b');
    });

    test('a choice no longer in the catalog counts as no choice', () async {
      final SessionCubit cubit = await open(reciterId: 'retired');
      cubit.suggestRange(s2a1, s2a3);
      expect(cubit.state.block, isNull);
      expect(cubit.state.reciter?.id, 'b');
    });

    test('a range into the next surah needs a reciter who has both', () async {
      final SessionCubit cubit = await open(reciterId: 'a');
      cubit.chooseRange(s1a3, s2a1);

      // a has surah 1 only; b has both.
      expect(cubit.state.block, SessionBlock.reciterLacksSurah);
      expect(cubit.state.availableReciters.single.id, 'b');
    });
  });

  group('the range', () {
    test('follows the page until the reader chooses one', () async {
      final SessionCubit cubit = await open();
      cubit.suggestRange(s1a1, s1a3);
      expect(cubit.state.rangeChosen, isFalse);
      expect(
        cubit.state.markedRange,
        isNull,
        reason: 'a suggestion is not tinted',
      );

      cubit.suggestRange(s2a1, s2a3);
      expect(cubit.state.config!.start, s2a1);

      cubit.chooseRange(const AyahRef(2, 2), s2a3);
      cubit.suggestRange(s1a1, s1a3);
      expect(
        cubit.state.config!.start,
        const AyahRef(2, 2),
        reason: 'a choice stays put',
      );
      expect(cubit.state.markedRange, (from: const AyahRef(2, 2), to: s2a3));

      cubit.clearRange();
      cubit.suggestRange(s1a1, s1a3);
      expect(cubit.state.config!.start, s1a1);
    });

    test(
      'its two ends never cross: moving one past the other takes it along',
      () async {
        final SessionCubit cubit = await open();
        cubit.chooseRange(const AyahRef(1, 2), s1a3);

        cubit.setStart(s2a1);
        expect(cubit.state.config!.start, s2a1);
        expect(cubit.state.config!.end, s2a1);

        cubit.setEnd(s1a1);
        expect(cubit.state.config!.start, s1a1);
        expect(cubit.state.config!.end, s1a1);
      },
    );

    test('may end in a later surah, and the plan crosses with it', () async {
      final SessionCubit cubit = await open();
      cubit.chooseRange(s1a3, s2a1);

      expect(cubit.state.configError, isNull);
      expect(cubit.state.plan!.surahNumbers, <int>[1, 2]);
      expect(cubit.state.plan!.steps.last.refs, const <AyahRef>[s1a3, s2a1]);
    });

    test(
      'an ayah past the end of its surah is pulled back inside it',
      () async {
        final SessionCubit cubit = await open();
        cubit.chooseRange(s1a1, s1a3);
        cubit.setEnd(const AyahRef(1, 99));
        expect(cubit.state.config!.end, s1a3);
      },
    );

    test('keeps the tuning when the range moves', () async {
      final SessionCubit cubit = await open();
      cubit.suggestRange(s1a1, s1a3);
      cubit.setRepeatCount(7);
      cubit.suggestRange(s2a1, s2a3);
      expect(cubit.state.config!.repeatCount, 7);
    });
  });

  group('"last used", from Settings', () {
    AppSettings remembering({AyahRange? surah1}) {
      const AppSettings base = AppSettings(
        reciterId: 'b',
        defaultRangeBehaviour: RangeBehaviour.lastUsed,
      );
      return surah1 == null ? base : base.rememberRange(1, surah1);
    }

    test(
      'a surah opened whole gets its last range back, as a choice',
      () async {
        final SessionCubit cubit = await open(
          stored: remembering(
            surah1: const AyahRange(startAyah: 2, endAyah: 3),
          ),
        );
        cubit.suggestRange(s1a1, s1a3);

        expect(cubit.state.rangeChosen, isTrue);
        expect(cubit.state.config!.start, const AyahRef(1, 2));
        expect(cubit.state.config!.end, s1a3);
      },
    );

    test('cleared, it does not come straight back', () async {
      final SessionCubit cubit = await open(
        stored: remembering(surah1: const AyahRange(startAyah: 2, endAyah: 3)),
      );
      cubit.suggestRange(s1a1, s1a3);
      cubit.clearRange();
      cubit.suggestRange(s1a1, s1a3);

      expect(cubit.state.rangeChosen, isFalse);
      expect(cubit.state.config!.start, s1a1);
    });

    test(
      'a page in the middle of the mushaf is not a surah opened whole',
      () async {
        final SessionCubit cubit = await open(
          stored: remembering(
            surah1: const AyahRange(startAyah: 1, endAyah: 2),
          ),
        );
        cubit.suggestRange(const AyahRef(1, 2), s1a3);
        expect(cubit.state.rangeChosen, isFalse);
      },
    );

    test('a range that no longer fits the surah is not handed back', () async {
      final SessionCubit cubit = await open(
        stored: remembering(surah1: const AyahRange(startAyah: 2, endAyah: 40)),
      );
      cubit.suggestRange(s1a1, s1a3);
      expect(cubit.state.rangeChosen, isFalse);
    });

    test(
      'starting a session writes its range down — inside one surah only',
      () async {
        final SessionCubit cubit = await open(stored: remembering());
        cubit.chooseRange(const AyahRef(1, 2), s1a3);
        await cubit.start();
        await settle();
        expect(
          settings.saved.last.rememberedRangeFor(1),
          const AyahRange(startAyah: 2, endAyah: 3),
        );

        final int writes = settings.saved.length;
        cubit.chooseRange(s1a3, s2a1);
        await cubit.start();
        await settle();
        expect(
          settings.saved,
          hasLength(writes),
          reason: 'no surah to file it under',
        );
      },
    );

    test('writing a range down does not undo what was saved elsewhere since '
        'the screen opened', () async {
      final SessionCubit cubit = await open(stored: remembering());
      // While the reading screen is open, the theme is changed in Settings and
      // the update prompt is put off.
      final DateTime prompted = DateTime(2026, 9, 20, 9);
      settings.writtenElsewhere(
        remembering().copyWith(
          themeMode: AppThemeMode.dark,
          updatePromptedAt: prompted,
          onboardingSeen: true,
        ),
      );

      cubit.chooseRange(const AyahRef(1, 2), s1a3);
      await cubit.start();
      await settle();

      final AppSettings written = settings.saved.last;
      expect(written.rememberedRangeFor(1), isNotNull);
      expect(written.themeMode, AppThemeMode.dark);
      expect(written.updatePromptedAt, prompted);
      expect(written.onboardingSeen, isTrue);
    });

    test('saving as defaults keeps what was saved elsewhere, too', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      settings.writtenElsewhere(
        const AppSettings(reciterId: 'b', homeViewMode: HomeViewMode.mushaf),
      );
      cubit.suggestRange(s1a1, s1a3);
      cubit.setRepeatCount(9);

      await cubit.saveAsDefaults();

      expect(settings.saved.last.defaultRepeatCount, 9);
      expect(settings.saved.last.homeViewMode, HomeViewMode.mushaf);
    });

    test('"whole surah" remembers nothing', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(const AyahRef(1, 2), s1a3);
      await cubit.start();
      await settle();
      expect(settings.saved, isEmpty);
    });
  });

  group('the summary', () {
    test('adds up measured clips, across surahs', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a3, s2a1);
      await settle();
      expect(cubit.state.estimatedDuration, isNotNull);
    });

    test('shows no duration rather than a guess when clips are not on the '
        'device', () async {
      final SessionCubit cubit = await open(reciterId: 'b', measurable: false);
      cubit.chooseRange(s1a1, s1a3);
      await settle();
      expect(cubit.state.estimatedDuration, isNull);
      expect(cubit.state.canStart, isTrue, reason: 'streaming still plays');
    });
  });

  group('playing', () {
    Future<SessionCubit> started({
      AyahRef from = s1a1,
      AyahRef to = s1a3,
    }) async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(from, to);
      // Said outright: the app's own default is a setting, and may change.
      cubit.setConnectMode(ConnectMode.cumulative);
      await cubit.start();
      return cubit;
    }

    test(
      'starts from the top, with every surah of the catalog to hand',
      () async {
        final SessionCubit cubit = await started();

        expect(cubit.state.phase, SessionPhase.active);
        expect(player.loads.single.startAtUnit, 0);
        expect(player.loads.single.reciter.id, 'b');
        expect(player.playCalls, 1);
        // Once it is playing, the reciting ayah is the only mark on the page.
        expect(cubit.state.markedRange, isNull);
      },
    );

    test('a page turned mid-session does not change what is playing', () async {
      final SessionCubit cubit = await started();
      cubit.clearRange();
      cubit.suggestRange(s2a1, s2a3);
      expect(cubit.state.config!.start, s1a1);
    });

    test('speed is applied as it moves, with nothing to decide', () async {
      final SessionCubit cubit = await started();
      cubit.setPlaybackSpeed(1.25);

      expect(player.speeds, <double>[1.25]);
      expect(cubit.state.hasPendingChange, isFalse);
      expect(player.loads, hasLength(1));
    });

    test('pauses re-queue the session at the very play it was on', () async {
      final SessionCubit cubit = await started();
      final SessionPlan plan = cubit.state.activePlan!;
      player.reach(plan.units[4]);
      await settle();

      cubit.setBetweenStepsPause(3000);
      await settle();

      expect(cubit.state.hasPendingChange, isFalse);
      expect(player.loads, hasLength(2));
      expect(player.loads.last.startAtUnit, 4);
      expect(player.loads.last.plan.config.betweenStepsPauseMs, 3000);
      expect(player.loads.last.plan.steps, plan.steps, reason: 'same session');
    });

    test('other changes wait to be told: start again, or carry on', () async {
      final SessionCubit cubit = await started();
      cubit.setRepeatCount(5);

      expect(cubit.state.hasPendingChange, isTrue);
      expect(player.loads, hasLength(1), reason: 'nothing happens unasked');
      expect(cubit.state.activePlan!.config.repeatCount, isNot(5));
    });

    test(
      'carrying on resumes at the start of the current ayah\'s drill',
      () async {
        final SessionCubit cubit = await started();
        final SessionPlan before = cubit.state.activePlan!;
        // Deep in the session: the joined block after ayah 2.
        final PlaybackUnit here = before.units.lastWhere(
          (PlaybackUnit u) => u.ref == const AyahRef(1, 2),
        );
        player.reach(here);
        await settle();

        cubit.setRepeatCount(5);
        await cubit.applyChanges(restart: false);

        final SessionPlan after = player.loads.last.plan;
        final PlaybackUnit resumed = after.units[player.loads.last.startAtUnit];
        expect(after.config.repeatCount, 5);
        expect(resumed.ref, const AyahRef(1, 2));
        expect(resumed.stepType, StepType.learn);
        expect(resumed.repeatIndex, 1);
        expect(cubit.state.hasPendingChange, isFalse);
      },
    );

    test(
      'carrying on from an ayah the new range dropped starts at the top',
      () async {
        final SessionCubit cubit = await started();
        player.reach(cubit.state.activePlan!.units.first);
        await settle();

        cubit.chooseRange(const AyahRef(1, 2), s1a3);
        await cubit.applyChanges(restart: false);

        expect(player.loads.last.startAtUnit, 0);
      },
    );

    test(
      'a change that has been answered stops being pending at once',
      () async {
        final SessionCubit cubit = await started();
        cubit.setRepeatCount(5);
        expect(cubit.state.hasPendingChange, isTrue);

        // Not awaited: the screen closes its sheet on the same tap, and must
        // not find the question still open.
        final Future<void> applying = cubit.applyChanges(restart: false);
        expect(cubit.state.hasPendingChange, isFalse);
        await applying;
        expect(cubit.state.hasPendingChange, isFalse);
      },
    );

    test('starting again goes to the top with the new settings', () async {
      final SessionCubit cubit = await started();
      player.reach(cubit.state.activePlan!.units[5]);
      await settle();

      cubit.setConnectMode(ConnectMode.none);
      await cubit.applyChanges(restart: true);

      expect(player.loads.last.startAtUnit, 0);
      expect(player.loads.last.plan.config.connectMode, ConnectMode.none);
    });

    test('another reciter is a change to decide on, too', () async {
      final SessionCubit cubit = await started();
      cubit.setReciter(
        cubit.state.reciters.firstWhere((Reciter r) => r.id == 'a'),
      );
      expect(cubit.state.hasPendingChange, isTrue);

      cubit.discardChanges();
      expect(cubit.state.hasPendingChange, isFalse);
      expect(cubit.state.reciter?.id, 'b');
    });

    test(
      'dropping the changes puts the settings back as they are playing',
      () async {
        final SessionCubit cubit = await started();
        final SessionConfig playing = cubit.state.activePlan!.config;
        cubit.setRepeatCount(9);
        cubit.discardChanges();
        expect(cubit.state.config, playing);
        expect(cubit.state.hasPendingChange, isFalse);
      },
    );

    test(
      'what was recited is written down by surah and ayah when it stops',
      () async {
        final SessionCubit cubit = await started(from: s1a3, to: s2a1);
        final SessionPlan plan = cubit.state.activePlan!;
        for (final PlaybackUnit unit in plan.units.take(5)) {
          player.reach(unit);
          await settle();
        }

        await cubit.stop();

        expect(cubit.state.phase, SessionPhase.idle);
        expect(player.ended, 1);
        // Three repeats of 1:3, then two of 2:1 — never filed under one surah.
        expect(progress.recorded[const AyahRef(1, 3)], 3);
        expect(progress.recorded[const AyahRef(2, 1)], 2);
      },
    );

    test(
      'a source that will not open ends in a sentence, not a crash',
      () async {
        player.failOnPlay = true;
        final SessionCubit cubit = await started();
        expect(cubit.state.phase, SessionPhase.failed);
        expect(cubit.state.failure, isNotNull);
      },
    );

    test('leaving the screen ends the session', () async {
      final SessionCubit cubit = await started();
      await cubit.close();
      expect(player.ended, 1);
    });
  });
}

/// A store that holds what was last saved, the way the real one does — so
/// that "read it fresh before changing it" is something a test can see.
class _Settings implements SettingsRepository {
  _Settings(this._current);

  AppSettings _current;
  final List<AppSettings> saved = <AppSettings>[];

  /// Someone other than the session writing: the settings screen, say.
  void writtenElsewhere(AppSettings settings) => _current = settings;

  @override
  Future<Either<Failure, AppSettings>> read() async =>
      Right<Failure, AppSettings>(_current);

  @override
  Future<Either<Failure, AppSettings>> save(AppSettings settings) async {
    _current = settings;
    saved.add(settings);
    return Right<Failure, AppSettings>(settings);
  }

  @override
  Stream<AppSettings> get changes => const Stream<AppSettings>.empty();
}

/// One second per ayah — the summary only needs a measurement to exist.
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

class _Progress implements ProgressRepository {
  final Map<AyahRef, int> recorded = <AyahRef, int>{};

  @override
  Future<Either<Failure, Unit>> recordRepeats(
    int surahNumber,
    int ayahNumber,
    int repeats, {
    DateTime? at,
  }) async {
    recorded.update(
      AyahRef(surahNumber, ayahNumber),
      (int n) => n + repeats,
      ifAbsent: () => repeats,
    );
    return const Right<Failure, Unit>(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
