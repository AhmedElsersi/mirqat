import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../core/widgets/settings_card.dart';
import '../../../data/models/app_settings.dart';
import '../../../domain/entities/session_config.dart';
import '../cubit/settings_cubit.dart';
import '../cubit/settings_state.dart';

/// The values every new session starts from: repeats, the way of joining,
/// the pauses, the speed, the closing pass — and which range a surah opens
/// with.
///
/// The tuning is [SessionTuningControls], the very widget the reading view's
/// session sheet is built from, so the two can never offer different things.
/// What differs is where a change lands: here it is a default and is saved;
/// there it is for that session and is gone with it.
class SessionSettingsScreen extends StatelessWidget {
  const SessionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.settingsSectionSession.tr())),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (BuildContext context, SettingsState state) {
          final SettingsCubit cubit = context.read<SettingsCubit>();
          final AppSettings settings = state.settings;
          final ConnectMode mode = settings.defaultConnectMode;

          return ListView(
            padding: EdgeInsetsDirectional.all(16.r),
            children: <Widget>[
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(4.w, 0, 4.w, 16.h),
                child: Text(
                  LocaleKeys.settingsSessionPageHint.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              SettingsCard(
                title: LocaleKeys.settingsCardSession.tr(),
                icon: Icons.repeat,
                children: <Widget>[
                  SessionTuningControls(
                    repeatCount: settings.defaultRepeatCount,
                    connectMode: mode,
                    intraBlockPauseMs: settings.defaultIntraBlockPauseMs,
                    betweenRepeatPauseMs: settings.defaultBetweenRepeatPauseMs,
                    betweenStepsPauseMs: settings.defaultBetweenStepsPauseMs,
                    playbackSpeed: settings.defaultPlaybackSpeed,
                    finalFullPass:
                        settings.defaultFinalFullPass ??
                        mode.defaultFinalFullPass,
                    onRepeatCount: cubit.setDefaultRepeatCount,
                    onConnectMode: cubit.setDefaultConnectMode,
                    onIntraBlockPause: cubit.setDefaultIntraBlockPause,
                    onBetweenRepeatPause: cubit.setDefaultBetweenRepeatPause,
                    onBetweenStepsPause: cubit.setDefaultBetweenStepsPause,
                    onPlaybackSpeed: cubit.setDefaultPlaybackSpeed,
                    onFinalFullPass: cubit.setDefaultFinalFullPass,
                  ),
                ],
              ),
              SettingsCard(
                title: LocaleKeys.settingsDefaultRangeBehaviour.tr(),
                icon: Icons.straighten,
                children: <Widget>[
                  RadioGroup<RangeBehaviour>(
                    groupValue: settings.defaultRangeBehaviour,
                    onChanged: (RangeBehaviour? b) {
                      if (b != null) cubit.setDefaultRangeBehaviour(b);
                    },
                    child: Column(
                      children: <Widget>[
                        for (final RangeBehaviour behaviour
                            in RangeBehaviour.values)
                          RadioListTile<RangeBehaviour>(
                            contentPadding: EdgeInsetsDirectional.zero,
                            title: Text(_rangeLabel(behaviour).tr()),
                            value: behaviour,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static String _rangeLabel(RangeBehaviour behaviour) => switch (behaviour) {
    RangeBehaviour.wholeSurah => LocaleKeys.settingsRangeWholeSurah,
    RangeBehaviour.lastUsed => LocaleKeys.settingsRangeLastUsed,
  };
}
