import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:mirqat/core/localization/app_localization.dart';
import 'package:mirqat/features/session/widgets/session_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/error/failures.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/practice_repository.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/data/repositories/settings_repository.dart';
import 'package:mirqat/domain/engine/repetition_plan_builder.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/hifz_plan.dart';
import 'package:mirqat/domain/entities/interrupted_session.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/practice_stats.dart';
import 'package:mirqat/domain/entities/review_card.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/session/cubit/session_state.dart';
import 'package:mirqat/features/review/cubit/review_cubit.dart';
import 'package:mirqat/features/session/session_request.dart';
import 'package:mirqat/services/audio/ayah_duration_service.dart';
import 'package:mirqat/services/audio/reciter_catalog.dart';
import 'package:mirqat/services/keep_awake_service.dart';

import '../fake_review_repository.dart';
import '../fake_session_player.dart';
import '../localized.dart';
import '../quran_db_fixtures.dart';

/// Surah fixtures, three ayahs each: 1 is recorded by reciters a and b, 2 only
/// by b, 3 by nobody.
void main() {
  late QuranRepository quran;
  late _Settings settings;
  late FakeSessionPlayer player;
  late _Progress progress;
  late FakeReviewRepository reviews;
  late _Practice practice;

  setUp(() {
    practice = _Practice();
    quran = fixtureRepository();
    player = FakeSessionPlayer();
    progress = _Progress();
    reviews = FakeReviewRepository();
  });

  Future<SessionCubit> open({
    String? reciterId,
    bool measurable = true,
    AppSettings? stored,
    Duration placeSaveDelay = const Duration(seconds: 3),
    DateTime Function()? clock,
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
      reviewRepository: reviews,
      practiceRepository: practice,
      clock: clock ?? () => DateTime(2026, 10, 19, 20),
      pauseSettleTime: Duration.zero,
      placeSaveDelay: placeSaveDelay,
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

    test('the day\'s practice is written down with it', () async {
      final SessionCubit cubit = await started();
      for (final PlaybackUnit unit in cubit.state.activePlan!.units.take(4)) {
        player.reach(unit);
        await settle();
      }
      await cubit.stop();
      expect(practice.days.keys.single, DateTime(2026, 10, 19, 20));
      expect(practice.days.values.single.plays, 4);
    });

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

  group('stumbles', () {
    test(
      'marks stored before the screen opened are read with the catalog',
      () async {
        progress.stumbles[const AyahRef(1, 2)] = 3;
        final SessionCubit cubit = await open(reciterId: 'b');
        expect(cubit.state.stumbled, <AyahRef>{const AyahRef(1, 2)});
      },
    );

    test(
      'a stumbled ayah in the range is drilled more; the rest as set',
      () async {
        final SessionCubit cubit = await open(reciterId: 'b');
        cubit.chooseRange(s1a1, s1a3);
        cubit.setConnectMode(ConnectMode.none);
        cubit.setRepeatCount(3);
        await cubit.markStumble(const AyahRef(1, 2));

        final List<PlanStep> learns = cubit.state.plan!.steps
            .whereType<LearnStep>()
            .toList();
        expect(learns.map((PlanStep s) => s.repeats), <int>[
          3,
          3 + RepetitionPlanBuilder.reinforceExtra,
          3,
        ]);
      },
    );

    test('clearing the mark puts the drill back', () async {
      progress.stumbles[const AyahRef(1, 2)] = 1;
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.clearStumble(const AyahRef(1, 2));
      expect(cubit.state.stumbled, isEmpty);
      expect(
        cubit.state.plan!.steps.whereType<LearnStep>().map(
          (PlanStep s) => s.repeats,
        ),
        everyElement(cubit.state.config!.repeatCount),
      );
    });

    test('a mark made mid-session leaves the running session alone, and a '
        'pause change still resumes at the very play it was on', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      final SessionPlan running = cubit.state.activePlan!;
      player.reach(running.units[4]);
      await settle();

      await cubit.markStumble(s1a1);
      expect(cubit.state.hasPendingChange, isFalse);
      expect(cubit.state.activePlan, running);

      cubit.setBetweenStepsPause(2000);
      await settle();
      expect(player.loads.last.plan.steps, running.steps);
      expect(player.loads.last.startAtUnit, 4);
    });
  });

  group('a session asked for on the way in', () {
    test('chooses its range and lays its preset over the defaults', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      await cubit.applyRequest(
        const SessionRequest(
          from: AyahRef(1, 2),
          to: s1a3,
          preset: SessionPreset(
            repeatCount: 1,
            connectMode: ConnectMode.continuous,
            recallRounds: 1,
          ),
        ),
      );
      final SessionConfig c = cubit.state.config!;
      expect(cubit.state.rangeChosen, isTrue);
      expect(c.start, const AyahRef(1, 2));
      expect(c.end, s1a3);
      expect(c.repeatCount, 1);
      expect(c.connectMode, ConnectMode.continuous);
      expect(c.recallRounds, 1);
      expect(
        cubit.state.phase,
        SessionPhase.idle,
        reason: 'not asked to start',
      );
    });

    test('starts when asked to', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      await cubit.applyRequest(
        const SessionRequest(from: s1a1, to: s1a1, autostart: true),
      );
      expect(cubit.state.phase, SessionPhase.active);
      expect(player.loads.single.plan.config.start, s1a1);
      expect(player.loads.single.plan.config.end, s1a1);
    });

    test(
      'an ayah past the end of its surah is pulled back inside it',
      () async {
        final SessionCubit cubit = await open(reciterId: 'b');
        await cubit.applyRequest(
          const SessionRequest(from: AyahRef(1, 2), to: AyahRef(1, 99)),
        );
        expect(cubit.state.config!.end, s1a3);
      },
    );

    test('a range nobody recorded is set up, never started', () async {
      final SessionCubit cubit = await open(reciterId: 'a');
      await cubit.applyRequest(
        const SessionRequest(
          from: AyahRef(3, 1),
          to: AyahRef(3, 2),
          autostart: true,
        ),
      );
      expect(cubit.state.phase, SessionPhase.idle);
      expect(player.loads, isEmpty);
    });
  });

  group('reciting to a listener', () {
    test('a running session is stopped: the reader\'s voice is the '
        'recitation now', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      await cubit.startTasmee();
      expect(cubit.state.tasmee, isTrue);
      expect(cubit.state.phase, SessionPhase.idle);
      expect(player.ended, 1);
    });

    test(
      'each slip is a stumble at its ayah; undo takes back the last',
      () async {
        final SessionCubit cubit = await open(reciterId: 'b');
        await cubit.startTasmee();
        await cubit.markInTasmee(const AyahRef(1, 2));
        await cubit.markInTasmee(const AyahRef(1, 2));
        await cubit.markInTasmee(s1a3);
        expect(cubit.state.tasmeeMarks, hasLength(3));
        expect(progress.stumbles[const AyahRef(1, 2)], 2);
        expect(cubit.state.stumbled, contains(s1a3));

        await cubit.undoTasmeeMark();
        expect(cubit.state.tasmeeMarks, hasLength(2));
        expect(progress.stumbles.containsKey(s1a3), isFalse);
        expect(cubit.state.stumbled, isNot(contains(s1a3)));
      },
    );

    test('ending says what was noted, and the notes stay', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      await cubit.startTasmee();
      await cubit.markInTasmee(s1a1);
      final List<AyahRef> marks = cubit.endTasmee();
      expect(marks, <AyahRef>[s1a1]);
      expect(cubit.state.tasmee, isFalse);
      expect(progress.stumbles[s1a1], 1);
    });

    test('outside a sitting, a slip is not noted', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      await cubit.markInTasmee(s1a1);
      expect(progress.stumbles, isEmpty);
    });

    test('starting a session ends the sitting', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      await cubit.startTasmee();
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      expect(cubit.state.tasmee, isFalse);
    });

    for (final Locale locale in AppLocalization.supportedLocales) {
      testWidgets('the bar holds the count, undo and end at 320 dp, in '
          '${locale.languageCode}', (WidgetTester tester) async {
        await ensureTestLocalization();
        late SessionCubit cubit;
        await tester.runAsync(() async {
          cubit = await open(reciterId: 'b');
          await cubit.startTasmee();
          await cubit.markInTasmee(s1a1);
        });
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          localized(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (BuildContext context, _) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: BlocProvider<SessionCubit>.value(
                      value: cubit,
                      child: SessionBar(visible: true, onOpenSettings: () {}),
                    ),
                  ),
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await settleLocalization(tester);
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.undo), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
      });
    }
  });

  group('the resume prompt at 320 dp', () {
    for (final Locale locale in AppLocalization.supportedLocales) {
      testWidgets('fits, and carries on when asked, in '
          '${locale.languageCode}', (WidgetTester tester) async {
        await ensureTestLocalization();
        late SessionCubit cubit;
        await tester.runAsync(() async {
          cubit = await open(
            stored: AppSettings(
              reciterId: 'b',
              interruptedSession: InterruptedSession(
                config: const SessionConfig(
                  surahNumber: 1,
                  startAyah: 1,
                  endSurahNumber: 2,
                  endAyah: 3,
                ),
                reciterId: 'b',
                at: const AyahRef(2, 1),
                savedAt: DateTime(2026, 10, 19, 8),
              ),
            ),
          );
        });
        Intl.defaultLocale = locale.toString();
        addTearDown(() => Intl.defaultLocale = null);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          localized(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (BuildContext context, _) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: BlocProvider<SessionCubit>.value(
                      value: cubit,
                      child: SessionBar(visible: true, onOpenSettings: () {}),
                    ),
                  ),
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await settleLocalization(tester);
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.history), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.byIcon(Icons.play_arrow).first);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(player.loads, hasLength(1));
        await tester.runAsync(cubit.close);
      });
    }
  });

  group('the playing bar at 320 dp', () {
    for (final Locale locale in AppLocalization.supportedLocales) {
      testWidgets('grade prompt, moon, repeat and counter fit, in '
          '${locale.languageCode}', (WidgetTester tester) async {
        await ensureTestLocalization();
        late SessionCubit cubit;
        await tester.runAsync(() async {
          cubit = await open(reciterId: 'b');
          cubit.chooseRange(s1a1, s1a3);
          await cubit.start();
          player.reach(cubit.state.activePlan!.units[5]);
          await settle();
          cubit.setSleepTimer(const Duration(minutes: 30));
          // A question left from an earlier range, still on show.
          cubit.emit(cubit.state.copyWith(gradeOffer: (from: s1a1, to: s1a3)));
        });
        Intl.defaultLocale = locale.toString();
        addTearDown(() => Intl.defaultLocale = null);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          localized(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (BuildContext context, _) => MaterialApp(
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: BlocProvider<SessionCubit>.value(
                      value: cubit,
                      child: SessionBar(visible: true, onOpenSettings: () {}),
                    ),
                  ),
                ),
              ),
            ),
            locale: locale,
          ),
        );
        await settleLocalization(tester);
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
        expect(find.byIcon(Icons.replay), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNWidgets(3));
        await tester.runAsync(cubit.close);
      });
    }
  });

  group('quick presets', () {
    test('lay their values over the settings, the range kept', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(const AyahRef(1, 2), s1a3);
      cubit.applyPreset(SessionPreset.deep);
      final SessionConfig c = cubit.state.config!;
      expect(c.repeatCount, 7);
      expect(c.recallRounds, 2);
      expect(c.chainRecall, isTrue);
      expect(c.start, const AyahRef(1, 2));
      expect(cubit.state.rangeChosen, isTrue);

      cubit.applyPreset(SessionPreset.old);
      expect(cubit.state.config!.connectMode, ConnectMode.continuous);
      expect(cubit.state.config!.repeatCount, 1);
    });

    test('under a running session, a preset waits to be told', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      cubit.applyPreset(SessionPreset.deep);
      expect(cubit.state.hasPendingChange, isTrue);
      expect(player.loads, hasLength(1));
    });

    test('the review tiers use the same presets', () {
      expect(ReviewItem.presetFor(ReviewTier.sabqi), SessionPreset.recent);
      expect(ReviewItem.presetFor(ReviewTier.manzil), SessionPreset.old);
    });
  });

  group('picking up an interrupted session', () {
    const Duration quick = Duration(milliseconds: 10);
    Future<void> waitForSave() =>
        Future<void>.delayed(const Duration(milliseconds: 40));

    test('the place is written down shortly after each ayah begins', () async {
      final SessionCubit cubit = await open(
        reciterId: 'b',
        placeSaveDelay: quick,
      );
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      player.reach(cubit.state.activePlan!.units[4]);
      await waitForSave();
      final InterruptedSession? saved = settings.saved.last.interruptedSession;
      expect(saved, isNotNull);
      expect(saved!.at, cubit.state.activePlan!.units[4].ref);
      expect(saved.reciterId, 'b');
      expect(saved.config, cubit.state.activePlan!.config);
    });

    test('a session played out, or stopped on purpose, leaves nothing to '
        'pick up', () async {
      final SessionCubit cubit = await open(
        reciterId: 'b',
        placeSaveDelay: quick,
      );
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      player.reach(cubit.state.activePlan!.units[1]);
      await waitForSave();
      await cubit.stop();
      await waitForSave();
      expect(settings.saved.last.interruptedSession, isNull);

      await cubit.start();
      player.reach(cubit.state.activePlan!.units[1]);
      await waitForSave();
      player.complete();
      await waitForSave();
      expect(settings.saved.last.interruptedSession, isNull);
    });

    test('leaving the screen mid-session writes the place at once', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      player.reach(cubit.state.activePlan!.units[2]);
      await settle();
      expect(
        settings.saved.where((AppSettings s) => s.interruptedSession != null),
        isEmpty,
        reason: 'not yet: the save waits',
      );
      await cubit.close();
      expect(settings.saved.last.interruptedSession!.at, s1a1);
    });

    final InterruptedSession left = InterruptedSession(
      config: const SessionConfig(
        surahNumber: 1,
        startAyah: 1,
        endAyah: 3,
        repeatCount: 4,
      ),
      reciterId: 'b',
      at: const AyahRef(1, 2),
      savedAt: DateTime(2026, 10, 19, 8),
    );

    test(
      'offered back the same day, with what it was and where it was',
      () async {
        final SessionCubit cubit = await open(
          stored: AppSettings(reciterId: 'a', interruptedSession: left),
        );
        expect(cubit.state.resumeOffer, left);
      },
    );

    test('not offered once a day has gone by', () async {
      final SessionCubit cubit = await open(
        stored: AppSettings(interruptedSession: left),
        clock: () => DateTime(2026, 10, 20, 9),
      );
      expect(cubit.state.resumeOffer, isNull);
    });

    test(
      'taken up: its settings, its reciter, from the drill of its ayah',
      () async {
        final SessionCubit cubit = await open(
          stored: AppSettings(reciterId: 'a', interruptedSession: left),
        );
        await cubit.resume();
        final SessionLoad load = player.loads.single;
        expect(load.plan.config.repeatCount, 4);
        expect(load.reciter.id, 'b');
        final PlaybackUnit first = load.plan.units[load.startAtUnit];
        expect(first.ref, const AyahRef(1, 2));
        expect(first.stepType, StepType.learn);
        expect(first.repeatIndex, 1);
        expect(cubit.state.resumeOffer, isNull);
      },
    );

    test('waved away, it is forgotten', () async {
      final SessionCubit cubit = await open(
        stored: AppSettings(interruptedSession: left),
      );
      await cubit.dismissResume();
      expect(cubit.state.resumeOffer, isNull);
      expect(settings.saved.last.interruptedSession, isNull);
    });

    test('a new session takes the offer away', () async {
      final SessionCubit cubit = await open(
        reciterId: 'b',
        stored: AppSettings(reciterId: 'b', interruptedSession: left),
      );
      cubit.chooseRange(s2a1, s2a3);
      await cubit.start();
      expect(cubit.state.resumeOffer, isNull);
    });

    test('the settings and the place survive storage', () {
      expect(InterruptedSession.fromMap(left.toMap()), left);
      expect(SessionConfig.fromMap(left.config.toMap()), left.config);
      expect(
        AppSettings.fromMap(
          AppSettings(interruptedSession: left).toMap(),
        ).interruptedSession,
        left,
      );
      expect(InterruptedSession.fromMap(<String, Object?>{'at': 'x'}), isNull);
      expect(SessionConfig.fromMap(<String, Object?>{'surah': 1}), isNull);
    });
  });

  group('listening', () {
    Future<SessionCubit> playing() async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      cubit.setConnectMode(ConnectMode.cumulative);
      await cubit.start();
      await settle();
      return cubit;
    }

    test('the sleep timer pauses — never stops — when it runs out', () async {
      final SessionCubit cubit = await playing();
      cubit.setSleepTimer(const Duration(milliseconds: 20));
      expect(cubit.state.sleepTimerSet, isTrue);
      expect(cubit.state.sleepAt, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cubit.state.playing, isFalse);
      expect(cubit.state.phase, SessionPhase.active, reason: 'the place kept');
      expect(cubit.state.sleepTimerSet, isFalse);
    });

    test('turned off, it never fires', () async {
      final SessionCubit cubit = await playing();
      cubit.setSleepTimer(const Duration(milliseconds: 20));
      cubit.setSleepTimer(null);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(cubit.state.playing, isTrue);
    });

    test('stopping the session takes the timer with it', () async {
      final SessionCubit cubit = await playing();
      cubit.setSleepTimer(const Duration(milliseconds: 20));
      await cubit.stop();
      expect(cubit.state.sleepTimerSet, isFalse);
    });

    test('"end of step" pauses as the next step begins, not before', () async {
      final SessionCubit cubit = await playing();
      final SessionPlan plan = cubit.state.activePlan!;
      player.reach(plan.units[0]);
      await settle();
      cubit.sleepAtEndOfStep();

      for (final PlaybackUnit u in plan.units.where(
        (PlaybackUnit u) => u.stepIndex == 0,
      )) {
        player.reach(u);
        await settle();
      }
      expect(cubit.state.playing, isTrue);

      player.reach(plan.units.firstWhere((PlaybackUnit u) => u.stepIndex == 1));
      await settle();
      expect(cubit.state.playing, isFalse);
    });

    test('three more times lays a one-off drill in at the ayah being heard, '
        'then takes its step up again from the start', () async {
      final SessionCubit cubit = await playing();
      final SessionPlan before = cubit.state.activePlan!;
      final PlaybackUnit here = before.units.firstWhere(
        (PlaybackUnit u) => u.stepIndex == 2,
      );
      player.reach(here);
      await settle();

      await cubit.repeatCurrentAyah();

      final SessionLoad load = player.loads.last;
      expect(load.plan.stepCount, before.stepCount + 1);
      final PlaybackUnit first = load.plan.units[load.startAtUnit];
      expect(first.ref, here.ref);
      expect(first.stepType, StepType.learn);
      expect(first.totalRepeats, 3);
      // After the extra drill, the step it interrupted, whole.
      expect(load.plan.steps[3], before.steps[2]);
      expect(cubit.state.hasPendingChange, isFalse, reason: 'same session');
    });

    test(
      'a pending end-of-step waits for the same step after the insertion',
      () async {
        final SessionCubit cubit = await playing();
        final SessionPlan before = cubit.state.activePlan!;
        player.reach(
          before.units.firstWhere((PlaybackUnit u) => u.stepIndex == 2),
        );
        await settle();
        cubit.sleepAtEndOfStep();
        await cubit.repeatCurrentAyah();
        final SessionPlan after = player.loads.last.plan;

        // The inserted drill (step 2) and the interrupted step (now 3) play on.
        for (final PlaybackUnit u in after.units.where(
          (PlaybackUnit u) => u.stepIndex == 2 || u.stepIndex == 3,
        )) {
          player.reach(u);
          await settle();
        }
        expect(cubit.state.playing, isTrue);
        player.reach(
          after.units.firstWhere((PlaybackUnit u) => u.stepIndex == 4),
        );
        await settle();
        expect(cubit.state.playing, isFalse);
      },
    );

    test('listening is straight through once, nothing asked back', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.setRecallRounds(2);
      await cubit.applyRequest(
        const SessionRequest(
          from: AyahRef(1, 2),
          to: s1a3,
          preset: SessionPreset.listen,
          autostart: true,
        ),
      );
      final SessionPlan plan = player.loads.single.plan;
      expect(plan.config.connectMode, ConnectMode.continuous);
      expect(plan.unitCount, 2, reason: 'each ayah once');
      expect(plan.units.where((PlaybackUnit u) => u.asked), isEmpty);
    });
  });

  group('grading what was recited', () {
    Future<SessionCubit> recited({bool all = true}) async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      final SessionPlan plan = cubit.state.activePlan!;
      for (final PlaybackUnit u in plan.units) {
        if (!all && u.ref == s1a3) continue;
        player.reach(u);
        await settle();
      }
      return cubit;
    }

    test('a session played out asks how it went', () async {
      final SessionCubit cubit = await recited();
      player.complete();
      await settle();
      expect(cubit.state.gradeOffer, (from: s1a1, to: s1a3));
    });

    test('stopped after every ayah was heard, it asks too', () async {
      final SessionCubit cubit = await recited();
      await cubit.stop();
      expect(cubit.state.gradeOffer, (from: s1a1, to: s1a3));
      expect(cubit.state.phase, SessionPhase.idle, reason: 'still asked');
    });

    test('stopped before the range was heard through, it does not', () async {
      final SessionCubit cubit = await recited(all: false);
      await cubit.stop();
      expect(cubit.state.gradeOffer, isNull);
    });

    test(
      'the first grade starts the range on the ladder; the next moves it',
      () async {
        final SessionCubit cubit = await recited();
        await cubit.stop();
        await cubit.grade(Grade.solid);
        expect(cubit.state.gradeOffer, isNull);
        final ReviewCard first = reviews.cards.values.single;
        expect(first.id, '1:1-1:3');
        expect(first.step, 0);
        expect(first.due, DateTime(2026, 10, 20));

        await cubit.start();
        for (final PlaybackUnit u in cubit.state.activePlan!.units) {
          player.reach(u);
          await settle();
        }
        await cubit.stop();
        await cubit.grade(Grade.solid);
        expect(reviews.cards.values.single.step, 1);
      },
    );

    test('waving it away writes nothing', () async {
      final SessionCubit cubit = await recited();
      await cubit.stop();
      cubit.dismissGrade();
      expect(cubit.state.gradeOffer, isNull);
      expect(reviews.cards, isEmpty);
    });

    final HifzPlan plan = HifzPlan(
      from: s1a1,
      to: s2a3,
      days: 2,
      started: DateTime(2026, 10, 19),
      portions: const <Portion>[Portion(s1a1, s1a3), Portion(s2a1, s2a3)],
    );

    Future<SessionCubit> recitedWithPlan(AyahRef from, AyahRef to) async {
      final SessionCubit cubit = await open(
        stored: AppSettings(reciterId: 'b', hifzPlan: plan),
      );
      cubit.chooseRange(from, to);
      await cubit.start();
      for (final PlaybackUnit u in cubit.state.activePlan!.units) {
        player.reach(u);
        await settle();
      }
      await cubit.stop();
      return cubit;
    }

    test('today\'s portion graded held moves the plan on', () async {
      final SessionCubit cubit = await recitedWithPlan(s1a1, s1a3);
      await cubit.grade(Grade.shaky);
      expect(settings.saved.last.hifzPlan!.completed, 1);
      expect(settings.saved.last.reciterId, 'b');
    });

    test('forgotten, the plan waits', () async {
      final SessionCubit cubit = await recitedWithPlan(s1a1, s1a3);
      await cubit.grade(Grade.forgot);
      expect(
        settings.saved.where((AppSettings s) => s.hifzPlan?.completed == 1),
        isEmpty,
      );
    });

    test('another range — even one inside the portion — is not the day\'s '
        'work', () async {
      final SessionCubit cubit = await recitedWithPlan(
        s1a1,
        const AyahRef(1, 2),
      );
      await cubit.grade(Grade.solid);
      expect(
        settings.saved.where((AppSettings s) => s.hifzPlan?.completed == 1),
        isEmpty,
      );
    });

    test('a new session takes the old question away', () async {
      final SessionCubit cubit = await recited();
      await cubit.stop();
      await cubit.start();
      expect(cubit.state.gradeOffer, isNull);
    });
  });

  group('recall', () {
    test('changing the connect mode keeps both recall settings', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      cubit.setRecallRounds(2);
      cubit.setChainRecall(true);

      cubit.setConnectMode(ConnectMode.none);

      expect(cubit.state.config!.recallRounds, 2);
      expect(cubit.state.config!.chainRecall, isTrue);
    });

    test(
      'toggling the links test mid-session is a change to decide on',
      () async {
        final SessionCubit cubit = await open(reciterId: 'b');
        cubit.chooseRange(s1a1, s1a3);
        await cubit.start();
        cubit.setChainRecall(true);
        expect(cubit.state.hasPendingChange, isTrue);
      },
    );

    test('a recall gap veils without counting; the answer counts', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a1);
      cubit.setRepeatCount(1);
      cubit.setRecallRounds(1);
      await cubit.start();
      final PlaybackUnit asked = cubit.state.activePlan!.units.firstWhere(
        (PlaybackUnit u) => u.asked,
      );

      player.recall(asked);
      await settle();
      expect(cubit.state.recalling, isTrue);
      expect(cubit.state.currentUnit, asked);

      player.reach(asked);
      await settle();
      expect(cubit.state.recalling, isFalse);

      await cubit.stop();
      expect(progress.recorded[s1a1], 1, reason: 'the gap is not a recitation');
    });

    test('the player is handed measured clips to size the gaps', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      cubit.setRecallRounds(1);
      await cubit.start();
      expect(player.recallClipLoads.single[s1a1], const Duration(seconds: 1));
    });

    test('a session with nothing asked measures nothing for gaps', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      await cubit.start();
      expect(player.recallClipLoads.single, isEmpty);
    });

    test('recall settings are saved as defaults with the rest', () async {
      final SessionCubit cubit = await open(reciterId: 'b');
      cubit.chooseRange(s1a1, s1a3);
      cubit.setRecallRounds(3);
      cubit.setChainRecall(true);
      await cubit.saveAsDefaults();
      expect(settings.saved.last.defaultRecallRounds, 3);
      expect(settings.saved.last.defaultChainRecall, isTrue);
    });
  });
}

