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
import '../../../data/models/app_settings.dart';
import '../../../data/models/ayah_search_hit.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../mushaf/mushaf_args.dart';
import '../../mushaf/reading_section.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/search_cubit.dart';
import '../cubit/search_state.dart';

/// One box, three kinds of answer: a surah by name, an ayah by its words, a
/// page by its number. Every result opens the reading view at its place.
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
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: LocaleKeys.searchHint.tr(),
            border: InputBorder.none,
          ),
          style: theme.textTheme.titleMedium,
          onChanged: (String input) =>
              context.read<SearchCubit>().search(input),
        ),
        actions: <Widget>[
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (BuildContext context, TextEditingValue value, _) =>
                value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: () {
                      _controller.clear();
                      context.read<SearchCubit>().search('');
                    },
                    tooltip: LocaleKeys.commonClear.tr(),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ],
      ),
      body: DesktopWidth(
        child: BlocBuilder<SearchCubit, SearchState>(
          builder: (BuildContext context, SearchState state) {
            if (!state.hasQuery) {
              return _Message(LocaleKeys.searchPrompt.tr());
            }
            if (!state.hasResults) {
              return state.searching
                  ? const Center(child: CircularProgressIndicator())
                  : _Message(LocaleKeys.searchNoResults.tr());
            }
            return _Results(state: state);
          },
        ),
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
      padding: EdgeInsetsDirectional.only(bottom: 24.h),
      children: <Widget>[
        if (page != null)
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: Text(
              LocaleKeys.searchOpenPage.tr(
                args: <String>[page.toLocalisedString()],
              ),
            ),
            onTap: () => _openMushaf(context, MushafArgs(initialPage: page)),
          ),
        if (state.surahs.isNotEmpty) ...<Widget>[
          _SectionLabel(LocaleKeys.searchSurahs.tr()),
          for (final Surah surah in state.surahs) _SurahResult(surah: surah),
        ],
        if (state.ayahs.isNotEmpty) ...<Widget>[
          _SectionLabel(LocaleKeys.searchAyahs.tr()),
          for (final AyahSearchHit hit in state.ayahs) _AyahResult(hit: hit),
        ],
        if (state.searching)
          Padding(
            padding: EdgeInsetsDirectional.all(16.r),
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (state.ayahs.length >= SearchCubit.ayahLimit)
          // The list is capped, never any ayah's text (A.2 rule 7): say so,
          // and a longer query narrows it.
          Padding(
            padding: EdgeInsetsDirectional.all(16.r),
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(16.w, 16.h, 16.w, 4.h),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

class _SurahResult extends StatelessWidget {
  const _SurahResult({required this.surah});

  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final bool arabic = context.locale.languageCode == 'ar';
    return ListTile(
      leading: CircleAvatar(
        radius: 16.r,
        child: Text(
          surah.number.toLocalisedString(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
      title: Text(arabic ? surah.nameAr : surah.nameEn),
      subtitle: Text(arabic ? surah.nameEn : surah.nameAr),
      onTap: () => _openSurah(context, surah),
    );
  }
}

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

    return InkWell(
      onTap: () => _openMushaf(
        context,
        MushafArgs(initialAyah: AyahRef(hit.surahNumber, hit.number)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: 16.w,
          vertical: 10.h,
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
            SizedBox(height: 4.h),
            Text(
              '${LocaleKeys.mushafAyahReference.tr(args: <String>[
                surah == null
                    ? hit.surahNumber.toLocalisedString()
                    : (arabic ? surah.nameAr : surah.nameEn),
                hit.number.toLocalisedString(),
              ])} · ${LocaleKeys.mushafPage.tr(args: <String>[hit.page.toLocalisedString()])}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 6.h),
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
          ],
        ),
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
