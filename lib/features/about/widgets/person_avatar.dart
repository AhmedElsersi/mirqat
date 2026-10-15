import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/di/injection.dart';
import '../../../services/app_info_service.dart';

/// The round portrait of a person named in `app.json`.
///
/// The photo, when the file names one and it can be fetched; over the name's
/// first letter, which is what shows until then and whenever it cannot. A
/// card with no portrait should not look like one is missing.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({required this.name, required this.photo, super.key});

  /// The name whose initial stands in for a missing photo.
  final String name;

  /// An address or a path relative to `app.json`, or empty for none.
  final String photo;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return CircleAvatar(
      radius: 44.r,
      backgroundColor: theme.colorScheme.primary,
      foregroundImage: switch (sl<AppInfoService>().resolve(photo)) {
        final Uri resolved => NetworkImage('$resolved'),
        null => null,
      },
      onForegroundImageError: photo.isEmpty
          ? null
          : (Object _, StackTrace? _) {},
      child: Text(
        name.isEmpty ? '' : name.characters.first,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: theme.colorScheme.onPrimary,
        ),
      ),
    );
  }
}
