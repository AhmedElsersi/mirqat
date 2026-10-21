import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../data/models/surah.dart';
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

    ListTile action(
      AyahAction value,
      IconData icon,
      String label, {
      String? subtitle,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () => Navigator.of(context).pop(value),
    );
    final bool arabic = context.locale.languageCode == 'ar';
    String refName(SimilarRef r) =>
        '${arabic ? r.surah.nameAr : r.surah.nameEn} '
        '${r.ref.ayah.toLocalisedString()}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.symmetric(vertical: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: 16.w,
                vertical: 8.h,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    LocaleKeys.mushafAyahReference.tr(
                      args: <String>[surahName, ayah.ayah.toLocalisedString()],
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                  // Where the surah stands, from the catalog: where it was
                  // revealed and how long it is — a moment's orientation.
                  Text(
                    <String>[
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
                                args: <String>[juzFirst!.toLocalisedString()],
                              )
                            : LocaleKeys.mushafJuzSpan.tr(
                                args: <String>[
                                  juzFirst!.toLocalisedString(),
                                  juzLast!.toLocalisedString(),
                                ],
                              ),
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // First, because it is what a reader closing the mushaf wants.
            isMarked
                ? action(
                    AyahAction.unmark,
                    Icons.bookmark_remove_outlined,
                    LocaleKeys.mushafUnmark.tr(),
                  )
                : action(
                    AyahAction.markHere,
                    Icons.bookmark_add_outlined,
                    LocaleKeys.mushafMarkHere.tr(),
                  ),
            action(
              AyahAction.stumble,
              Icons.flag_outlined,
              LocaleKeys.mushafStumbleHere.tr(),
            ),
            if (isStumbled)
              action(
                AyahAction.clearStumble,
                Icons.outlined_flag,
                LocaleKeys.mushafClearStumble.tr(),
              ),
            if (hasSimilar)
              action(
                AyahAction.similar,
                Icons.compare_arrows,
                LocaleKeys.mushafSimilarAyahs.tr(),
                subtitle: LocaleKeys.mushafSimilarResembles.tr(
                  args: <String>[
                    <String>[
                      ...similar.take(named).map(refName),
                      if (similar.length > named)
                        LocaleKeys.mushafSimilarMore.tr(
                          args: <String>[
                            (similar.length - named).toLocalisedString(),
                          ],
                        ),
                    ].join(' · '),
                  ],
                ),
              ),
            if (canShare) ...<Widget>[
              action(
                AyahAction.share,
                Icons.adaptive.share,
                LocaleKeys.mushafShareAyah.tr(),
              ),
              action(
                AyahAction.sharePage,
                Icons.menu_book_outlined,
                LocaleKeys.mushafSharePage.tr(),
              ),
            ],
            if (canPlay) ...<Widget>[
              action(
                AyahAction.listenFromHere,
                Icons.headphones_outlined,
                LocaleKeys.mushafListenFromHere.tr(),
              ),
              action(
                AyahAction.memorizeAlone,
                Icons.repeat_one,
                LocaleKeys.mushafMemorizeAyah.tr(),
              ),
            ],
            action(
              AyahAction.rangeStart,
              Icons.first_page,
              LocaleKeys.mushafSetRangeStart.tr(),
            ),
            action(
              AyahAction.rangeEnd,
              Icons.last_page,
              LocaleKeys.mushafSetRangeEnd.tr(),
            ),
            if (hasChosenRange)
              action(
                AyahAction.clearRange,
                Icons.clear,
                LocaleKeys.mushafClearRange.tr(),
              ),
          ],
        ),
      ),
    );
  }
}
