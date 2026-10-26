import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/duration_extensions.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/memorization_view_control.dart';
import '../../../core/widgets/reciter_dropdown.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reciter.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/saved_preset.dart';
import '../../../domain/entities/session_config.dart';
import '../session_request.dart';
import 'audio_pack_tile.dart';
import '../cubit/session_cubit.dart';
import '../cubit/session_state.dart';

/// The session's settings, over the text: who recites, from where to where,
/// how many times, how joined, how fast.
///
/// The same sheet before a session and during one. Before, it sets up the
/// session to come. During, speed and pauses take effect as they are moved;
/// anything that would change what is being recited waits for the reader to
/// say whether to start again or carry on from the ayah being heard.
///
/// Everything here is scratch: it is gone when the reading screen closes.
/// «حفظ كافتراضي» is the only thing that writes to storage, which is what
/// keeps a one-off long session from quietly becoming the reader's normal.
class SessionSheet extends StatelessWidget {
  const SessionSheet({super.key});

  /// Shows the sheet over [context], which must have a [SessionCubit] above
  /// it. Completes when it is put away.
  static Future<void> show(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => BlocProvider<SessionCubit>.value(
        value: cubit,
        child: const SessionSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) =>
          BlocBuilder<SessionCubit, SessionState>(
            builder: (BuildContext context, SessionState state) {
              final SessionConfig? config = state.config;
              if (config == null) return const SizedBox.shrink();
              return Column(
                children: <Widget>[
                  _Header(state: state),
                  Expanded(
                    // A column in a scroll view, not a lazy list: the form
                    // is short, and a slider scrolled out of a lazy list
                    // loses the drag that was moving it.
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: EdgeInsetsDirectional.fromSTEB(
                        18.w,
                        0,
                        18.w,
                        12.h,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (state.block != null) _BlockNotice(state: state),
                          // The way of working first: most sessions are one
                          // tap here. Then the range, the two numbers and
                          // the joining; everything else folds into one row.
                          const _Presets(),
                          _Range(state: state, config: config),
                          _Tuning(state: state, config: config),
                        ],
                      ),
                    ),
                  ),
                  _Footer(state: state),
                ],
              );
            },
          ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(18.w, 0, 8.w, 0),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            // Before a session it is a new one being set up; during one,
            // the settings of the one that is running.
            state.isActive
                ? LocaleKeys.readerSessionSettings.tr()
                : LocaleKeys.readerNewSession.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: LocaleKeys.commonClose.tr(),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}

String _reciterName(BuildContext context, Reciter r) =>
    context.locale.languageCode == 'ar' ? r.nameAr : r.nameEn;

String _surahName(BuildContext context, Surah s) =>
    context.locale.languageCode == 'ar' ? s.nameAr : s.nameEn;

/// Why the play button is disabled, said before anyone presses it — and, when
/// it is only the chosen reciter who lacks the range, a switch to one who
/// has it.
class _BlockNotice extends StatelessWidget {
  const _BlockNotice({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String message = switch (state.block!) {
      SessionBlock.noAudio => LocaleKeys.sessionNoAudioRange.tr(),
      SessionBlock.reciterLacksSurah => LocaleKeys.sessionReciterLacksRange.tr(
        args: <String>[_reciterName(context, state.chosenReciter!)],
      ),
    };

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 16.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline, size: 18.sp, color: theme.colorScheme.error),
          SizedBox(width: 8.w),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _Reciters extends StatelessWidget {
  const _Reciters({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();
    final List<Reciter> available = state.availableReciters;
    final Reciter? current = state.reciter ?? state.chosenReciter;

    return SetupSection(
      label: LocaleKeys.settingsReciter.tr(),
      child: ReciterDropdown(
        reciters: state.reciters,
        currentId: current?.id,
        // A reciter who has not recorded the whole range cannot be picked
        // for it; they stay listed so it is clear why.
        unavailable: (Reciter r) => available.contains(r)
            ? null
            : LocaleKeys.sessionReciterLacksRange.tr(
                args: <String>[_reciterName(context, r)],
              ),
        onChanged: (Reciter picked) => cubit.setReciter(picked),
      ),
    );
  }
}

/// From a surah and an ayah to a surah and an ayah, both picked right here:
/// the surah from a dropdown, the ayah with a stepper beside it. The end may
/// be in a later surah than the start, never an earlier one.
class _Range extends StatelessWidget {
  const _Range({required this.state, required this.config});

  final SessionState state;
  final SessionConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(LocaleKeys.sessionSetupRange.tr()),
        SessionListCard(
          children: <Widget>[
            Padding(
              key: const ValueKey<String>('session-from'),
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: 14.w,
                vertical: 12.h,
              ),
              child: _RangeEnd(
                label: LocaleKeys.sessionSetupFrom.tr(),
                surahs: state.surahs,
                value: config.start,
                onChanged: cubit.setStart,
                isEnd: false,
              ),
            ),
            Padding(
              key: const ValueKey<String>('session-to'),
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: 14.w,
                vertical: 12.h,
              ),
              child: _RangeEnd(
                label: LocaleKeys.sessionSetupTo.tr(),
                // A range only runs forward, so the end is offered from the
                // start's surah on.
                surahs: <Surah>[
                  for (final Surah s in state.surahs)
                    if (s.number >= config.surahNumber) s,
                ],
                value: config.end,
                onChanged: cubit.setEnd,
                isEnd: true,
              ),
            ),
          ],
        ),
        if (!state.rangeChosen && !state.isActive)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(4.w, 8.h, 4.w, 0),
            child: Text(
              LocaleKeys.sessionRangeFromPage.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else if (!state.isActive)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: cubit.clearRange,
              icon: const Icon(Icons.auto_stories_outlined),
              label: Text(LocaleKeys.sessionUsePageRange.tr()),
            ),
          ),
      ],
    );
  }
}

