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
import '../../../core/widgets/panel.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../surah_list/widgets/error_view.dart';
import '../cubit/mutashabihat_cubit.dart';
import '../widgets/compared_ayah_card.dart';

/// Every phrase the Quran repeats across its ayahs, one card each, in the
/// order the mushaf first reaches it; narrowed to one surah on request.
///
/// The phrase itself leads each card — it is what the reader is looking for —
/// and the drill that uses it is on the card, not two screens away.
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
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 24.h),
              // The heading, then a card per phrase, then the source.
              itemCount: shown.length + 2,
              itemBuilder: (BuildContext context, int i) {
                if (i == 0) return _Heading(state: state);
                if (i == shown.length + 1) {
                  return Padding(
                    padding: EdgeInsetsDirectional.only(top: 12.h),
                    child: AppNote(
                      shown.isEmpty
                          ? LocaleKeys.mutashabihatNoneInSurah.tr()
                          : LocaleKeys.similarSource.tr(),
                      icon: shown.isEmpty
                          ? Icons.info_outline
                          : Icons.bookmarks_outlined,
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
    final Surah? chosen = state.surahFilter == null
        ? null
        : state.surahs
              .where((Surah s) => s.number == state.surahFilter)
              .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          LocaleKeys.mutashabihatIntro.tr(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 12.h),
        // The chips fill the row; the count keeps to its end.
        Row(
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: <Widget>[
                  ChoiceChip(
                    selected: state.surahFilter == null,
                    onSelected: (_) => cubit.filterBySurah(null),
                    label: Text(LocaleKeys.mutashabihatAllSurahs.tr()),
                  ),
                  ActionChip(
                    key: const ValueKey<String>('mutashabihat-surah'),
                    avatar: const Icon(Icons.filter_list),
                    label: Text(
                      chosen == null
                          ? LocaleKeys.mutashabihatSurah.tr()
                          : (arabic ? chosen.nameAr : chosen.nameEn),
                    ),
                    onPressed: () => _pickSurah(context, state, cubit),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              LocaleKeys.mutashabihatShown.tr(
                args: <String>[state.shown.length.toLocalisedString()],
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  /// The 114 surahs as a sheet rather than a dropdown: a dropdown over a
  /// hundred rows opens as a wall over the list it filters.
  Future<void> _pickSurah(
    BuildContext context,
    MutashabihatState state,
    MutashabihatCubit cubit,
  ) async {
    final bool arabic = context.locale.languageCode == 'ar';
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: state.surahs.length,
          itemBuilder: (BuildContext context, int i) {
            final Surah s = state.surahs[i];
            return ListTile(
              selected: s.number == state.surahFilter,
              title: Text(
                '${s.number.toLocalisedString()}. '
                '${arabic ? s.nameAr : s.nameEn}',
              ),
              onTap: () => Navigator.of(sheet).pop(s.number),
            );
          },
        ),
      ),
    );
    if (picked != null) cubit.filterBySurah(picked);
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

  static String _surahLine(
    PhraseEntry entry,
    String Function(Surah) name, {
    required bool arabic,
  }) {
    final List<String> names = entry.surahs.take(3).map(name).toList();
    if (entry.surahs.length > 3) {
      names.add(LocaleKeys.mutashabihatAndOthers.tr());
    }
    return names.join(arabic ? '، ' : ', ');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    final PhraseEntry entry = widget.entry;
    String name(Surah s) => arabic ? s.nameAr : s.nameEn;

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 10.h),
      child: AppCard(
        padding: EdgeInsetsDirectional.all(16.r),
        onTap: () => context.pushNamed(
          AppRoutes.mutashabihatPhraseName,
          extra: entry.id,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            FutureBuilder<List<Word>>(
              future: _words,
              builder: (BuildContext context, AsyncSnapshot<List<Word>> snap) {
                final List<Word> words = snap.data ?? const <Word>[];
                // Room held while the words load, so the list does not
                // jump under the reader's thumb.
                if (words.isEmpty) return SizedBox(height: 36.h);
                return QuranWords(words: words, fontSize: 21.sp);
              },
            ),
            SizedBox(height: 12.h),
            Row(
              children: <Widget>[
                Flexible(
                  child: AppTag(
                    gold: true,
                    label: LocaleKeys.mutashabihatAyahsTag.tr(
                      args: <String>[entry.ayahCount.toLocalisedString()],
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                Flexible(
                  child: AppTag(
                    label: LocaleKeys.mutashabihatSurahsTag.tr(
                      args: <String>[entry.surahs.length.toLocalisedString()],
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: BoxConstraints.tightFor(
                    width: 36.r,
                    height: 36.r,
                  ),
                  padding: EdgeInsetsDirectional.zero,
                  tooltip: LocaleKeys.mutashabihatDrill.tr(),
                  onPressed: () => context.pushNamed(
                    AppRoutes.mutashabihatDrillName,
                    extra: entry.id,
                  ),
                  icon: const Icon(Icons.fitness_center),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            SizedBox(height: 8.h),
            // One line: up to three of its surahs, then where it first
            // comes — the card opens on the whole of it.
            Text(
              '${_surahLine(entry, name, arabic: arabic)} — '
              '${LocaleKeys.mutashabihatFirstAt.tr(args: <String>[
                LocaleKeys.mushafAyahReference.tr(args: <String>[name(entry.surahs.first), entry.first.ref.ayah.toLocalisedString()]),
              ])}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
