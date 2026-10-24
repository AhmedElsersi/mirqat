import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/ladder_mark.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/app_info.dart';
import '../../../services/app_version_service.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../cubit/app_info_cubit.dart';
import '../widgets/contact_link_chip.dart';
import '../widgets/person_avatar.dart';

/// Everything the app says about itself, on one page: what it is for, who
/// made it, whose idea it was, and how to reach them.
///
/// These were four routes under Settings, each an icon over a paragraph from
/// the same `app.json`. The words still come from there, so they can be
/// rewritten without a release; only the reading of them is in one place now.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<AppInfoCubit>(
    create: (_) => sl<AppInfoCubit>()..load(),
    child: const _AboutView(),
  );
}

class _AboutView extends StatelessWidget {
  const _AboutView();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String language = context.locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.aboutTitle.tr())),
      body: DesktopWidth(
        child: BlocBuilder<AppInfoCubit, AppInfo?>(
          builder: (BuildContext context, AppInfo? info) {
            if (info == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final String goal = info.goal.of(language);
            final String about = info.about.of(language);
            final IdeaInfo idea = info.idea;
            final String ideaText = idea.text.of(language);

            return ListView(
              padding: EdgeInsetsDirectional.fromSTEB(16.w, 12.h, 16.w, 32.h),
              children: <Widget>[
                const _Masthead(),

                if (goal.isNotEmpty) ...<Widget>[
                  FieldLabel(LocaleKeys.aboutGoal.tr()),
                  _Prose(text: goal),
                ],
                if (about.isNotEmpty) ...<Widget>[
                  FieldLabel(LocaleKeys.aboutUs.tr()),
                  _Prose(
                    text: about,
                    // What the app does not do, as three tags: these are
                    // the app's own promises (CLAUDE.md A.2), not app.json's.
                    tags: <String>[
                      LocaleKeys.aboutTagNoAds.tr(),
                      LocaleKeys.aboutTagNoAccounts.tr(),
                      LocaleKeys.aboutTagNoTracking.tr(),
                    ],
                  ),
                ],
                if (ideaText.isNotEmpty ||
                    idea.owner.name.of(language).isNotEmpty) ...<Widget>[
                  FieldLabel(LocaleKeys.aboutIdea.tr()),
                  _Person(
                    person: idea.owner,
                    role: LocaleKeys.aboutIdeaOwnerRole.tr(),
                    text: ideaText,
                  ),
                ],
                FieldLabel(LocaleKeys.aboutDeveloperLabel.tr()),
                _Person(
                  person: info.developer,
                  role: LocaleKeys.aboutDeveloperRole.tr(),
                ),

                SizedBox(height: 16.h),
                AppCard(
                  padding: EdgeInsetsDirectional.zero,
                  child: Column(
                    children: <Widget>[
                      ListTile(
                        leading: const TileIcon(Icons.help_outline),
                        title: Text(
                          LocaleKeys.aboutHowToUse.tr(),
                          style: theme.textTheme.titleSmall,
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () => context.pushNamed(AppRoutes.howToUseName),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const TileIcon(Icons.play_circle_outline),
                        title: Text(
                          LocaleKeys.aboutShowIntro.tr(),
                          style: theme.textTheme.titleSmall,
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () =>
                            context.pushNamed(AppRoutes.onboardingName),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The app's own name, what it is called in one line, and which build this
/// is — the first thing anyone opening "about" is looking for.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const Color onHero = AppColors.cream;
    final InstalledVersion? version = context
        .select<SettingsCubit, InstalledVersion?>(
          (SettingsCubit c) => c.state.appVersion,
        );

    return Material(
      color: AppColors.forest,
      borderRadius: BorderRadius.circular(26.r),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsetsDirectional.all(22.r),
        child: Column(
          children: <Widget>[
            LadderMark(
              current: 3,
              color: onHero.withValues(alpha: 0.18),
              doneColor: AppColors.rungDoneOnHero,
            ),
            SizedBox(height: 14.h),
            Text(
              LocaleKeys.appName.tr(),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              LocaleKeys.appSlogan.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: onHero.withValues(alpha: 0.78),
              ),
            ),
            if (version != null) ...<Widget>[
              SizedBox(height: 10.h),
              Text(
                LocaleKeys.settingsVersion.tr(
                  args: <String>[version.version, version.buildNumber],
                ),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onHero.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A passage of `app.json`'s own words.
class _Prose extends StatelessWidget {
  const _Prose({required this.text, this.tags = const <String>[]});

  final String text;

  /// Said under the passage in a word or three each.
  final List<String> tags;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsetsDirectional.all(16.r),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.9),
        ),
        if (tags.isNotEmpty) ...<Widget>[
          SizedBox(height: 12.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: <Widget>[
              for (final String tag in tags) AppTag(label: tag),
            ],
          ),
        ],
      ],
    ),
  );
}

/// A person named in `app.json`: who they are, what they did, what they say,
/// and every way of reaching them that the file fills in.
class _Person extends StatelessWidget {
  const _Person({required this.person, required this.role, this.text});

  final DeveloperInfo person;
  final String role;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String name = person.name.of(context.locale.languageCode);
    final String body = text ?? '';

    return AppCard(
      padding: EdgeInsetsDirectional.all(16.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PersonAvatar(name: name, photo: person.photo),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (name.isNotEmpty)
                      Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    Text(
                      role,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (body.isNotEmpty) ...<Widget>[
            SizedBox(height: 14.h),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.9),
            ),
          ],
          if (person.links.isNotEmpty) ...<Widget>[
            SizedBox(height: 14.h),
            // Every way of reaching them, as chips: a tap opens it.
            Wrap(
              spacing: 8.w,
              runSpacing: 6.h,
              children: <Widget>[
                for (final DeveloperLink link in person.links.keys)
                  ContactLinkChip(person: person, link: link),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
