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
import '../../surah_list/widgets/error_view.dart';
import '../cubit/phrase_cubit.dart';
import '../cubit/similar_cubit.dart';
import '../widgets/compared_ayah_card.dart';

/// One shared phrase, and below it every ayah it occurs in, surah by surah,
/// each with the phrase marked — where the ayahs agree, and where they part.
class PhraseScreen extends StatelessWidget {
  const PhraseScreen({required this.phraseId, super.key});

  final int phraseId;

  @override
  Widget build(BuildContext context) => BlocProvider<PhraseCubit>(
    create: (_) => sl<PhraseCubit>()..load(phraseId),
    child: Scaffold(
      appBar: AppBar(
        title: Text(LocaleKeys.mutashabihatPhraseTitle.tr()),
        actions: <Widget>[
          IconButton(
            tooltip: LocaleKeys.drillTitle.tr(),
            onPressed: () => context.pushNamed(
              AppRoutes.mutashabihatDrillName,
              extra: phraseId,
            ),
            icon: const Icon(Icons.quiz_outlined),
          ),
        ],
      ),
      body: DesktopWidth(
        child: BlocBuilder<PhraseCubit, PhraseState>(
          builder: (BuildContext context, PhraseState state) {
            if (state.status.isLoading || state.status == LoadStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status.isFailure) {
              return ErrorView(
                message: state.errorMessage ?? LocaleKeys.commonError.tr(),
                onRetry: () => context.read<PhraseCubit>().load(phraseId),
              );
            }
            final ThemeData theme = Theme.of(context);
            final bool arabic = context.locale.languageCode == 'ar';
            return ListView(
              padding: EdgeInsetsDirectional.all(12.r),
              children: <Widget>[
                Card(
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                  margin: EdgeInsetsDirectional.only(bottom: 8.h),
                  child: Padding(
                    padding: EdgeInsetsDirectional.all(14.r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (state.words.isNotEmpty)
                          QuranWords(words: state.words, fontSize: 26.sp),
                        SizedBox(height: 8.h),
                        Text(
                          LocaleKeys.mutashabihatCounts.tr(
                            args: <String>[
                              state.ayahCount.toLocalisedString(),
                              state.groups.length.toLocalisedString(),
                            ],
                          ),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final PhraseGroup group in state.groups) ...<Widget>[
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      4.w,
                      12.h,
                      4.w,
                      6.h,
                    ),
                    child: Text(
                      LocaleKeys.mutashabihatInSurah.tr(
                        args: <String>[
                          arabic ? group.surah.nameAr : group.surah.nameEn,
                          group.ayahs.length.toLocalisedString(),
                        ],
                      ),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  for (final ComparedAyah ayah in group.ayahs)
                    ComparedAyahCard(item: ayah),
                ],
                SizedBox(height: 8.h),
                Text(
                  LocaleKeys.similarSource.tr(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}
