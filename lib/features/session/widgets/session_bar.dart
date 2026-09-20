import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../domain/entities/session_config.dart';
import '../cubit/session_cubit.dart';
import '../cubit/session_state.dart';

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
              elevation: 6,
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(18.r),
              clipBehavior: Clip.antiAlias,
              child: BlocBuilder<SessionCubit, SessionState>(
                builder: (BuildContext context, SessionState state) =>
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsetsDirectional.symmetric(
                          horizontal: 6.w,
                          vertical: 4.h,
                        ),
                        child: switch (state.phase) {
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 6.h, 12.w, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  state.finished
                      ? LocaleKeys.playerFinished.tr()
                      : _nowReciting(context, state, unit),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (unit != null && !state.finished)
                // The repeat counter: which time through, of how many.
                Text(
                  '${LocaleKeys.playerRepeatHeader.tr(args: <String>[unit.repeatIndex.toLocalisedString(), unit.totalRepeats.toLocalisedString()])}'
                  ' · '
                  '${LocaleKeys.playerStepHeader.tr(args: <String>[(unit.stepIndex + 1).toLocalisedString(), steps.toLocalisedString()])}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: <Widget>[
            const _BackButton(),
            const Spacer(),
            IconButton(
              onPressed: cubit.previousStep,
              tooltip: LocaleKeys.playerPreviousStep.tr(),
              icon: Icon(_towardsStart(context)),
            ),
            IconButton.filled(
              onPressed: cubit.togglePlayPause,
              iconSize: 30.r,
              tooltip: state.playing
                  ? LocaleKeys.playerPause.tr()
                  : LocaleKeys.playerPlay.tr(),
              icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
            ),
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
            const Spacer(),
            Badge(
              isLabelVisible: state.hasPendingChange,
              smallSize: 8.r,
              child: IconButton(
                onPressed: onOpenSettings,
                tooltip: LocaleKeys.readerSessionSettings.tr(),
                icon: const Icon(Icons.tune),
              ),
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
    return LocaleKeys.mushafAyahReference.tr(
      args: <String>[
        _surahName(context, state.surah(unit.surahNumber)),
        unit.ayahNumber.toLocalisedString(),
      ],
    );
  }
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
