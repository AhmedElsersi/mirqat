import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/ayah_text.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/models/word.dart';
import '../../mushaf/mushaf_args.dart';
import '../../session/session_request.dart';
import '../cubit/similar_cubit.dart';

/// One ayah of a comparison: where it is, its words as the mushaf prints
/// them with the shared ones tinted, a tap to read it in place and a button
/// to hear it.
class ComparedAyahCard extends StatelessWidget {
  const ComparedAyahCard({
    required this.item,
    this.emphasised = false,
    super.key,
  });

  final ComparedAyah item;

  /// The ayah being compared from, set apart from the ones it resembles.
  final bool emphasised;

  void _open(BuildContext context, {required bool listen}) => context.pushNamed(
    AppRoutes.mushafName,
    extra: MushafArgs(
      initialAyah: item.ref,
      session: listen
          ? SessionRequest(
              from: item.ref,
              to: item.ref,
              preset: SessionPreset.listen,
              autostart: true,
            )
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? page = item.words.firstOrNull?.page;
    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 10.h),
      child: AppCard(
        filled: emphasised,
        padding: EdgeInsetsDirectional.all(16.r),
        onTap: () => _open(context, listen: false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The ayah's own words, as the mushaf prints them, wrapping
            // where the card ends; the words it shares tinted.
            QuranWords(
              words: item.words,
              tint: (Word w) =>
                  item.isShared(w) ? WordTint.shared : WordTint.none,
            ),
            SizedBox(height: 10.h),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    joinDetails(<String>[
                      LocaleKeys.commonAyahNumber.tr(
                        args: <String>[item.ref.ayah.toLocalisedString()],
                      ),
                      if (page != null)
                        LocaleKeys.mushafPage.tr(
                          args: <String>[page.toLocalisedString()],
                        ),
                    ]),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: LocaleKeys.similarListen.tr(),
                  onPressed: () => _open(context, listen: true),
                  icon: const Icon(Icons.volume_up_outlined),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Words of `quran.db`, each through [AyahText], wrapping right to left
/// whatever the interface language.
class QuranWords extends StatelessWidget {
  const QuranWords({
    required this.words,
    this.tint,
    this.fontSize,
    this.veiled,
    this.faint = false,
    this.centered = false,
    super.key,
  });

  final List<Word> words;

  /// Set in the middle of its width, as a phrase on its own is.
  final bool centered;
  final WordTint Function(Word)? tint;
  final double? fontSize;

  /// Words whose ink is held back — in place, at their width, unread.
  final bool Function(Word)? veiled;

  /// Drawn fainter: context, not what is being asked.
  final bool faint;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Wrap(
      spacing: 6.w,
      runSpacing: 2.h,
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      children: <Widget>[
        for (final Word w in words)
          AyahText.word(
            text: w.text,
            fontSize: fontSize ?? 22.sp,
            isMarker: w.isMarker,
            tint: (veiled?.call(w) ?? false)
                ? WordTint.veiled
                : tint?.call(w) ?? WordTint.none,
            veiled: veiled?.call(w) ?? false,
            heldBack: faint,
          ),
      ],
    ),
  );
}
