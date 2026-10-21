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
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/mutashabihat_cubit.dart';
import '../widgets/compared_ayah_card.dart';

/// Every phrase the Quran repeats across its ayahs, one card each, in the
/// order the mushaf first reaches it; narrowed to one surah on request.
class MutashabihatScreen extends StatelessWidget {
  const MutashabihatScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<MutashabihatCubit>(
    create: (_) => sl<MutashabihatCubit>()..load(),
    child: Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.mutashabihatTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<MutashabihatCubit, MutashabihatState>(
          builder: (BuildContext context, MutashabihatState state) {
            if (state.status.isLoading || state.status == LoadStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status.isFailure) {
              return ErrorView(
                message: state.errorMessage ?? LocaleKeys.commonError.tr(),
                onRetry: () => context.read<MutashabihatCubit>().load(),
              );
            }
            if (state.entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: EdgeInsetsDirectional.all(24.r),
                  child: Text(
                    LocaleKeys.mutashabihatEmpty.tr(),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            final List<PhraseEntry> shown = state.shown;
            return ListView.builder(
              padding: EdgeInsetsDirectional.all(12.r),
              // The heading, then a card per phrase, then the source.
              itemCount: shown.length + 2,
              itemBuilder: (BuildContext context, int i) {
                if (i == 0) return _Heading(state: state);
                if (i == shown.length + 1) {
                  return Padding(
                    padding: EdgeInsetsDirectional.only(top: 8.h),
                    child: Text(
                      shown.isEmpty
                          ? LocaleKeys.mutashabihatNoneInSurah.tr()
                          : LocaleKeys.similarSource.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                final PhraseEntry entry = shown[i - 1];
                return _PhraseCard(key: ValueKey<int>(entry.id), entry: entry);
              },
            );
          },
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.state});

  final MutashabihatState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    final MutashabihatCubit cubit = context.read<MutashabihatCubit>();
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(4.w, 0, 4.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            LocaleKeys.mutashabihatIntro.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: <Widget>[
              Text(
                LocaleKeys.mutashabihatSurah.tr(),
                style: theme.textTheme.labelLarge,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: DropdownButton<int?>(
                  key: const ValueKey<String>('mutashabihat-surah'),
                  isExpanded: true,
                  value: state.surahFilter,
                  onChanged: cubit.filterBySurah,
                  items: <DropdownMenuItem<int?>>[
                    DropdownMenuItem<int?>(
                      child: Text(LocaleKeys.mutashabihatAllSurahs.tr()),
                    ),
                    for (final Surah s in state.surahs)
                      DropdownMenuItem<int?>(
                        value: s.number,
                        child: Text(
                          '${s.number.toLocalisedString()}. '
                          '${arabic ? s.nameAr : s.nameEn}',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Text(
            LocaleKeys.mutashabihatShown.tr(
              args: <String>[state.shown.length.toLocalisedString()],
            ),
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _PhraseCard extends StatefulWidget {
  const _PhraseCard({required this.entry, super.key});

  final PhraseEntry entry;

  @override
  State<_PhraseCard> createState() => _PhraseCardState();
}

class _PhraseCardState extends State<_PhraseCard> {
  late Future<List<Word>> _words;

  @override
  void initState() {
    super.initState();
    _words = context.read<MutashabihatCubit>().wordsOf(widget.entry);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    final PhraseEntry entry = widget.entry;
    String name(Surah s) => arabic ? s.nameAr : s.nameEn;
    return Card(
      margin: EdgeInsetsDirectional.only(bottom: 10.h),
      child: InkWell(
        onTap: () => context.pushNamed(
          AppRoutes.mutashabihatPhraseName,
          extra: entry.id,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(12.w, 10.h, 8.w, 12.h),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    FutureBuilder<List<Word>>(
                      future: _words,
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<List<Word>> snap,
                          ) {
                            final List<Word> words =
                                snap.data ?? const <Word>[];
                            // Room held while the words load, so the list
                            // does not jump under the reader's thumb.
                            if (words.isEmpty) return SizedBox(height: 36.h);
                            return QuranWords(words: words);
                          },
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      LocaleKeys.mutashabihatFirstAt.tr(
                        args: <String>[
                          LocaleKeys.mushafAyahReference.tr(
                            args: <String>[
                              name(entry.surahs.first),
                              entry.first.ref.ayah.toLocalisedString(),
                            ],
                          ),
                        ],
                      ),
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(
                      LocaleKeys.mutashabihatCounts.tr(
                        args: <String>[
                          entry.ayahCount.toLocalisedString(),
                          entry.surahs.length.toLocalisedString(),
                        ],
                      ),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      entry.surahs.map(name).join(arabic ? '، ' : ', '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
