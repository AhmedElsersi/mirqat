import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;
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

/// A juz as a row, drawn as a surah's is (design 02): its number in a
/// diamond, its name, and one quiet line — where it begins, and on which page.
class JuzRow extends StatelessWidget {
  const JuzRow({
    required this.item,
    required this.onTap,
    this.nameKey = LocaleKeys.homeJuzName,
    super.key,
  });

  final JuzItem item;
  final VoidCallback onTap;

  /// What the part is called — a juz by default, a hizb under that tab.
  final String nameKey;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(16.w, 10.h, 16.w, 10.h),
        child: Row(
          children: <Widget>[
            NumberDiamond(number: item.info.number),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    nameKey.tr(
                      args: <String>[item.info.number.toLocalisedString()],
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    joinDetails(<String>[
                      _starts(context, item),
                      LocaleKeys.homePage.tr(
                        args: <String>[item.info.page.toLocalisedString()],
                      ),
                    ]),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The same juz as a card, for the grid.
class JuzTile extends StatelessWidget {
  const JuzTile({
    required this.item,
    required this.onTap,
    this.nameKey = LocaleKeys.homeJuzName,
    super.key,
  });

  final JuzItem item;
  final VoidCallback onTap;

  /// What the part is called — a juz by default, a hizb under that tab.
  final String nameKey;

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
                  NumberDiamond(number: item.info.number),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      nameKey.tr(
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
