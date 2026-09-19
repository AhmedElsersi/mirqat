import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../data/models/ayah.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../domain/entities/plan_step.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/player_cubit.dart';
import '../cubit/player_state.dart';
import '../player_args.dart';
import '../widgets/ayah_text_view.dart';
import '../widgets/plan_timeline.dart';
import '../widgets/player_controls.dart';
import '../widgets/step_header.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({required this.args, super.key});

  final PlayerArgs args;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<PlayerCubit>(
      create: (_) => sl<PlayerCubit>()..start(args),
      child: _PlayerView(args: args),
    );
  }
}

class _PlayerView extends StatelessWidget {
  const _PlayerView({required this.args});

  final PlayerArgs args;

  @override
  Widget build(BuildContext context) {
    // The reader's chosen size, applied live from the app-wide settings.
    final double ayahFontSize = context.select<SettingsCubit, double>(
      (SettingsCubit cubit) => cubit.state.settings.arabicFontSize,
    );

    final List<Ayah> rangeAyahs = args.ayahs
        .where(
          (Ayah a) =>
              a.number >= args.plan.config.startAyah &&
              a.number <= args.plan.config.endAyah,
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(args.surah.nameAr),
        actions: <Widget>[
          // Who is reciting, compactly. The name is in the tooltip rather than
          // on the bar: at this size it would crowd the surah name, and during
          // a session the surah is what the listener needs to see.
          Padding(
            padding: EdgeInsetsDirectional.only(end: 12.w),
            child: Tooltip(
              message: args.reciter.nameAr,
              child: ReciterAvatar(reciter: args.reciter, diameter: 30),
            ),
          ),
        ],
      ),
      body: BlocBuilder<PlayerCubit, PlayerScreenState>(
        builder: (BuildContext context, PlayerScreenState state) {
          if (state.status.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.status.isFailure) {
            return ErrorView(
              message: _failureMessage(state.failure),
              onRetry: () => context.read<PlayerCubit>().start(args),
            );
          }

          final PlayerCubit cubit = context.read<PlayerCubit>();
          final PlaybackUnit? unit = state.currentUnit;
          final PlanStep step = args.plan.steps[state.stepIndex];

          return SafeArea(
            top: false,
            child: Column(
              children: <Widget>[
                StepHeader(
                  stepIndex: state.stepIndex,
                  stepCount: args.plan.stepCount,
                  step: step,
                  repeatIndex: unit?.repeatIndex ?? 0,
                  totalRepeats:
                      unit?.totalRepeats ?? args.plan.config.repeatCount,
                  connectMode: args.plan.config.connectMode,
                ),
                const Divider(height: 1),
                Expanded(
                  child: AyahTextView(
                    ayahs: rangeAyahs,
                    currentAyah: unit?.ayahNumber,
                    blockFrom: unit?.blockFrom ?? step.fromAyah,
                    blockTo: unit?.blockTo ?? step.toAyah,
                    fontSize: ayahFontSize,
                  ),
                ),
                if (state.finished)
                  Padding(
                    padding: EdgeInsetsDirectional.only(bottom: 8.h),
                    child: Text(
                      LocaleKeys.playerFinished.tr(),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                PlanTimeline(
                  steps: args.plan.steps,
                  currentStepIndex: state.stepIndex,
                ),
                SwitchListTile.adaptive(
                  dense: true,
                  title: Text(
                    LocaleKeys.playerKeepAwake.tr(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  value: state.keepAwake,
                  onChanged: cubit.setKeepAwake,
                ),
                const Divider(height: 1),
                PlayerControls(
                  playing: state.playing,
                  onPlayPause: cubit.togglePlayPause,
                  onPreviousStep: cubit.previousStep,
                  onNextStep: cubit.nextStep,
                  onRestartStep: cubit.restartStep,
                  onStop: cubit.stop,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// What the listener is told. The offline line is the one that actually
  /// gets read: a surah nobody downloaded, opened on a train.
  static String _failureMessage(PlayerFailure? failure) =>
      switch (failure ?? PlayerFailure.unknown) {
        PlayerFailure.audioUnreachable => LocaleKeys.playerErrorOffline.tr(),
        PlayerFailure.configuration => LocaleKeys.playerErrorConfig.tr(),
        PlayerFailure.unknown => LocaleKeys.playerErrorUnknown.tr(),
      };
}
