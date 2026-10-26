import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/surah.dart';
import '../../surah_list/widgets/surah_row.dart' show NumberDiamond;
import '../cubit/mushaf_page.dart';

/// What can be done with an ayah that has been long-pressed.
enum AyahAction {
  /// Mark this ayah as where the reader stopped — or take that mark off it.
  markHere,
  unmark,

  /// Share this ayah as an image: the verbatim text in the illuminated frame,
  /// handed to the platform's share sheet.
  share,

  /// Share the whole page the ayah is on as an image, drawn as the reading
  /// view draws it.
  sharePage,

  /// The rest of the surah recited straight through, once, with nothing
  /// drilled — listening, the way talqeen begins.
  listenFromHere,

  /// A session over this ayah alone, started at once.
  memorizeAlone,

  /// This ayah becomes the start, or the end, of the range a session would
  /// cover. Nothing starts: the range is tinted on the page and the bar's
  /// play button takes it from there.
  rangeStart,
  rangeEnd,

  /// Gives the range back to the page on show.
  clearRange,

  /// The reader slips here — or no longer does. A stumbled ayah is marked on
  /// the page and drilled more by every session over it.
  stumble,
  clearStumble,

  /// The ayahs this one shares a phrase with, side by side.
  similar,
}

/// An ayah that resembles the one pressed, with its surah, to name it.
typedef SimilarRef = ({AyahRef ref, Surah surah});

/// What a long-pressed ayah offers. Pops with the [AyahAction] chosen.
class AyahActionsSheet extends StatelessWidget {
  const AyahActionsSheet({
    required this.ayah,
    required this.surah,
    required this.canPlay,
    required this.hasChosenRange,
    this.isMarked = false,
    this.isStumbled = false,
    this.similar = const <SimilarRef>[],
    this.juzFirst,
    this.juzLast,
    this.canShare = false,
    this.page,
    super.key,
  });

  final AyahRef ayah;
  final Surah surah;

  /// Whether a session can be started at all — a surah nobody has recorded
  /// can still be read, and its range can still be marked.
  final bool canPlay;

  final bool hasChosenRange;

  /// Whether this ayah carries the reader's mark, so the sheet offers to
  /// take it off rather than to set it again.
  final bool isMarked;

  /// Whether this ayah carries a stumble mark, so the sheet offers to take
  /// it off as well as to count another.
  final bool isStumbled;

  /// The ayahs this one shares a phrase with, the most alike first; named
  /// in the entry, so the reader learns the trap is there before opening it.
  final List<SimilarRef> similar;

  bool get hasSimilar => similar.isNotEmpty;

  /// The juz the surah begins and ends in, said beside where it was
  /// revealed. Null when the catalog could not say.
  final int? juzFirst;
  final int? juzLast;

  /// The page the ayah was pressed on, said last in the header. Null when
  /// it is not known.
  final int? page;

  /// How many are named before the rest are only counted.
  static const int named = 2;

  /// Whether this platform can share at all — a desktop without a share
  /// sheet is not offered a button that would do nothing.
  final bool canShare;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String surahName = context.locale.languageCode == 'ar'
        ? surah.nameAr
        : surah.nameEn;
    final bool arabic = context.locale.languageCode == 'ar';
    String refName(SimilarRef r) =>
        '${arabic ? r.surah.nameAr : r.surah.nameEn} '
        '${r.ref.ayah.toLocalisedString()}';
    void choose(AyahAction value) => Navigator.of(context).pop(value);

