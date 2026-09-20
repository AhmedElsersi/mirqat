import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/app_info.dart';
import '../../../services/app_info_service.dart';
import '../../../services/link_opener.dart';
import '../cubit/app_info_cubit.dart';

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
                child: CircleAvatar(
                  radius: 44.r,
                  backgroundColor: theme.colorScheme.primary,
                  // The portrait, when `app.json` names one and it can be
                  // fetched; over the name's first letter, which is what
                  // shows until then and whenever it cannot. A card with no
                  // portrait should not look like one is missing.
                  foregroundImage: switch (sl<AppInfoService>().resolve(
                    developer.photo,
                  )) {
                    final Uri photo => NetworkImage('$photo'),
                    null => null,
                  },
                  onForegroundImageError: developer.photo.isEmpty
                      ? null
                      : (Object _, StackTrace? _) {},
                  child: Text(
                    name.isEmpty ? '' : name.characters.first,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
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
                  _LinkTile(developer: developer, link: link),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.developer, required this.link});

  final DeveloperInfo developer;
  final DeveloperLink link;

  @override
  Widget build(BuildContext context) {
    final Uri? uri = developer.uriFor(link);
    final (IconData icon, String label) = switch (link) {
      DeveloperLink.email => (
        Icons.mail_outline,
        LocaleKeys.aboutLinkEmail.tr(),
      ),
      DeveloperLink.github => (Icons.code, LocaleKeys.aboutLinkGithub.tr()),
      DeveloperLink.linkedin => (
        Icons.work_outline,
        LocaleKeys.aboutLinkLinkedin.tr(),
      ),
      DeveloperLink.whatsapp => (
        Icons.chat_outlined,
        LocaleKeys.aboutLinkWhatsapp.tr(),
      ),
      DeveloperLink.facebook => (
        Icons.public,
        LocaleKeys.aboutLinkFacebook.tr(),
      ),
    };

    return ListTile(
      contentPadding: EdgeInsetsDirectional.zero,
      leading: Icon(icon),
      title: Text(label),
      // An address reads left to right whatever the language around it, but
      // it still sits under its label, on the side the page reads from.
      subtitle: Text(
        developer.links[link] ?? '',
        textDirection: TextDirection.ltr,
        textAlign: Directionality.of(context) == TextDirection.rtl
            ? TextAlign.right
            : TextAlign.left,
      ),
      trailing: const Icon(Icons.open_in_new, size: 18),
      enabled: uri != null,
      onTap: uri == null ? null : () => _open(context, uri),
    );
  }

  static Future<void> _open(BuildContext context, Uri uri) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failed = LocaleKeys.aboutLinkFailed.tr();
    if (await sl<LinkOpener>().open(uri)) return;
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
