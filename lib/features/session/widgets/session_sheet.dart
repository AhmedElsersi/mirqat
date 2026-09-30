import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/duration_extensions.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../core/widgets/session_controls.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/session_config.dart';
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
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scroll) =>
          BlocBuilder<SessionCubit, SessionState>(
            builder: (BuildContext context, SessionState state) {
              final SessionConfig? config = state.config;
              if (config == null) return const SizedBox.shrink();
              return Column(
                children: <Widget>[
                  _Header(),
                  const Divider(height: 1),
                  Expanded(
                    // A column in a scroll view, not a lazy list: the form
                    // is short, and a slider scrolled out of a lazy list
                    // loses the drag that was moving it.
                    child: SingleChildScrollView(
                      controller: scroll,
                      padding: EdgeInsetsDirectional.all(16.r),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (state.block != null) _BlockNotice(state: state),
                          _Reciters(state: state),
                          _Range(state: state, config: config),
                          _Downloads(state: state),
                          _Tuning(config: config),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _Footer(state: state),
                ],
              );
            },
          ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(16.w, 0, 8.w, 8.h),
    child: Row(
      children: <Widget>[
        Expanded(
          child: Text(
            LocaleKeys.readerSessionSettings.tr(),
            style: Theme.of(context).textTheme.titleMedium,
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

    // One field, not a list: ten reciters as radio rows are a screen of
    // scrolling before the settings that matter, and the next reciter added
    // on the CDN would make it longer still. The field shows who is chosen,
    // portrait and both names; the menu shows everyone the same way.
    return SetupSection(
      label: LocaleKeys.settingsReciter.tr(),
      child: DropdownButtonFormField<String>(
        // Keyed by the choice, so a reciter picked elsewhere — the settings
        // default, a session that switched — is what the field shows.
        key: ValueKey<String?>(current?.id),
        initialValue: current?.id,
        isExpanded: true,
        // Entries size to their two lines, and to a third for the reason a
        // reciter cannot be picked.
        itemHeight: null,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          contentPadding: EdgeInsetsDirectional.symmetric(
            horizontal: 12.w,
            vertical: 8.h,
          ),
        ),
        items: <DropdownMenuItem<String>>[
          for (final Reciter reciter in state.reciters)
            DropdownMenuItem<String>(
              value: reciter.id,
              // A reciter who has not recorded the whole range cannot be
              // picked for it; they stay listed so it is clear why.
              enabled: available.contains(reciter),
              child: _ReciterEntry(
                reciter: reciter,
                enabled: available.contains(reciter),
              ),
            ),
        ],
        // What the closed field shows: the chosen one, without the reason
        // line, which only belongs in the menu.
        selectedItemBuilder: (BuildContext context) => <Widget>[
          for (final Reciter reciter in state.reciters)
            _ReciterEntry(reciter: reciter, enabled: true, inField: true),
        ],
        onChanged: (String? id) {
          final Reciter? picked = state.reciters
              .where((Reciter r) => r.id == id)
              .firstOrNull;
          if (picked != null) cubit.setReciter(picked);
        },
      ),
    );
  }
}

/// A reciter as the field and its menu draw them: the portrait, the Arabic
/// name over the English one, and — in the menu, for one who cannot be
/// picked — why.
class _ReciterEntry extends StatelessWidget {
  const _ReciterEntry({
    required this.reciter,
    required this.enabled,
    this.inField = false,
  });

  final Reciter reciter;
  final bool enabled;
  final bool inField;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    // In the field, one line: the input has a single line's height, and
    // both names still read — Arabic first, English after it, smaller.
    if (inField) {
      return Row(
        children: <Widget>[
          ReciterAvatar(reciter: reciter, diameter: 28),
          SizedBox(width: 10.w),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: reciter.nameAr,
                style: theme.textTheme.titleSmall,
                children: <InlineSpan>[
                  TextSpan(
                    text: '  ${reciter.nameEn}',
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: 6.h),
        child: Row(
          children: <Widget>[
            ReciterAvatar(reciter: reciter, diameter: 40),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reciter.nameAr,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    reciter.nameEn,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!enabled)
                    Text(
                      LocaleKeys.sessionReciterLacksRange.tr(
                        args: <String>[_reciterName(context, reciter)],
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      maxLines: 2,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// From a surah and an ayah to a surah and an ayah. The end may be in a later
/// surah than the start, never an earlier one.
class _Range extends StatelessWidget {
  const _Range({required this.state, required this.config});

  final SessionState state;
  final SessionConfig config;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();

    return SetupSection(
      label: LocaleKeys.sessionSetupRange.tr(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RangeEnd(
            label: LocaleKeys.sessionSetupFrom.tr(),
            surahs: state.surahs,
            value: config.start,
            onChanged: cubit.setStart,
            isEnd: false,
          ),
          SizedBox(height: 12.h),
          _RangeEnd(
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
          if (!state.rangeChosen && !state.isActive)
            Padding(
              padding: EdgeInsetsDirectional.only(top: 8.h),
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
      ),
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
      key: ValueKey<String>(isEnd ? 'session-to' : 'session-from'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        SizedBox(height: 4.h),
        Row(
          children: <Widget>[
            Expanded(
              flex: 3,
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
            Expanded(
              flex: 2,
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

class _Tuning extends StatelessWidget {
  const _Tuning({required this.config});

  final SessionConfig config;

  @override
  Widget build(BuildContext context) {
    final SessionCubit cubit = context.read<SessionCubit>();
    final SessionState state = context.watch<SessionCubit>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SessionTuningControls(
          repeatCount: config.repeatCount,
          connectMode: config.connectMode,
          intraBlockPauseMs: config.intraBlockPauseMs,
          betweenRepeatPauseMs: config.betweenRepeatPauseMs,
          betweenStepsPauseMs: config.betweenStepsPauseMs,
          playbackSpeed: config.playbackSpeed,
          finalFullPass: config.finalFullPass,
          onRepeatCount: cubit.setRepeatCount,
          onConnectMode: cubit.setConnectMode,
          onIntraBlockPause: cubit.setIntraBlockPause,
          onBetweenRepeatPause: cubit.setBetweenRepeatPause,
          onBetweenStepsPause: cubit.setBetweenStepsPause,
          onPlaybackSpeed: cubit.setPlaybackSpeed,
          onFinalFullPass: cubit.setFinalFullPass,
        ),
        // Only before a session: the isti'adhah opens one, and a session that
        // is already under way has nothing left to open.
        if ((state.reciter?.hasIstiadhah ?? false) && !state.isActive)
          SwitchListTile.adaptive(
            contentPadding: EdgeInsetsDirectional.zero,
            title: Text(LocaleKeys.sessionSetupPlayIstiadhah.tr()),
            value: config.playIstiadhah,
            onChanged: cubit.setPlayIstiadhah,
          ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsetsDirectional.zero,
          title: Text(LocaleKeys.playerKeepAwake.tr()),
          value: state.keepAwake,
          onChanged: cubit.setKeepAwake,
        ),
      ],
    );
  }
}

/// The measured summary, then what can be done with these settings: keep them
/// as defaults — or, when they have changed under a running session, take
/// them up.
class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();

    return Padding(
      padding: EdgeInsetsDirectional.all(16.r),
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
          SizedBox(height: 12.h),
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
          else
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
                  child: FilledButton.tonal(
                    onPressed: cubit.saveAsDefaults,
                    child: Text(LocaleKeys.readerSaveAsDefault.tr()),
                  ),
                ),
              ],
            ),
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