    // The six done most, as a grid a thumb reaches: listening, memorizing,
    // the reader's mark, a stumble, sharing. Each says in full what it does
    // as its tooltip.
    final List<Widget> quick = <Widget>[
      if (canPlay) ...<Widget>[
        _Quick(
          icon: Icons.headphones_outlined,
          label: LocaleKeys.ayahMenuListen.tr(),
          tooltip: LocaleKeys.mushafListenFromHere.tr(),
          onTap: () => choose(AyahAction.listenFromHere),
        ),
        _Quick(
          icon: Icons.repeat_one,
          label: LocaleKeys.ayahMenuMemorize.tr(),
          tooltip: LocaleKeys.mushafMemorizeAyah.tr(),
          onTap: () => choose(AyahAction.memorizeAlone),
        ),
      ],
      isMarked
          ? _Quick(
              icon: Icons.bookmark_remove_outlined,
              label: LocaleKeys.ayahMenuUnmark.tr(),
              tooltip: LocaleKeys.mushafUnmark.tr(),
              onTap: () => choose(AyahAction.unmark),
            )
          : _Quick(
              icon: Icons.bookmark_added_outlined,
              iconColor: AppColors.gold,
              label: LocaleKeys.ayahMenuMark.tr(),
              tooltip: LocaleKeys.mushafMarkHere.tr(),
              onTap: () => choose(AyahAction.markHere),
            ),
      _Quick(
        icon: Icons.flag_outlined,
        label: LocaleKeys.ayahMenuStumble.tr(),
        tooltip: LocaleKeys.mushafStumbleHere.tr(),
        onTap: () => choose(AyahAction.stumble),
      ),
      if (canShare) ...<Widget>[
        _Quick(
          icon: Icons.image_outlined,
          label: LocaleKeys.ayahMenuShareAyah.tr(),
          tooltip: LocaleKeys.mushafShareAyah.tr(),
          onTap: () => choose(AyahAction.share),
        ),
        _Quick(
          icon: Icons.menu_book_outlined,
          label: LocaleKeys.ayahMenuSharePage.tr(),
          tooltip: LocaleKeys.mushafSharePage.tr(),
          onTap: () => choose(AyahAction.sharePage),
        ),
      ],
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(16.w, 4.h, 16.w, 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                NumberDiamond(number: ayah.ayah),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        LocaleKeys.mushafAyahReference.tr(
                          args: <String>[
                            surahName,
                            ayah.ayah.toLocalisedString(),
                          ],
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      // Where the surah stands, from the catalog: where it
                      // was revealed, how long it is, which juz it spans.
                      Text(
                        joinDetails(<String>[
                          LocaleKeys.mushafSurahAbout.tr(
                            args: <String>[
                              switch (surah.revelationPlace) {
                                RevelationPlace.makkah =>
                                  LocaleKeys.mushafMakki.tr(),
                                RevelationPlace.madinah =>
                                  LocaleKeys.mushafMadani.tr(),
                              },
                              surah.ayahCount.toLocalisedString(),
                            ],
                          ),
                          if (juzFirst != null && juzLast != null)
                            juzFirst == juzLast
                                ? LocaleKeys.mushafJuzOne.tr(
                                    args: <String>[
                                      juzFirst!.toLocalisedString(),
                                    ],
                                  )
                                : LocaleKeys.mushafJuzSpan.tr(
                                    args: <String>[
                                      juzFirst!.toLocalisedString(),
                                      juzLast!.toLocalisedString(),
                                    ],
                                  ),
                          if (page != null)
                            LocaleKeys.mushafPage.tr(
                              args: <String>[page!.toLocalisedString()],
                            ),
                        ]),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8.r,
              crossAxisSpacing: 8.r,
              childAspectRatio: 1.15,
              children: quick,
            ),
            SizedBox(height: 14.h),
            AppCard(
              padding: EdgeInsetsDirectional.zero,
              child: Column(
                children: <Widget>[
                  if (isStumbled) ...<Widget>[
                    ListTile(
                      leading: const TileIcon(Icons.outlined_flag),
                      title: Text(
                        LocaleKeys.mushafClearStumble.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      onTap: () => choose(AyahAction.clearStumble),
                    ),
                    const Divider(height: 1),
                  ],
                  if (hasSimilar) ...<Widget>[
                    ListTile(
                      leading: const TileIcon(Icons.compare_arrows),
                      trailing: AppTag(
                        label: similar.length.toLocalisedString(),
                      ),
                      title: Text(
                        LocaleKeys.mushafSimilarAyahs.tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Text(
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        LocaleKeys.mushafSimilarResembles.tr(
                          args: <String>[
                            joinDetails(<String>[
                              ...similar.take(named).map(refName),
                              if (similar.length > named)
                                LocaleKeys.mushafSimilarMore.tr(
                                  args: <String>[
                                    (similar.length - named)
                                        .toLocalisedString(),
                                  ],
                                ),
                            ]),
                          ],
                        ),
                      ),
                      onTap: () => choose(AyahAction.similar),
                    ),
                    const Divider(height: 1),
                  ],
                  // The range: what it is, and the two ends to set it by,
                  // on the row itself.
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      16.w,
                      12.h,
                      12.w,
                      12.h,
                    ),
                    child: Row(
                      children: <Widget>[
                        const TileIcon(Icons.data_array),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                LocaleKeys.ayahMenuRange.tr(),
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                LocaleKeys.ayahMenuRangeHint.tr(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Tooltip(
                          message: LocaleKeys.mushafSetRangeStart.tr(),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(LocaleKeys.ayahMenuStart.tr()),
                            onPressed: () => choose(AyahAction.rangeStart),
                          ),
                        ),
                        SizedBox(width: 6.w),
                        Tooltip(
                          message: LocaleKeys.mushafSetRangeEnd.tr(),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(LocaleKeys.ayahMenuEnd.tr()),
                            onPressed: () => choose(AyahAction.rangeEnd),
                          ),
                        ),
                        if (hasChosenRange)
                          IconButton(
                            tooltip: LocaleKeys.mushafClearRange.tr(),
                            onPressed: () => choose(AyahAction.clearRange),
                            icon: const Icon(Icons.clear),
                          ),
                      ],
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

/// One cell of the grid: an icon, a few words, the whole of it a tap.
class _Quick extends StatelessWidget {
  const _Quick({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final Color? iconColor;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.all(8.r),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: iconColor, size: 24.r),
                SizedBox(height: 6.h),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
