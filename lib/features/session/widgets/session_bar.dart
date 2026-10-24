import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/reciter_avatar.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../data/models/reciter.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../core/widgets/range_label.dart';
import '../../../domain/entities/interrupted_session.dart';
import '../../../domain/entities/review_card.dart';
import '../../../domain/entities/session_config.dart';
import '../cubit/session_cubit.dart';
import '../cubit/session_state.dart';
import 'session_sheet.dart' show sleepTimeLabel;

/// The bar at the foot of the reading view: what would play and the button
/// that plays it, and — once a session is running — the session's controls.
///
/// It slides rather than appears, and while it is away it takes no taps, so
/// the page beneath it is never dead to the touch.
class SessionBar extends StatelessWidget {
  const SessionBar({
    required this.visible,
    required this.onOpenSettings,
    super.key,
  });

  final bool visible;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12.w, 0, 12.w, 10.h),
            child: Material(
              elevation: 3,
              color: theme.colorScheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24.r),
                side: BorderSide(color: theme.colorScheme.outline),
              ),
              clipBehavior: Clip.antiAlias,
              child: BlocBuilder<SessionCubit, SessionState>(
                builder: (BuildContext context, SessionState state) =>
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          2.w,
                          4.h,
                          2.w,
                          4.h,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            if (state.gradeOffer != null) const _GradePrompt(),
                            if (state.resumeOffer != null &&
                                state.phase == SessionPhase.idle &&
                                !state.tasmee)
                              _ResumePrompt(state: state),
                            if (state.tasmee)
                              _Tasmee(state: state)
                            else
                              switch (state.phase) {
                                SessionPhase.idle => _Idle(
                                  state: state,
                                  onOpenSettings: onOpenSettings,
                                ),
                                SessionPhase.loading => const _Loading(),
                                SessionPhase.active => _Active(
                                  state: state,
                                  onOpenSettings: onOpenSettings,
                                ),
                                SessionPhase.failed => _Failed(state: state),
                              },
                          ],
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The session the app was closed in the middle of, offered back.
class _ResumePrompt extends StatelessWidget {
  const _ResumePrompt({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();
    final InterruptedSession offer = state.resumeOffer!;
    final Surah? from = state.surah(offer.config.surahNumber);
    final Surah? to = state.surah(offer.config.endSurahNumber);
    if (from == null || to == null) return const SizedBox.shrink();
    final Surah? here = state.surah(offer.at.surah);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(8.w, 6.h, 4.w, 2.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.history, color: theme.colorScheme.primary),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      LocaleKeys.resumeTitle.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      rangeLabel(
                        context,
                        from: offer.config.start,
                        to: offer.config.end,
                        fromSurah: from,
                        toSurah: to,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                    if (here != null)
                      Text(
                        LocaleKeys.resumeAt.tr(
                          args: <String>[
                            _surahName(context, here),
                            offer.at.ayah.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: LocaleKeys.resumeDismiss.tr(),
                onPressed: cubit.dismissResume,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: state.ready ? cubit.resume : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(LocaleKeys.resumeGo.tr()),
            ),
          ),
          const Divider(height: 12),
        ],
      ),
    );
  }
}

/// Reciting to a listener: how many slips are noted, the last one taken
/// back, and the end of the sitting.
class _Tasmee extends StatelessWidget {
  const _Tasmee({required this.state});

  final SessionState state;

