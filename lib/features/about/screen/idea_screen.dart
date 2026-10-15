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

/// «فكرة التطبيق»: where the app's idea came from — Mr. Saied Eloksh
/// (سعيد العكش) — with a word of credit and the ways to reach him.
///
/// Everything here comes from `app.json`'s `idea` section through
/// [AppInfoCubit], so the words, the photo and the links can change without a
/// release, and it is read the way the developer's card is: a link left blank
/// is simply not shown, and a missing photo shows the name's initial.
class IdeaScreen extends StatelessWidget {
  const IdeaScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider<AppInfoCubit>(
    create: (_) => sl<AppInfoCubit>()..load(),
    child: const _IdeaView(),
  );
}

class _IdeaView extends StatelessWidget {
  const _IdeaView();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.aboutIdea.tr())),
      body: BlocBuilder<AppInfoCubit, AppInfo?>(
        builder: (BuildContext context, AppInfo? info) {
          if (info == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final IdeaInfo idea = info.idea;
          final DeveloperInfo owner = idea.owner;
          final String name = owner.name.of(context.locale.languageCode);
          final String text = idea.text.of(context.locale.languageCode);

          return ListView(
            padding: EdgeInsetsDirectional.all(24.r),
            children: <Widget>[
              Center(
                child: PersonAvatar(name: name, photo: owner.photo),
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
                LocaleKeys.aboutIdeaOwnerRole.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                text.isEmpty ? LocaleKeys.aboutEmpty.tr() : text,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.9),
              ),
              if (owner.links.isNotEmpty) ...<Widget>[
                SizedBox(height: 28.h),
                Text(
                  LocaleKeys.aboutContact.tr(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                SizedBox(height: 4.h),
                for (final DeveloperLink link in owner.links.keys)
                  ContactLinkTile(person: owner, link: link),
              ],
            ],
          );
        },
      ),
    );
  }
}