class _RangeEnd extends StatelessWidget {
  const _RangeEnd({
    required this.label,
    required this.surahs,
    required this.value,
    required this.onChanged,
    required this.isEnd,
  });

  final String label;
  final List<Surah> surahs;
  final AyahRef value;
  final ValueChanged<AyahRef> onChanged;

  /// Whether this is the far end of the range, which decides what picking
  /// another surah means: its last ayah here, its first at the near end.
  final bool isEnd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Surah? surah = surahs
        .where((Surah s) => s.number == value.surah)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        SizedBox(height: 4.h),
        Row(
          children: <Widget>[
            Expanded(
              child: DropdownButtonFormField<int>(
                // Keyed by its value: a form field keeps the value it was
                // built with, and the other end can move this one.
                key: ValueKey<int?>(surah?.number),
                initialValue: surah?.number,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: LocaleKeys.sessionSurah.tr(),
                  isDense: true,
                ),
                items: <DropdownMenuItem<int>>[
                  for (final Surah s in surahs)
                    DropdownMenuItem<int>(
                      value: s.number,
                      child: Text(
                        '${s.number.toLocalisedString()}. '
                        '${_surahName(context, s)}',
                      ),
                    ),
                ],
                // Another surah: its first ayah as a start, its last as an
                // end, which is what picking a whole surah nearly always
                // means. The ayah beside it is then a nudge away.
                onChanged: (int? number) {
                  if (number == null || number == value.surah) return;
                  final Surah picked = surahs.firstWhere(
                    (Surah s) => s.number == number,
                  );
                  onChanged(AyahRef(number, isEnd ? picked.ayahCount : 1));
                },
              ),
            ),
            SizedBox(width: 12.w),
            // Half and half: the stepper's two buttons must fit even on the
            // narrowest phone, inside the card's own padding.
            Expanded(
              child: StepperField(
                value: value.ayah,
                min: 1,
                max: surah?.ayahCount ?? value.ayah,
                editable: true,
                formatValue: (int v) => v.toLocalisedString(),
                onChanged: (int ayah) => onChanged(AyahRef(value.surah, ayah)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// When the running session should fall quiet: after so many minutes, or
/// once the step it is on is over. It pauses rather than stops, so the
/// place is kept for the morning.
class _SleepTimer extends StatelessWidget {
  const _SleepTimer({required this.state});

  final SessionState state;

  static const List<int> minutes = <int>[5, 15, 30, 60];

  @override
  Widget build(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();
    final DateTime? at = state.sleepAt;
    return SetupSection(
      label: LocaleKeys.sleepTitle.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8.w,
            runSpacing: 4.h,
            children: <Widget>[
              ChoiceChip(
                label: Text(LocaleKeys.sleepOff.tr()),
                selected: !state.sleepTimerSet,
                onSelected: (_) => cubit.setSleepTimer(null),
              ),
              for (final int m in minutes)
                ChoiceChip(
                  label: Text(
                    LocaleKeys.sleepMinutes.tr(
                      args: <String>[m.toLocalisedString()],
                    ),
                  ),
                  selected: false,
                  onSelected: (_) => cubit.setSleepTimer(Duration(minutes: m)),
                ),
              ChoiceChip(
                label: Text(LocaleKeys.sleepEndOfStep.tr()),
                selected: state.sleepAtEndOfStep,
                onSelected: (_) => cubit.sleepAtEndOfStep(),
              ),
            ],
          ),
          if (at != null)
            Padding(
              padding: EdgeInsetsDirectional.only(top: 6.h),
              child: Text(
                LocaleKeys.sleepUntil.tr(
                  args: <String>[sleepTimeLabel(context, at)],
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// The time a sleep timer falls due, as the clock says it: «١٠:٤٢ م».
String sleepTimeLabel(BuildContext context, DateTime at) =>
    DateFormat.jm(context.locale.toString()).format(at).withLocalisedDigits();

/// How much of the page is covered while reading. Not scratch like the rest
/// of the sheet: it is a way of reading, kept until the reader changes it,
/// and the same setting the settings page shows.
class _MemorizationView extends StatelessWidget {
  const _MemorizationView();

  @override
  Widget build(BuildContext context) {
    final MemorizationView view = context
        .select<SettingsCubit, MemorizationView>(
          (SettingsCubit c) => c.state.settings.memorizationView,
        );
    return MemorizationViewControl(
      value: view,
      onChanged: context.read<SettingsCubit>().setMemorizationView,
    );
  }
}

/// A surah of the range that streams can be taken offline from here. One
/// surah is shown outright; several are folded away so that a session over a
/// juz does not bury the settings under thirty tiles.
class _Downloads extends StatelessWidget {
  const _Downloads({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final Reciter? reciter = state.reciter;
    final List<Surah> surahs = state.rangeSurahs;
    if (reciter == null || surahs.isEmpty) return const SizedBox.shrink();

    // Keyed by reciter and surah: the tile holds a cubit bound to both.
    List<Widget> tiles() => <Widget>[
      for (final Surah surah in surahs)
        AudioPackTile(
          key: ValueKey<String>('${reciter.id}:${surah.number}'),
          reciter: reciter,
          surah: surah,
        ),
    ];

    if (surahs.length == 1) return Column(children: tiles());
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 12.h),
      child: ExpansionTile(
        tilePadding: EdgeInsetsDirectional.zero,
        title: Text(
          LocaleKeys.sessionDownloads.tr(
            args: <String>[surahs.length.toLocalisedString()],
          ),
        ),
        // Built only when opened: each tile asks the device what it holds.
        children: <Widget>[Builder(builder: (_) => Column(children: tiles()))],
      ),
    );
  }
}

/// A way of working, in one tap: learning something new the reader's own
/// way, going over a recent portion, keeping an old one, drilling one that
/// will not settle, or just listening to it, round and round. Each lays its values over the settings below,
/// where they can still be changed.
class _Presets extends StatelessWidget {
  const _Presets();

  @override
  Widget build(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();
    final List<SavedPreset> saved = context
        .select<SessionCubit, List<SavedPreset>>(
          (SessionCubit c) => c.state.defaults.savedPresets,
        );
    final String? chosen = context.select<SessionCubit, String?>(
      (SessionCubit c) => c.state.activePreset,
    );
    // Choice chips: the one in use is marked, the way a choice is anywhere
    // else in the sheet.
    Widget chip(String key, String label, IconData icon, VoidCallback onTap) =>
        ChoiceChip(
          avatar: Icon(icon, size: 16.r),
          label: Text(label),
          selected: chosen == key,
          onSelected: (_) => onTap(),
        );
    // One line that scrolls sideways, as the design's chips do: a way of
    // working is picked, not read through.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FieldLabel(LocaleKeys.presetsTitle.tr()),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsetsDirectional.symmetric(vertical: 2.h),
          child: Row(
            children:
                <Widget>[
                      chip(
                        'new',
                        LocaleKeys.presetsNew.tr(),
                        Icons.eco_outlined,
                        () => cubit.resetToDefaults(key: 'new'),
                      ),
                      chip(
                        'recent',
                        LocaleKeys.presetsRecent.tr(),
                        Icons.replay,
                        () => cubit.applyPreset(
                          SessionPreset.recent,
                          key: 'recent',
                        ),
                      ),
                      chip(
                        'old',
                        LocaleKeys.presetsOld.tr(),
                        Icons.local_library_outlined,
                        () => cubit.applyPreset(SessionPreset.old, key: 'old'),
                      ),
                      chip(
                        'deep',
                        LocaleKeys.presetsDeep.tr(),
                        Icons.anchor,
                        () =>
                            cubit.applyPreset(SessionPreset.deep, key: 'deep'),
                      ),
                      chip(
                        'listen',
                        LocaleKeys.presetsListen.tr(),
                        Icons.headphones_outlined,
                        () => cubit.applyPreset(
                          SessionPreset.listenLoop,
                          key: 'listen',
                        ),
                      ),
                      for (final SavedPreset p in saved)
                        InputChip(
                          avatar: Icon(Icons.bookmark_outline, size: 16.r),
                          label: Text(p.name),
                          selected:
                              chosen == SessionCubit.savedPresetKey(p.name),
                          onPressed: () => cubit.applySaved(p),
                          deleteButtonTooltipMessage: LocaleKeys.presetsDelete
                              .tr(),
                          onDeleted: () =>
                              _confirmDelete(context, cubit, p.name),
                        ),
                    ]
                    .expand(
                      (Widget chip) => <Widget>[chip, SizedBox(width: 8.w)],
                    )
                    .toList(),
          ),
        ),
      ],
    );
  }

  static Future<void> askName(BuildContext context, SessionCubit cubit) async {
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (_) => const _PresetNameDialog(),
    );
    if (chosen != null && chosen.trim().isNotEmpty) {
      await cubit.savePreset(chosen);
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    SessionCubit cubit,
    String name,
  ) async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        content: Text(LocaleKeys.presetsDeleteConfirm.tr(args: <String>[name])),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(LocaleKeys.commonCancel.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(LocaleKeys.presetsDelete.tr()),
          ),
        ],
      ),
    );
    if (yes ?? false) await cubit.deletePreset(name);
  }
}

class _Tuning extends StatelessWidget {
  const _Tuning({required this.state, required this.config});

  final SessionState state;
  final SessionConfig config;

  @override
  Widget build(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();

    return SessionTuningControls(
      repeatCount: config.repeatCount,
      connectMode: config.connectMode,
      recallRounds: config.recallRounds,
      chainRecall: config.chainRecall,
      onRepeatCount: cubit.setRepeatCount,
      onConnectMode: cubit.setConnectMode,
      onRecallRounds: cubit.setRecallRounds,
      onChainRecall: cubit.setChainRecall,
      rows: <Widget>[_ReciterAndAudio(state: state, config: config)],
    );
  }
}

/// Everything a session is set up with once and then left — who recites, the
/// isti'adhah and the closing pass, the speed and the pauses, the sleep
/// timer, what is saved on the device, how the page is veiled, whether the
/// screen stays awake, and the defaults — folded behind one row that says
/// where they stand.
class _ReciterAndAudio extends StatefulWidget {
  const _ReciterAndAudio({required this.state, required this.config});

  final SessionState state;
  final SessionConfig config;

  @override
  State<_ReciterAndAudio> createState() => _ReciterAndAudioState();
}

class _ReciterAndAudioState extends State<_ReciterAndAudio> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionState state = widget.state;
    final SessionConfig config = widget.config;
    final SessionCubit cubit = context.read<SessionCubit>();
    final Reciter? reciter = state.reciter ?? state.chosenReciter;
    final DateTime? sleepAt = state.sleepAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SessionListRow(
          icon: Icons.settings_outlined,
          title: LocaleKeys.readerReciterAudioPauses.tr(),
          subtitle: joinDetails(<String>[
            if (reciter != null) _reciterName(context, reciter),
            LocaleKeys.readerSpeedValue.tr(
              args: <String>[speedLabel(config.playbackSpeed)],
            ),
            if (state.sleepTimerSet)
              sleepAt == null
                  ? LocaleKeys.sleepEndOfStep.tr()
                  : sleepTimeLabel(context, sleepAt),
          ]),
          trailing: Icon(
            _open ? Icons.expand_less : Icons.chevron_right,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(14.w, 4.h, 14.w, 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _Reciters(state: state),
                // Only before a session: the isti'adhah opens one, and a
                // session already under way has nothing left to open.
                if ((state.reciter?.hasIstiadhah ?? false) && !state.isActive)
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsetsDirectional.zero,
                    title: Text(LocaleKeys.sessionSetupPlayIstiadhah.tr()),
                    value: config.playIstiadhah,
                    onChanged: cubit.setPlayIstiadhah,
                  ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(LocaleKeys.sessionSetupFinalFullPass.tr()),
                  value: config.finalFullPass,
                  onChanged: cubit.setFinalFullPass,
                ),
                SizedBox(height: 8.h),
                SpeedAndPausesList(
                  intraBlockPauseMs: config.intraBlockPauseMs,
                  betweenRepeatPauseMs: config.betweenRepeatPauseMs,
                  betweenStepsPauseMs: config.betweenStepsPauseMs,
                  playbackSpeed: config.playbackSpeed,
                  onIntraBlockPause: cubit.setIntraBlockPause,
                  onBetweenRepeatPause: cubit.setBetweenRepeatPause,
                  onBetweenStepsPause: cubit.setBetweenStepsPause,
                  onPlaybackSpeed: cubit.setPlaybackSpeed,
                ),
                SizedBox(height: 16.h),
                if (state.isActive) _SleepTimer(state: state),
                _Downloads(state: state),
                const _MemorizationView(),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsetsDirectional.zero,
                  title: Text(LocaleKeys.playerKeepAwake.tr()),
                  value: state.keepAwake,
                  onChanged: cubit.setKeepAwake,
                ),
                // The defaults are kept on their own page; from here, these
                // values can be taken there, or the page's taken back.
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: cubit.resetToDefaults,
                        child: Text(LocaleKeys.readerResetDefaults.tr()),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: cubit.saveAsDefaults,
                        child: Text(LocaleKeys.readerSaveAsDefault.tr()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The measured summary as one quiet line, then the one button — or, when the
/// settings have changed under a running session, the two ways to take them
/// up — and under "start", the two quieter ways.
class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(18.w, 4.h, 18.w, 12.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (state.configError != null)
            Text(
              state.configError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            )
          else if (state.plan != null && state.estimatedDuration != null)
            // Step and recitation counts come from the built plan, and the
            // duration from real clip lengths — never an estimate from an
            // average ayah.
            SessionSummary(
              stepCount: state.plan!.stepCount,
              unitCount: state.plan!.unitCount,
              duration: state.estimatedDuration!.localized,
            ),
          SizedBox(height: 10.h),
          if (state.hasPendingChange)
            PendingChangeActions(
              onRestart: () {
                cubit.applyChanges(restart: true);
                Navigator.of(context).pop();
              },
              onContinue: () {
                cubit.applyChanges(restart: false);
                Navigator.of(context).pop();
              },
            )
          else if (!state.isActive) ...<Widget>[
            // Before a session: the one button.
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: Size(0, 50.r)),
              onPressed: state.canStart
                  ? () {
                      cubit.start();
                      Navigator.of(context).pop();
                    }
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(LocaleKeys.sessionStart.tr()),
            ),
            SizedBox(height: 6.h),
            _QuietWays(state: state),
          ],
        ],
      ),
    );
  }
}