  Future<void> _end(BuildContext context) async {
    // Taken now: ending the sitting turns the bar back into the session's,
    // and this widget — and its context — is gone by the time the dialog is
    // answered.
    final GoRouter router = GoRouter.of(context);
    final int slips = context.read<SessionCubit>().endTasmee().length;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: Text(LocaleKeys.tasmeeTitle.tr()),
        content: Text(
          slips == 0
              ? LocaleKeys.tasmeeNoSlips.tr()
              : LocaleKeys.tasmeeSlipsNoted.tr(
                  args: <String>[slips.toLocalisedString()],
                ),
        ),
        actions: <Widget>[
          if (slips > 0)
            TextButton(
              onPressed: () {
                Navigator.of(dialog).pop();
                router.pushNamed(AppRoutes.weakSpotsName);
              },
              child: Text(LocaleKeys.weakSpotsTitle.tr()),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(LocaleKeys.commonClose.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();
    // Two rows, as the playing bar has: what this is and the count above, the
    // controls below — one row does not fit a narrow phone.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 6.h, 12.w, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      LocaleKeys.tasmeeTitle.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      LocaleKeys.tasmeeHint.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                LocaleKeys.tasmeeCount.tr(
                  args: <String>[state.tasmeeMarks.length.toLocalisedString()],
                ),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
        Row(
          children: <Widget>[
            const _BackButton(),
            const Spacer(),
            IconButton(
              tooltip: LocaleKeys.tasmeeUndo.tr(),
              onPressed: state.tasmeeMarks.isEmpty
                  ? null
                  : cubit.undoTasmeeMark,
              icon: const Icon(Icons.undo),
            ),
            SizedBox(width: 4.w),
            FilledButton.tonal(
              onPressed: () => _end(context),
              child: Text(LocaleKeys.tasmeeEnd.tr()),
            ),
            SizedBox(width: 8.w),
          ],
        ),
      ],
    );
  }
}

/// "How did it go?" once a range has been recited through: three answers
/// that set when it comes back for review, and a way to leave it unanswered.
class _GradePrompt extends StatelessWidget {
  const _GradePrompt();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();

    Widget answer(Grade grade, String label, Color color) => Expanded(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(horizontal: 3.w),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color),
            padding: EdgeInsetsDirectional.symmetric(horizontal: 4.w),
          ),
          onPressed: () => cubit.grade(grade),
          child: Text(label, maxLines: 1, overflow: TextOverflow.fade),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(8.w, 6.h, 4.w, 2.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  LocaleKeys.reviewGradeQuestion.tr(),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: LocaleKeys.reviewGradeLater.tr(),
                onPressed: cubit.dismissGrade,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              answer(
                Grade.solid,
                LocaleKeys.reviewGradeSolid.tr(),
                theme.colorScheme.primary,
              ),
              answer(
                Grade.shaky,
                LocaleKeys.reviewGradeShaky.tr(),
                theme.colorScheme.secondary,
              ),
              answer(
                Grade.forgot,
                LocaleKeys.reviewGradeForgot.tr(),
                theme.colorScheme.error,
              ),
            ],
          ),
          const Divider(height: 12),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: LocaleKeys.mushafBack.tr(),
    onPressed: () => Navigator.of(context).maybePop(),
    icon: const BackButtonIcon(),
  );
}

/// Nothing playing: what a session would cover, its settings, and start.
class _Idle extends StatelessWidget {
  const _Idle({required this.state, required this.onOpenSettings});

  final SessionState state;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();
    final String? blocked = switch (state.block) {
      null => null,
      SessionBlock.noAudio => LocaleKeys.sessionNoAudioRange.tr(),
      SessionBlock.reciterLacksSurah => LocaleKeys.sessionReciterLacksRange.tr(
        args: <String>[
          context.locale.languageCode == 'ar'
              ? state.chosenReciter!.nameAr
              : state.chosenReciter!.nameEn,
        ],
      ),
    };

    return Row(
      children: <Widget>[
        const _BackButton(),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                describeRange(context, state, state.config),
                style: theme.textTheme.titleSmall,
              ),
              Text(
                blocked ?? LocaleKeys.mushafHintLongPress.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: blocked == null
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: state.ready ? onOpenSettings : null,
          tooltip: LocaleKeys.readerSessionSettings.tr(),
          icon: const Icon(Icons.tune),
        ),
        SizedBox(width: 2.w),
        FilledButton.icon(
          onPressed: state.canStart ? cubit.start : null,
          icon: const Icon(Icons.play_arrow),
          label: Text(LocaleKeys.sessionStart.tr()),
        ),
        SizedBox(width: 4.w),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const _BackButton(),
      const Spacer(),
      SizedBox.square(
        dimension: 22.r,
        child: const CircularProgressIndicator(strokeWidth: 2.5),
      ),
      const Spacer(),
      SizedBox(width: 48.w),
    ],
  );
}

