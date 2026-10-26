import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/app_info.dart';
import '../../../services/link_opener.dart';

/// One way of reaching a person named in `app.json` — the developer, the
/// owner of the app's idea. A link that cannot be turned into an address is
/// shown disabled rather than hidden, so a typo in the file is visible to
/// whoever can fix it; one left blank is not rendered at all (the caller
/// walks `links.keys`).
class ContactLinkChip extends StatelessWidget {
  const ContactLinkChip({required this.person, required this.link, super.key});

  final DeveloperInfo person;
  final DeveloperLink link;

  @override
  Widget build(BuildContext context) {
    final Uri? uri = person.uriFor(link);
    final (IconData icon, String label) = switch (link) {
      DeveloperLink.email => (
        Icons.mail_outline,
        LocaleKeys.aboutLinkEmail.tr(),
      ),
      DeveloperLink.phone => (
        Icons.phone_outlined,
        LocaleKeys.aboutLinkPhone.tr(),
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

    return ActionChip(
      avatar: Icon(icon, size: 16.r),
      label: Text(label),
      tooltip: person.links[link],
      onPressed: uri == null ? null : () => _open(context, uri),
    );
  }

  static Future<void> _open(BuildContext context, Uri uri) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String failed = LocaleKeys.aboutLinkFailed.tr();
    if (await sl<LinkOpener>().open(uri)) return;
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
