import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../cubit/home_index_state.dart';

String _starts(BuildContext context, JuzItem item) =>
    LocaleKeys.homeJuzStarts.tr(
      args: <String>[
        context.locale.languageCode == 'ar'
            ? item.surah.nameAr
            : item.surah.nameEn,
        item.info.ayahNumber.toLocalisedString(),
      ],
    );

class _Number extends StatelessWidget {
  const _Number(this.number);

  final int number;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: 44.r,
      height: 44.r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        number.toLocalisedString(),
        style: theme.textTheme.titleSmall,
      ),
    );
  }
}

/// A juz as a row: its number, its name, and where it begins.
class JuzRow extends StatelessWidget {
  const JuzRow({required this.item, required this.onTap, super.key});

  final JuzItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsetsDirectional.symmetric(
        horizontal: 20.w,
        vertical: 6.h,
      ),
      leading: _Number(item.info.number),
      title: Text(
        LocaleKeys.homeJuzName.tr(
          args: <String>[item.info.number.toLocalisedString()],
        ),
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text(_starts(context, item)),
      trailing: Text(
        LocaleKeys.homePage.tr(
          args: <String>[item.info.page.toLocalisedString()],
        ),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// The same juz as a card, for the grid.
class JuzTile extends StatelessWidget {
  const JuzTile({required this.item, required this.onTap, super.key});

  final JuzItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.all(14.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Number and name share a line: stacked, the card needed more
              // height than the grid gives it and overflowed by a line.
              Row(
                children: <Widget>[
                  _Number(item.info.number),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      LocaleKeys.homeJuzName.tr(
                        args: <String>[item.info.number.toLocalisedString()],
                      ),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                _starts(context, item),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                LocaleKeys.homePage.tr(
                  args: <String>[item.info.page.toLocalisedString()],
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