/// A session is loaded: where it is, and the controls that move it.
class _Active extends StatelessWidget {
  const _Active({required this.state, required this.onOpenSettings});

  final SessionState state;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();
    final PlaybackUnit? unit = state.currentUnit;
    final int steps = state.activePlan?.stepCount ?? 0;

    // A recall round is the reader's turn, not the reciter's: the bar says
    // what is being asked, and offers the two things they may want — the
    // answer now, or a note that this is where they slip.
    if (state.recalling && !state.finished && unit != null) {
      return _Recall(state: state, unit: unit, onOpenSettings: onOpenSettings);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 8.h, 12.w, 0),
          child: Row(
            children: <Widget>[
              // Whose voice this is, as the lock screen shows it.
              if (state.reciter case final Reciter reciter) ...<Widget>[
                ReciterAvatar(reciter: reciter, diameter: 34),
                SizedBox(width: 10.w),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      state.finished
                          ? LocaleKeys.playerFinished.tr()
                          : _nowReciting(context, state, unit),
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Which time through, and which rung — under the ayah,
                    // not beside it, so neither has to be shortened.
                    if (unit != null && !state.finished)
                      Text(
                        joinDetails(<String>[
                          LocaleKeys.playerRepeatHeader.tr(
                            args: <String>[
                              unit.repeatIndex.toLocalisedString(),
                              unit.totalRepeats.toLocalisedString(),
                            ],
                          ),
                          LocaleKeys.playerStepHeader.tr(
                            args: <String>[
                              (unit.stepIndex + 1).toLocalisedString(),
                              steps.toLocalisedString(),
                            ],
                          ),
                        ]),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (state.sleepTimerSet)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: 6.w),
                  child: Tooltip(
                    message: state.sleepAt == null
                        ? LocaleKeys.sleepEndOfStep.tr()
                        : LocaleKeys.sleepUntil.tr(
                            args: <String>[
                              sleepTimeLabel(context, state.sleepAt!),
                            ],
                          ),
                    child: Icon(
                      Icons.bedtime_outlined,
                      size: 18.r,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // Three more times over this ayah: the one thing a reader asks
              // for mid-session, so it says what it does.
              if (unit != null && !state.finished && !state.recalling)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: 6.w),
                  child: _BarChip(
                    icon: Icons.repeat_one,
                    label: LocaleKeys.playerThreeMore.tr(),
                    tooltip: LocaleKeys.playerRepeatAyah.tr(),
                    onPressed: () => cubit.repeatCurrentAyah(),
                  ),
                ),
            ],
          ),
        ),
        // Where in the ladder: the steps stood on, the one being climbed.
        if (unit != null && steps > 1)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12.w, 12.h, 12.w, 0),
            child: StepsBar(
              total: steps,
              current: state.finished ? steps : unit.stepIndex,
            ),
          ),
        // Spread across the bar: the settings, then back a step, the big
        // pause, forward a step, and stop. The way out of the page is the
        // stop, which hands the bar back to the one that leaves.
        _ControlsRow(
          children: <Widget>[
            Badge(
              isLabelVisible: state.hasPendingChange,
              smallSize: 8.r,
              child: IconButton(
                onPressed: onOpenSettings,
                tooltip: LocaleKeys.readerSessionSettings.tr(),
                icon: const Icon(Icons.tune),
              ),
            ),
            IconButton(
              onPressed: cubit.previousStep,
              tooltip: LocaleKeys.playerPreviousStep.tr(),
              icon: Icon(_towardsStart(context)),
            ),
            _BigPlayPause(state: state),
            IconButton(
              onPressed: cubit.nextStep,
              tooltip: LocaleKeys.playerNextStep.tr(),
              icon: Icon(_towardsEnd(context)),
            ),
            IconButton(
              onPressed: cubit.stop,
              tooltip: LocaleKeys.playerStop.tr(),
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
      ],
    );
  }

  /// The skip glyphs are not mirrored by the framework, so in Arabic — where
  /// "previous" sits on the right and the text runs leftwards — the glyph
  /// that points right is the one that means "back", and the two are swapped.
  static IconData _towardsStart(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.skip_next
      : Icons.skip_previous;

  static IconData _towardsEnd(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
      ? Icons.skip_previous
      : Icons.skip_next;

  static String _nowReciting(
    BuildContext context,
    SessionState state,
    PlaybackUnit? unit,
  ) {
    if (unit == null) {
      return describeRange(context, state, state.activePlan?.config);
    }
    final String reference = LocaleKeys.mushafAyahReference.tr(
      args: <String>[
        _surahName(context, state.surah(unit.surahNumber)),
        unit.ayahNumber.toLocalisedString(),
      ],
    );
    // A recall gap: the silence is the reader's turn, and the bar says so —
    // otherwise it reads as the session hanging.
    return state.recalling
        ? LocaleKeys.playerRecallNow.tr(args: <String>[reference])
        : reference;
  }
}

/// The bar during a recall gap: the ayah's place, the silence as a bar, and
/// the reader's two answers — reveal it, or mark this as a place they slip.
class _Recall extends StatelessWidget {
  const _Recall({
    required this.state,
    required this.unit,
    required this.onOpenSettings,
  });

  final SessionState state;
  final PlaybackUnit unit;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();
    // The surah is on the page's own border; the bar names the ayah.
    final String reference = LocaleKeys.commonAyahNumber.tr(
      args: <String>[unit.ayahNumber.toLocalisedString()],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 8.h, 12.w, 0),
          child: Row(
            children: <Widget>[
              TileIcon(
                Icons.mic_none,
                background: AppColors.gold.withValues(alpha: 0.2),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      LocaleKeys.playerRecallNow.tr(args: <String>[reference]),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      LocaleKeys.playerRecallHint.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // The silence itself, as a calm line that fills while it lasts — no
        // count, no clock.
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 14.h, 12.w, 0),
          child: _RecallProgress(
            key: ValueKey<Object>(unit),
            gap: state.recallGap,
            running: state.playing,
          ),
        ),
        // "Reveal" and "I stumble here" sit in the row, within reach, either
        // side of the pause.
        _ControlsRow(
          children: <Widget>[
            IconButton(
              onPressed: onOpenSettings,
              tooltip: LocaleKeys.readerSessionSettings.tr(),
              icon: const Icon(Icons.tune),
            ),
            Flexible(
              child: _BarChip(
                icon: Icons.visibility_outlined,
                label: LocaleKeys.playerRecallReveal.tr(),
                tooltip: LocaleKeys.playerRecallReveal.tr(),
                onPressed: cubit.revealRecall,
              ),
            ),
            _BigPlayPause(state: state),
            Flexible(
              child: _BarChip(
                icon: Icons.flag_outlined,
                label: LocaleKeys.mushafStumbleHere.tr(),
                tooltip: LocaleKeys.mushafStumbleHere.tr(),
                onPressed: () => _markStumble(context, cubit),
              ),
            ),
            IconButton(
              onPressed: cubit.stop,
              tooltip: LocaleKeys.playerStop.tr(),
              icon: const Icon(Icons.stop),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _markStumble(BuildContext context, SessionCubit cubit) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String said = LocaleKeys.mushafStumbleMarked.tr();
    await cubit.markStumble(unit.ref);
    messenger.showSnackBar(SnackBar(content: Text(said)));
  }
}

/// The bar's row of controls, spread from edge to edge with the big button
/// in the middle.
class _ControlsRow extends StatelessWidget {
  const _ControlsRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(top: 10.h),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: children,
    ),
  );
}

/// The one big button of the bar: a solid 56 circle that plays and pauses.
class _BigPlayPause extends StatelessWidget {
  const _BigPlayPause({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: context.read<SessionCubit>().togglePlayPause,
      tooltip: state.playing
          ? LocaleKeys.playerPause.tr()
          : LocaleKeys.playerPlay.tr(),
      iconSize: 28.r,
      style: IconButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        minimumSize: Size(56.r, 56.r),
        fixedSize: Size(56.r, 56.r),
      ),
      icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
    );
  }
}

/// A small outlined chip on the bar — "three more times", "reveal it",
/// "I stumble here": an action that says what it does.
class _BarChip extends StatelessWidget {
  const _BarChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: ActionChip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsetsDirectional.symmetric(horizontal: 4.w),
      avatar: Icon(icon, size: 16.r),
      tooltip: tooltip,
      onPressed: onPressed,
      label: Text(label),
    ),
  );
}

