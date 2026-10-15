import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/app_info.dart';
import '../cubit/app_info_cubit.dart';
import '../widgets/contact_link_tile.dart';
import '../widgets/person_avatar.dart';

/// Who made the app, and how to reach them. Every way of reaching them is
/// optional in `app.json`; one that is not filled in is simply not here.
class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<AppInfoCubit>(
    create: (_) => sl<AppInfoCubit>()..load(),
    child: const _DeveloperView(),
  );
}

class _DeveloperView extends StatelessWidget {
  const _DeveloperView();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.aboutDeveloper.tr())),
      body: BlocBuilder<AppInfoCubit, AppInfo?>(
        builder: (BuildContext context, AppInfo? info) {
          if (info == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final DeveloperInfo developer = info.developer;
          final String name = developer.name.of(context.locale.languageCode);

          return ListView(
            padding: EdgeInsetsDirectional.all(24.r),
            children: <Widget>[
              Center(
                child: PersonAvatar(name: name, photo: developer.photo),
              ),
              SizedBox(height: 16.h),
              if (name.isNotEmpty)
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
              SizedBox(height: 4.h),
              Text(
                LocaleKeys.aboutDeveloperRole.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (developer.links.isNotEmpty) ...<Widget>[
                SizedBox(height: 28.h),
                Text(
                  LocaleKeys.aboutContact.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: 4.h),
                for (final DeveloperLink link in developer.links.keys)
                  ContactLinkTile(person: developer, link: link),
              ],
            ],
          );
        },
      ),
    );
  }
}
