import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../data/models/reciter.dart';
import 'reciter_avatar.dart';

/// The reciter picker, the same wherever a reciter is chosen — the session
/// sheet and Settings.
///
/// One field, not a list: ten reciters as rows are a screen of scrolling
/// before the settings that matter, and the next reciter added on the CDN
/// would make it longer still. The field is a filled pill, as the session
/// form's other controls are, and shows the chosen reciter's portrait with
/// their Arabic name over their English one. The menu lists everyone the
/// same way, with the attribution under a reciter who has one, a tick on
/// the one chosen, and — where [unavailable] says so — why one cannot be
/// picked, greyed but still listed so it is clear why.
///
/// A plain dropdown button in the pill, not a form field: the form field's
/// decorator sizes itself from one line of text whatever is put in it, and
/// two names beside a round portrait need their own height.
class ReciterDropdown extends StatelessWidget {
  const ReciterDropdown({
    required this.reciters,
    required this.currentId,
    required this.onChanged,
    this.unavailable,
    super.key,
  });

  final List<Reciter> reciters;
  final String? currentId;
  final ValueChanged<Reciter> onChanged;

  /// Why a reciter cannot be picked here, or null when they can. Absent,
  /// everyone can.
  final String? Function(Reciter reciter)? unavailable;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(12.w, 8.h, 8.w, 8.h),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            // Keyed by the choice, so a reciter picked elsewhere — the
            // settings default, a session that switched — is what the field
            // shows.
            key: ValueKey<String?>(currentId),
            value: currentId,
            isExpanded: true,
            // Entries size to their lines: two, a third for an attribution
            // or for the reason a reciter cannot be picked.
            itemHeight: null,
            icon: Icon(Icons.expand_more_rounded, color: colors.primary),
            dropdownColor: colors.surface,
            borderRadius: BorderRadius.circular(16.r),
            elevation: 3,
            menuMaxHeight: 0.6.sh,
            items: <DropdownMenuItem<String>>[
              for (final Reciter reciter in reciters)
                DropdownMenuItem<String>(
                  value: reciter.id,
                  enabled: unavailable?.call(reciter) == null,
                  child: _ReciterEntry(
                    reciter: reciter,
                    reason: unavailable?.call(reciter),
                    chosen: reciter.id == currentId,
                  ),
                ),
            ],
            // What the closed field shows: the chosen one, without the tick
            // or the reason line, which belong to the menu.
            selectedItemBuilder: (BuildContext context) => <Widget>[
              for (final Reciter reciter in reciters)
                _ReciterEntry(reciter: reciter, inField: true),
            ],
            onChanged: (String? id) {
              final Reciter? picked = reciters
                  .where((Reciter r) => r.id == id)
                  .firstOrNull;
              if (picked != null) onChanged(picked);
            },
          ),
        ),
      ),
    );
  }
}

/// A reciter as the field and its menu draw them: the portrait in a thin
/// gold ring, the Arabic name over the English one, and — in the menu — the
/// attribution, a tick on the one chosen, and for one who cannot be picked,
/// why.
class _ReciterEntry extends StatelessWidget {
  const _ReciterEntry({
    required this.reciter,
    this.reason,
    this.chosen = false,
    this.inField = false,
  });

  final Reciter reciter;

  /// Why this reciter cannot be picked, or null when they can.
  final String? reason;
  final bool chosen;
  final bool inField;

  bool get enabled => reason == null;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color muted = colors.onSurfaceVariant;
    final Widget portrait = _Portrait(
      reciter: reciter,
      diameter: 40,
      ringed: chosen || inField,
    );

    // In the field: the portrait, and the Arabic name over the English
    // one, as the menu writes them.
    if (inField) {
      return Row(
        children: <Widget>[
          portrait,
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  reciter.nameAr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  reciter.nameEn,
                  style: theme.textTheme.labelMedium?.copyWith(color: muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      );
    }

    final String attribution = reciter.attribution.of(
      context.locale.languageCode,
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: 8.h),
        child: Row(
          children: <Widget>[
            portrait,
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    reciter.nameAr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: chosen ? colors.primary : colors.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    reciter.nameEn,
                    style: theme.textTheme.labelMedium?.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (enabled && attribution.isNotEmpty)
                    Text(
                      attribution,
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (reason != null)
                    Text(
                      reason!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.error,
                      ),
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            if (chosen) ...<Widget>[
              SizedBox(width: 8.w),
              Icon(
                Icons.check_circle_rounded,
                color: colors.primary,
                size: 22.r,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The portrait in a thin ring: gold for the reciter chosen, the outline
/// tone for the rest.
class _Portrait extends StatelessWidget {
  const _Portrait({
    required this.reciter,
    required this.diameter,
    required this.ringed,
  });

  final Reciter reciter;
  final double diameter;
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(2.r),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: ringed ? colors.secondary : colors.outline,
          width: 1.5,
        ),
      ),
      child: ReciterAvatar(reciter: reciter, diameter: diameter),
    );
  }
}
