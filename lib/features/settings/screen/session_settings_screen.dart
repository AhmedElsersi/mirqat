import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/desktop.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../data/models/app_settings.dart';
import '../../../domain/entities/session_config.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// The values every new session starts from: how the ayahs join, how many
/// repeats and recall rounds, the closing passes, the speed and the pauses —
/// and which range a surah opens with.
///
/// The tuning is [SessionTuningControls], the very widget the reading view's
/// session sheet is built from, so the two can never offer different things
/// in a different order. What differs is where a change lands: here it is a
/// default and is saved; there it is for that session and is gone with it.
class SessionSettingsScreen extends StatelessWidget {
  const SessionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.settingsSectionSession.tr())),
      body: DesktopWidth(
        child: BlocBuilder<SettingsCubit, SettingsState>(
          builder: (BuildContext context, SettingsState state) {
            final SettingsCubit cubit = context.read<SettingsCubit>();
            final AppSettings settings = state.settings;
            final ConnectMode mode = settings.defaultConnectMode;

            return ListView(
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
              children: <Widget>[
                Text(
                  LocaleKeys.settingsSessionPageHint.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // The session sheet's own order, so the two are learned
                // once: the two numbers, the joining, the switches.
                SessionTuningControls(
                  repeatCount: settings.defaultRepeatCount,
                  connectMode: mode,
                  recallRounds: settings.defaultRecallRounds,
                  chainRecall: settings.defaultChainRecall,
                  onRepeatCount: cubit.setDefaultRepeatCount,
                  onConnectMode: cubit.setDefaultConnectMode,
                  onRecallRounds: cubit.setDefaultRecallRounds,
                  onChainRecall: cubit.setDefaultChainRecall,
                  rows: <Widget>[
                    SessionSwitchRow(
                      icon: Icons.restart_alt,
                      title: LocaleKeys.sessionSetupFinalFullPass.tr(),
                      value:
                          settings.defaultFinalFullPass ??
                          mode.defaultFinalFullPass,
                      onChanged: cubit.setDefaultFinalFullPass,
                    ),
                    SessionSwitchRow(
                      icon: Icons.shield_outlined,
                      title: LocaleKeys.sessionSetupPlayIstiadhah.tr(),
                      value: settings.defaultPlayIstiadhah,
                      onChanged: cubit.setDefaultPlayIstiadhah,
                    ),
                  ],
                ),
                FieldLabel(LocaleKeys.sessionSetupSpeedAndPauses.tr()),
                SpeedAndPausesList(
                  intraBlockPauseMs: settings.defaultIntraBlockPauseMs,
                  betweenRepeatPauseMs: settings.defaultBetweenRepeatPauseMs,
                  betweenStepsPauseMs: settings.defaultBetweenStepsPauseMs,
                  playbackSpeed: settings.defaultPlaybackSpeed,
                  onIntraBlockPause: cubit.setDefaultIntraBlockPause,
                  onBetweenRepeatPause: cubit.setDefaultBetweenRepeatPause,
                  onBetweenStepsPause: cubit.setDefaultBetweenStepsPause,
                  onPlaybackSpeed: cubit.setDefaultPlaybackSpeed,
                ),
                FieldLabel(LocaleKeys.settingsDefaultRangeBehaviour.tr()),
                // Two choices, so a segmented control rather than two radio
                // rows: both are read at once, and the chosen one is seen
                // without reading either.
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<RangeBehaviour>(
                    showSelectedIcon: false,
                    segments: <ButtonSegment<RangeBehaviour>>[
                      for (final RangeBehaviour behaviour
                          in RangeBehaviour.values)
                        ButtonSegment<RangeBehaviour>(
                          value: behaviour,
                          label: Text(
                            _rangeLabel(behaviour).tr(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    selected: <RangeBehaviour>{settings.defaultRangeBehaviour},
                    onSelectionChanged: (Set<RangeBehaviour> picked) =>
                        cubit.setDefaultRangeBehaviour(picked.first),
                  ),
                ),
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(4.w, 8.h, 4.w, 0),
                  child: Text(
                    LocaleKeys.settingsDefaultRangeHint.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _rangeLabel(RangeBehaviour behaviour) => switch (behaviour) {
    RangeBehaviour.wholeSurah => LocaleKeys.settingsRangeWholeSurah,
    RangeBehaviour.lastUsed => LocaleKeys.settingsRangeLastUsed,
  };
}
