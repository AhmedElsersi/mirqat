import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/range_label.dart';
import '../../../data/models/surah.dart';
import '../../../domain/entities/daily_wird.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import 'wird_editor.dart';

/// The words a part of the wird goes by — the same as its chip in the
/// session sheet, so the two read as one thing.
String wirdPartLabel(WirdPart part) => switch (part) {
  WirdPart.fresh => LocaleKeys.presetsNew.tr(),
  WirdPart.recent => LocaleKeys.presetsRecent.tr(),
  WirdPart.old => LocaleKeys.presetsOld.tr(),
};

/// How a part is worked: new is the reader's own defaults; the reviews are
/// the sheet's lighter ways of working.
SessionPreset wirdPartPreset(WirdPart part) => switch (part) {
  WirdPart.fresh => const SessionPreset(),
  WirdPart.recent => SessionPreset.recent,
  WirdPart.old => SessionPreset.old,
};

/// Opens the reading view on [range], set up the way [part] is worked, with
/// its chip shown chosen in the sheet.
void openWirdPart(BuildContext context, WirdPart part, WirdRange range) =>
    context.pushNamed<void>(
      AppRoutes.mushafName,
      extra: MushafArgs(
        initialAyah: range.from,
        session: SessionRequest(
          from: range.from,
          to: range.to,
          preset: wirdPartPreset(part),
          presetKey: part.key,
          autostart: true,
        ),
      ),
    );

/// Today's wird on the home page: what the reader memorizes new, and what
/// they go over again, each a range they set and a tap away. A part they
/// have not set is simply not listed; with none set, one quiet line offers to
/// set them.
class WirdCard extends StatelessWidget {
  const WirdCard({
    required this.wird,
    required this.surahs,
    required this.onChanged,
    super.key,
  });

  final DailyWird wird;

  /// Every surah, in order: for the names, and for the editor's lists.
  final List<Surah> surahs;

  /// One part set to a range, or cleared with null.
  final Future<void> Function(WirdPart part, WirdRange? range) onChanged;

  Surah? _surah(int n) => n >= 1 && n <= surahs.length ? surahs[n - 1] : null;

  Future<void> _edit(BuildContext context) async {
    final DailyWird? edited = await showWirdEditor(
      context,
      wird: wird,
      surahs: surahs,
    );
    if (edited == null) return;
    for (final WirdPart part in WirdPart.values) {
      if (edited[part] != wird[part]) await onChanged(part, edited[part]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (surahs.isEmpty) return const SizedBox.shrink();
    final ThemeData theme = Theme.of(context);
    final List<WirdPart> set = <WirdPart>[
      for (final WirdPart p in WirdPart.values)
        if (wird[p] != null) p,
    ];

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12.w, 10.h, 12.w, 0),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16.r),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(14.w, 4.h, 4.w, 4.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.menu_book, color: theme.colorScheme.primary),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      LocaleKeys.wirdTitle.tr(),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _edit(context),
                    child: Text(
                      set.isEmpty
                          ? LocaleKeys.wirdSet.tr()
                          : LocaleKeys.wirdEdit.tr(),
                    ),
                  ),
                ],
              ),
              if (set.isEmpty)
                Padding(
                  padding: EdgeInsetsDirectional.only(bottom: 8.h),
                  child: Text(
                    LocaleKeys.wirdEmpty.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final WirdPart part in set)
                if ((
                      _surah(wird[part]!.from.surah),
                      _surah(wird[part]!.to.surah),
                    )
                    case (final Surah fromSurah, final Surah toSurah))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsetsDirectional.zero,
                    title: Text(
                      rangeLabel(
                        context,
                        from: wird[part]!.from,
                        to: wird[part]!.to,
                        fromSurah: fromSurah,
                        toSurah: toSurah,
                      ),
                    ),
                    subtitle: Text(
                      wirdPartLabel(part),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: LocaleKeys.planStart.tr(),
                      onPressed: () => openWirdPart(context, part, wird[part]!),
                      icon: const Icon(Icons.play_circle_outline),
                    ),
                    onTap: () => openWirdPart(context, part, wird[part]!),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
