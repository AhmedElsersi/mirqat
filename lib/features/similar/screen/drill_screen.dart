import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/state/load_status.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;
import '../../surah_list/widgets/error_view.dart';
import '../cubit/drill_cubit.dart';
import '../widgets/compared_ayah_card.dart';

/// The mutashabihat drill for one phrase: each ayah it is in, shown as far
/// as the phrase reaches — which is it, and how does it go on?
class DrillScreen extends StatelessWidget {
  const DrillScreen({required this.phraseId, super.key});

  final int phraseId;

  @override
  Widget build(BuildContext context) => BlocProvider<DrillCubit>(
    create: (_) => sl<DrillCubit>()..load(phraseId),
    child: BlocBuilder<DrillCubit, DrillState>(
      builder: (BuildContext context, DrillState state) => Scaffold(
        appBar: AppBar(
          // The round under the title, and the rounds as steps at the end:
          // where the drill stands, without a score.
          title: state.round == null
              ? Text(LocaleKeys.drillTitle.tr())
              : _RoundTitle(state: state),
          actions: <Widget>[
            if (state.round != null && state.rounds.length > 1)
              Padding(
                padding: EdgeInsetsDirectional.only(end: 16.w),
                child: SizedBox(
                  width: 90.w,
                  child: Center(
                    child: StepsBar(
                      total: state.rounds.length,
                      current: state.index,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: DesktopWidth(
          child: Builder(
            builder: (BuildContext context) {
              if (state.status.isLoading ||
                  state.status == LoadStatus.initial) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state.status.isFailure) {
                return ErrorView(
                  message: state.errorMessage ?? LocaleKeys.commonError.tr(),
                  onRetry: () => context.read<DrillCubit>().load(phraseId),
                );
              }
              final DrillRound? round = state.round;
              if (round == null) return _Done(state: state);
              return _Round(state: state, round: round);
            },
          ),
        ),
      ),
    ),
  );
}

class _RoundTitle extends StatelessWidget {
  const _RoundTitle({required this.state});

  final DrillState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          LocaleKeys.drillTitle.tr(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          LocaleKeys.drillRound.tr(
            args: <String>[
              (state.index + 1).toLocalisedString(),
              state.rounds.length.toLocalisedString(),
            ],
          ),
          style: theme.textTheme.titleSmall,
        ),
      ],
    );
  }
}

String _refName(BuildContext context, Surah surah, AyahRef ref) =>
    LocaleKeys.mushafAyahReference.tr(
      args: <String>[
        context.locale.languageCode == 'ar' ? surah.nameAr : surah.nameEn,
        ref.ayah.toLocalisedString(),
      ],
    );

class _Round extends StatelessWidget {
  const _Round({required this.state, required this.round});

  final DrillState state;
  final DrillRound round;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DrillCubit cubit = context.read<DrillCubit>();
    final bool shown = state.stage == DrillStage.revealed;
    final bool picked = state.stage != DrillStage.identify;
    return ListView(
      padding: EdgeInsetsDirectional.all(16.r),
      children: <Widget>[
        AppCard(
          padding: EdgeInsetsDirectional.fromSTEB(18.w, 22.h, 18.w, 22.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                LocaleKeys.drillSharedPhrase.tr(),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 10.h),
              if (round.before.isNotEmpty) ...<Widget>[
                QuranWords(words: round.before, faint: true, centered: true),
                SizedBox(height: 8.h),
              ],
              QuranWords(
                words: round.ayah.words,
                fontSize: 24.sp,
                centered: true,
                veiled: shown ? null : round.isHeldBack,
                // The shared phrase is tinted, before the reveal and after
                // it: once the rest is shown, where the tint stops is where
                // this ayah goes its own way.
                tint: (Word w) => !round.isHeldBack(w) && !w.isMarker
                    ? WordTint.shared
                    : WordTint.none,
              ),
              if (round.after.isNotEmpty) ...<Widget>[
                SizedBox(height: 8.h),
                QuranWords(
                  words: round.after,
                  centered: true,
                  veiled: shown ? null : (Word _) => true,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(4.w, 24.h, 4.w, 12.h),
          child: Text(
            picked
                ? (state.pickedRight
                          ? LocaleKeys.drillRight
                          : LocaleKeys.drillItIs)
                      .tr(
                        args: <String>[
                          _refName(context, round.ayah.surah, round.ayah.ref),
                        ],
                      )
                : LocaleKeys.drillWhich.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: picked ? theme.colorScheme.primary : null,
            ),
          ),
        ),
        // Each choice a card: the surah's number, the ayah named, and a
        // radio at its end. The one picked keeps its outline afterwards.
        for (final DrillChoice c in round.choices)
          Padding(
            padding: EdgeInsetsDirectional.only(bottom: 10.h),
            child: AppCard(
              padding: EdgeInsetsDirectional.fromSTEB(14.w, 10.h, 14.w, 10.h),
              border: state.picked == c.ref ? theme.colorScheme.primary : null,
              onTap: picked ? null : () => cubit.pick(c.ref),
              child: Row(
                children: <Widget>[
                  NumberDiamond(number: c.surah.number),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      _refName(context, c.surah, c.ref),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Icon(
                    state.picked == c.ref
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: state.picked == c.ref
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        // What comes after the choice is said from the start, and the
        // reveal waits under it until a choice is made.
        if (!shown) ...<Widget>[
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(0, 12.h, 0, 10.h),
            child: Text(
              LocaleKeys.drillContinue.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: Size(0, 50.r)),
            onPressed: picked ? cubit.reveal : null,
            icon: const Icon(Icons.visibility_outlined),
            label: Text(LocaleKeys.drillShow.tr()),
          ),
        ] else ...<Widget>[
          SizedBox(height: 12.h),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => cubit.grade(slipped: true),
                  child: Text(LocaleKeys.drillSlipped.tr()),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: FilledButton(
                  onPressed: () => cubit.grade(slipped: false),
                  child: Text(LocaleKeys.drillHadIt.tr()),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          TextButton.icon(
            onPressed: () => context.pushNamed(
              AppRoutes.mushafName,
              extra: MushafArgs(
                initialAyah: round.ayah.ref,
                session: SessionRequest(
                  from: round.ayah.ref,
                  to: round.ayah.ref,
                  preset: SessionPreset.listen,
                  autostart: true,
                ),
              ),
            ),
            icon: const Icon(Icons.headphones_outlined),
            label: Text(LocaleKeys.similarListen.tr()),
          ),
        ],
      ],
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({required this.state});

  final DrillState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              LocaleKeys.drillDone.tr(),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              state.slips == 0
                  ? LocaleKeys.drillNoSlips.tr()
                  : LocaleKeys.drillSlips.tr(
                      args: <String>[state.slips.toLocalisedString()],
                    ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.h),
            FilledButton(
              onPressed: context.read<DrillCubit>().restart,
              child: Text(LocaleKeys.drillAgain.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