/// The silence of a recall gap as a gold line filling over its length; it
/// holds while the session is paused.
class _RecallProgress extends StatefulWidget {
  const _RecallProgress({required this.gap, required this.running, super.key});

  final Duration? gap;
  final bool running;

  @override
  State<_RecallProgress> createState() => _RecallProgressState();
}

class _RecallProgressState extends State<_RecallProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: widget.gap ?? const Duration(seconds: 1),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_RecallProgress old) {
    super.didUpdateWidget(old);
    if (widget.gap != null && widget.gap != old.gap) {
      _fill.duration = widget.gap;
    }
    _sync();
  }

  void _sync() {
    if (widget.running && widget.gap != null) {
      if (!_fill.isAnimating) _fill.forward();
    } else {
      _fill.stop();
    }
  }

  @override
  void dispose() {
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fill,
    builder: (BuildContext context, _) => ProgressBar(value: _fill.value),
  );
}

class _Failed extends StatelessWidget {
  const _Failed({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SessionCubit cubit = context.read<SessionCubit>();
    // What the listener is told. The offline line is the one that actually
    // gets read: a surah nobody downloaded, opened on a train.
    final String message = switch (state.failure ?? SessionFailure.unknown) {
      SessionFailure.audioUnreachable => LocaleKeys.playerErrorOffline.tr(),
      SessionFailure.configuration => LocaleKeys.playerErrorConfig.tr(),
      SessionFailure.unknown => LocaleKeys.playerErrorUnknown.tr(),
    };

    return Row(
      children: <Widget>[
        const _BackButton(),
        Expanded(
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(vertical: 6.h),
            child: Text(message, style: theme.textTheme.bodySmall),
          ),
        ),
        TextButton(
          onPressed: cubit.start,
          child: Text(LocaleKeys.commonRetry.tr()),
        ),
        IconButton(
          onPressed: cubit.stop,
          tooltip: LocaleKeys.commonClose.tr(),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

String _surahName(BuildContext context, Surah? surah) => surah == null
    ? ''
    : (context.locale.languageCode == 'ar' ? surah.nameAr : surah.nameEn);

/// A range in words: «سورة البقرة كاملة», «سورة البقرة · الآيات ٥ - ٢٠»,
/// «من الإخلاص ٣ إلى الفلق ٢» — in the locale's own numerals.
String describeRange(
  BuildContext context,
  SessionState state,
  SessionConfig? config,
) {
  if (config == null) return '';
  final Surah? first = state.surah(config.surahNumber);
  final Surah? last = state.surah(config.endSurahNumber);
  final String from = _surahName(context, first);

  if (config.spansSurahs) {
    return LocaleKeys.sessionRangeCross.tr(
      args: <String>[
        from,
        config.startAyah.toLocalisedString(),
        _surahName(context, last),
        config.endAyah.toLocalisedString(),
      ],
    );
  }
  if (config.startAyah == 1 && config.endAyah == first?.ayahCount) {
    return LocaleKeys.sessionRangeWhole.tr(args: <String>[from]);
  }
  if (config.startAyah == config.endAyah) {
    return LocaleKeys.sessionRangeSingle.tr(
      args: <String>[from, config.startAyah.toLocalisedString()],
    );
  }
  return LocaleKeys.sessionRangeSame.tr(
    args: <String>[
      from,
      config.startAyah.toLocalisedString(),
      config.endAyah.toLocalisedString(),
    ],
  );
}