/// "Start again" or "carry on from this ayah" — the two things that can be
/// done with settings changed under a running session.
class PendingChangeActions extends StatelessWidget {
  const PendingChangeActions({
    required this.onRestart,
    required this.onContinue,
    super.key,
  });

  final VoidCallback onRestart;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(
        LocaleKeys.sessionChangedBody.tr(),
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
      SizedBox(height: 8.h),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: onRestart,
              child: Text(LocaleKeys.sessionRestart.tr()),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: FilledButton(
              onPressed: onContinue,
              child: Text(LocaleKeys.sessionContinueHere.tr()),
            ),
          ),
        ],
      ),
    ],
  );
}

/// Asks what to call the form's way of working. Its own widget, so the
/// field's controller lives exactly as long as the dialog does — through
/// the closing animation, after the answer is already given.
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(LocaleKeys.presetsSaveTitle.tr()),
    content: TextField(
      controller: _name,
      autofocus: true,
      maxLength: SavedPreset.maxNameLength,
      decoration: InputDecoration(hintText: LocaleKeys.presetsSaveHint.tr()),
      onSubmitted: (String v) => Navigator.of(context).pop(v),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(LocaleKeys.commonCancel.tr()),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_name.text),
        child: Text(LocaleKeys.presetsSaveAction.tr()),
      ),
    ],
  );
}

/// Under "start", before a session: keep these settings as a way of
/// working, or recite to a listener instead of starting a recitation. A
/// wrap, not a row: on a narrow phone the second goes under the first.
class _QuietWays extends StatelessWidget {
  const _QuietWays({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        TextButton.icon(
          onPressed: () => _Presets.askName(context, cubit),
          icon: const Icon(Icons.bookmark_add_outlined),
          label: Text(LocaleKeys.presetsSave.tr()),
        ),
        // RELEASE-1.4(tasmee)
        // if (!state.tasmee)
        //   TextButton.icon(
        //     onPressed: () {
        //       cubit.startTasmee();
        //       Navigator.of(context).pop();
        //     },
        //     icon: const Icon(Icons.hearing),
        //     label: Text(LocaleKeys.tasmeeStart.tr()),
        //   ),
        // END RELEASE-1.4(tasmee)
      ],
    );
  }
}
