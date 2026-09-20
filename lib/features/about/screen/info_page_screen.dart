import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/app_info.dart';
import '../cubit/app_info_cubit.dart';

/// The two pages that are prose and nothing else.
enum InfoPage { about, goal }

/// «من نحن» and «هدفنا»: a heading and a few paragraphs, whose words come from
/// `app.json` so that they can be rewritten without a release.
class InfoPageScreen extends StatelessWidget {
  const InfoPageScreen({required this.page, super.key});

  final InfoPage page;

  @override
  Widget build(BuildContext context) => BlocProvider<AppInfoCubit>(
    create: (_) => sl<AppInfoCubit>()..load(),
    child: _InfoPageView(page: page),
  );
}

class _InfoPageView extends StatelessWidget {
  const _InfoPageView({required this.page});

  final InfoPage page;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String title, IconData icon) = switch (page) {
      InfoPage.about => (LocaleKeys.aboutUs.tr(), Icons.groups_outlined),
      InfoPage.goal => (LocaleKeys.aboutGoal.tr(), Icons.flag_outlined),
    };

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: BlocBuilder<AppInfoCubit, AppInfo?>(
        builder: (BuildContext context, AppInfo? info) {
          if (info == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final String text = switch (page) {
            InfoPage.about => info.about,
            InfoPage.goal => info.goal,
          }.of(context.locale.languageCode);

          return ListView(
            padding: EdgeInsetsDirectional.all(24.r),
            children: <Widget>[
              Icon(icon, size: 48.r, color: theme.colorScheme.primary),
              SizedBox(height: 20.h),
              Text(
                text.isEmpty ? LocaleKeys.aboutEmpty.tr() : text,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.9),
              ),
            ],
          );
        },
      ),
    );
  }
}