class _Practice implements PracticeRepository {
  final Map<DateTime, PracticeDay> days = <DateTime, PracticeDay>{};

  @override
  Future<Either<Failure, Unit>> add(DateTime day, PracticeDay p) async {
    days.update(day, (PracticeDay d) => d.plus(p), ifAbsent: () => p);
    return const Right<Failure, Unit>(unit);
  }

  @override
  Future<Either<Failure, Map<DateTime, PracticeDay>>> all() async =>
      Right<Failure, Map<DateTime, PracticeDay>>(days);

  @override
  Future<Either<Failure, Unit>> set(DateTime day, PracticeDay p) async {
    days[day] = p;
    return const Right<Failure, Unit>(unit);
  }
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

  /// Stumble counts, by ayah — what `stumbled()` reads back.
  final Map<AyahRef, int> stumbles = <AyahRef, int>{};

  @override
  Future<Either<Failure, List<MemorizationProgress>>> stumbled() async =>
      Right<Failure, List<MemorizationProgress>>(<MemorizationProgress>[
        for (final MapEntry<AyahRef, int> e in stumbles.entries)
          MemorizationProgress(
            surahNumber: e.key.surah,
            ayahNumber: e.key.ayah,
            stumbles: e.value,
          ),
      ]);

  @override
  Future<Either<Failure, Unit>> markStumble(
    int surahNumber,
    int ayahNumber, {
    DateTime? at,
  }) async {
    stumbles.update(
      AyahRef(surahNumber, ayahNumber),
      (int n) => n + 1,
      ifAbsent: () => 1,
    );
    return const Right<Failure, Unit>(unit);
  }

  @override
  Future<Either<Failure, Unit>> undoStumble(
    int surahNumber,
    int ayahNumber,
  ) async {
    final AyahRef ref = AyahRef(surahNumber, ayahNumber);
    final int n = stumbles[ref] ?? 0;
    if (n <= 1) {
      stumbles.remove(ref);
    } else {
      stumbles[ref] = n - 1;
    }
    return const Right<Failure, Unit>(unit);
  }

  @override
  Future<Either<Failure, Unit>> clearStumble(
    int surahNumber,
    int ayahNumber,
  ) async {
    stumbles.remove(AyahRef(surahNumber, ayahNumber));
    return const Right<Failure, Unit>(unit);
  }

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
