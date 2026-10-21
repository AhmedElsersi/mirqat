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
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.drillTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<DrillCubit, DrillState>(
          builder: (BuildContext context, DrillState state) {
            if (state.status.isLoading || state.status == LoadStatus.initial) {
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
  );
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
    return ListView(
      padding: EdgeInsetsDirectional.all(16.r),
      children: <Widget>[
        Text(
          LocaleKeys.drillRound.tr(
            args: <String>[
              (state.index + 1).toLocalisedString(),
              state.rounds.length.toLocalisedString(),
            ],
          ),
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 8.h),
        Card(
          margin: EdgeInsetsDirectional.zero,
          child: Padding(
            padding: EdgeInsetsDirectional.all(14.r),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (round.before.isNotEmpty) ...<Widget>[
                  QuranWords(words: round.before, faint: true),
                  SizedBox(height: 8.h),
                ],
                QuranWords(
                  words: round.ayah.words,
                  fontSize: 24.sp,
                  veiled: shown ? null : round.isHeldBack,
                  // Once shown, what was held back is marked: where this
                  // ayah goes its own way.
                  tint: (Word w) => shown && round.isHeldBack(w) && !w.isMarker
                      ? WordTint.highlighted
                      : WordTint.none,
                ),
                if (round.after.isNotEmpty) ...<Widget>[
                  SizedBox(height: 8.h),
                  QuranWords(
                    words: round.after,
                    veiled: shown ? null : (Word _) => true,
                    tint: (Word w) => shown && !w.isMarker
                        ? WordTint.highlighted
                        : WordTint.none,
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: 16.h),
        ...switch (state.stage) {
          DrillStage.identify => <Widget>[
            Text(
              LocaleKeys.drillWhich.tr(),
              style: theme.textTheme.titleMedium,
            ),
            SizedBox(height: 8.h),
            // Each choice a card: the surah's number, and the ayah named.
            for (final DrillChoice c in round.choices)
              Padding(
                padding: EdgeInsetsDirectional.only(bottom: 10.h),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size.fromHeight(60.r),
                    alignment: AlignmentDirectional.centerStart,
                    padding: EdgeInsetsDirectional.symmetric(horizontal: 12.w),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18.r),
                    ),
                  ),
                  onPressed: () => cubit.pick(c.ref),
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
                    ],
                  ),
                ),
              ),
          ],
          DrillStage.recite || DrillStage.revealed => <Widget>[
            Text(
              (state.pickedRight ? LocaleKeys.drillRight : LocaleKeys.drillItIs)
                  .tr(
                    args: <String>[
                      _refName(context, round.ayah.surah, round.ayah.ref),
                    ],
                  ),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: 6.h),
            if (!shown) ...<Widget>[
              Text(LocaleKeys.drillContinue.tr()),
              SizedBox(height: 12.h),
              FilledButton(
                onPressed: cubit.reveal,
                child: Text(LocaleKeys.drillShow.tr()),
              ),
            ] else ...<Widget>[
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
          DrillStage.done => const <Widget>[],
        },
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
