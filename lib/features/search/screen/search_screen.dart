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
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah_search_hit.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../mushaf/mushaf_args.dart';
import '../../mushaf/reading_section.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';

/// One box, three kinds of answer: a surah by name, an ayah by its words, a
/// page by its number. Every result opens the reading view at its place.
///
/// The box is the screen's own rather than a field in the app bar: it is what
/// the screen is for, and a field in the bar has nowhere to say what can be
/// typed into it.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<SearchCubit>(
    create: (_) => sl<SearchCubit>()..load(),
    child: const _SearchView(),
  );
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.searchTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<SearchCubit, SearchState>(
          builder: (BuildContext context, SearchState state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(16.w, 8.h, 16.w, 0),
                child: _Field(controller: _controller),
              ),
              // A hair of progress under the field, never a spinner over the
              // results: a longer query narrows what is already shown.
              SizedBox(
                height: 3.h,
                child: state.searching
                    ? LinearProgressIndicator(minHeight: 3.h)
                    : null,
              ),
              Expanded(
                child: !state.hasQuery
                    ? _Message(LocaleKeys.searchPrompt.tr())
                    : !state.hasResults && !state.searching
                    ? _Message(LocaleKeys.searchNoResults.tr())
                    : _Results(state: state),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The box itself: a pill on the page, with the one thing it does said under
/// it in the field's own hint.
class _Field extends StatelessWidget {
  const _Field({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 52.h,
      padding: EdgeInsetsDirectional.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
          SizedBox(width: 10.w),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: LocaleKeys.searchHint.tr(),
                border: InputBorder.none,
                isCollapsed: true,
              ),
              style: theme.textTheme.titleSmall,
              onChanged: (String input) =>
                  context.read<SearchCubit>().search(input),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (BuildContext context, TextEditingValue value, _) =>
                value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      controller.clear();
                      context.read<SearchCubit>().search('');
                    },
                    tooltip: LocaleKeys.commonClear.tr(),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: EdgeInsetsDirectional.all(24.r),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _Results extends StatelessWidget {
  const _Results({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    final int? page = state.page;
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 24.h),
      children: <Widget>[
        if (page != null) ...<Widget>[
          AppCard(
            onTap: () => _openMushaf(context, MushafArgs(initialPage: page)),
            padding: EdgeInsetsDirectional.all(14.r),
            child: Row(
              children: <Widget>[
                const TileIcon(Icons.auto_stories_outlined),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    LocaleKeys.searchOpenPage.tr(
                      args: <String>[page.toLocalisedString()],
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
          SizedBox(height: 4.h),
        ],
        if (state.surahs.isNotEmpty) ...<Widget>[
          SectionTitle(title: LocaleKeys.searchSurahs.tr()),
          AppCard(
            padding: EdgeInsetsDirectional.zero,
            child: Column(
              children: <Widget>[
                for (final Surah surah in state.surahs) ...<Widget>[
                  if (surah != state.surahs.first) const Divider(height: 1),
                  _SurahResult(surah: surah),
                ],
              ],
            ),
          ),
        ],
        if (state.ayahs.isNotEmpty) ...<Widget>[
          SectionTitle(
            title: LocaleKeys.searchAyahs.tr(),
            trailing: state.ayahs.length.toLocalisedString(),
          ),
          for (final AyahSearchHit hit in state.ayahs) ...<Widget>[
            _AyahResult(hit: hit),
            SizedBox(height: 10.h),
          ],
        ],
        if (state.ayahs.length >= SearchCubit.ayahLimit)
          // The list is capped, never any ayah's text (A.2 rule 7): say so,
          // and a longer query narrows it.
          Padding(
            padding: EdgeInsetsDirectional.all(12.r),
            child: Text(
              LocaleKeys.searchMoreResults.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _SurahResult extends StatelessWidget {
  const _SurahResult({required this.surah});

  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool arabic = context.locale.languageCode == 'ar';
    return ListTile(
      leading: NumberDiamond(number: surah.number),
      title: Text(
        arabic ? surah.nameAr : surah.nameEn,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        joinDetails(<String>[
          (surah.revelationPlace == RevelationPlace.makkah
                  ? LocaleKeys.mushafMakki
                  : LocaleKeys.mushafMadani)
              .tr(),
          LocaleKeys.surahListAyahCount.tr(
            args: <String>[surah.ayahCount.toLocalisedString()],
          ),
        ]),
      ),
      trailing: const Icon(Icons.chevron_left),
      onTap: () => _openSurah(context, surah),
    );
  }
}

/// One hit: the ayah whole, and under it where it is.
///
/// The matched word is not marked. The match is made against `text_search`,
/// a column derived at build time; marking the word here would mean
/// normalising the ayah's own words in the app, which A.2 rule 1 forbids.
class _AyahResult extends StatelessWidget {
  const _AyahResult({required this.hit});

  final AyahSearchHit hit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Surah? surah = context.read<SearchCubit>().surahOf(hit.surahNumber);
    final bool arabic = context.locale.languageCode == 'ar';
    final double fontSize = context.select(
      (SettingsCubit cubit) => cubit.state.settings.arabicFontSize,
    );

    return AppCard(
      padding: EdgeInsetsDirectional.all(14.r),
      onTap: () => _openMushaf(
        context,
        MushafArgs(initialAyah: AyahRef(hit.surahNumber, hit.number)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The whole ayah, wrapped — never shortened (A.2 rule 7).
          AyahText(
            text: hit.text,
            fontSize: fontSize.clamp(
              AppSettings.minArabicFontSize,
              AppSettings.maxArabicFontSize,
            ),
            textAlign: TextAlign.start,
          ),
          SizedBox(height: 10.h),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  joinDetails(<String>[
                    LocaleKeys.mushafAyahReference.tr(
                      args: <String>[
                        surah == null
                            ? hit.surahNumber.toLocalisedString()
                            : (arabic ? surah.nameAr : surah.nameEn),
                        hit.number.toLocalisedString(),
                      ],
                    ),
                    LocaleKeys.mushafPage.tr(
                      args: <String>[hit.page.toLocalisedString()],
                    ),
                  ]),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_left,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A surah result opens the way the home screen opens one: the mushaf at the
/// surah's page when the app lives in mushaf view, the surah on its own
/// otherwise.
Future<void> _openSurah(BuildContext context, Surah surah) async {
  final HomeViewMode mode = context
      .read<SettingsCubit>()
      .state
      .settings
      .homeViewMode;
  if (mode != HomeViewMode.mushaf) {
    return _openMushaf(
      context,
      MushafArgs(section: SectionRequest.surah(surah.number)),
    );
  }
  final int? page = await context.read<SearchCubit>().pageOfSurah(
    surah.number,
  );
  if (context.mounted) {
    await _openMushaf(context, MushafArgs(initialPage: page));
  }
}

Future<void> _openMushaf(BuildContext context, MushafArgs args) =>
    context.pushNamed<void>(AppRoutes.mushafName, extra: args);
