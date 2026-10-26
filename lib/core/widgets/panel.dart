import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

/// A rounded card on the page's surface — the shape every screen outside the
/// mushaf is built from.
///
/// One widget rather than a private copy per screen: the radius, the outline
/// and the way ink is drawn on it are a decision about the app, not about a
/// screen.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding,
    this.filled = false,
    this.border,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  /// Tinted rather than outlined: a suggestion, not a task.
  final bool filled;

  /// An outline of its own — for the one card on a screen that is being
  /// acted on now.
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Material(
      color: filled ? colors.surfaceContainerHighest : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18.r),
        side: filled && border == null
            ? BorderSide.none
            : BorderSide(
                color: border ?? colors.outline,
                width: border == null ? 1 : 1.6,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
  }
}

/// A heading over a group of cards, with an optional way out to the whole of
/// what it heads.
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    required this.title,
    this.action,
    this.onAction,
    this.trailing,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  /// Said beside the heading rather than offered — a count, usually.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(4.w, 24.h, 4.w, 8.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// A label over a field or a group of rows, quieter than a [SectionTitle].
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(4.w, 20.h, 4.w, 8.h),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A small label in a pill: a tier, a part of the wird, a size, a state.
class AppTag extends StatelessWidget {
  const AppTag({
    required this.label,
    this.onHero = false,
    this.tone,
    this.gold = false,
    super.key,
  });

  final String label;

  /// A wash of gold under the ordinary text: the first tag on a card, the
  /// new portion, what is current.
  final bool gold;

  /// On the forest-green hero card, where the surface and the text invert.
  final bool onHero;

  /// A colour of its own — gold for a stale download, the error colour for a
  /// failure. The pill is a wash of it; the text stays readable on it.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color tint = tone ?? theme.colorScheme.onSurface;
    return Container(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 10.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: onHero
            ? AppColors.cream.withValues(alpha: 0.14)
            : gold
            ? AppColors.gold.withValues(alpha: 0.2)
            : tone == null
            ? theme.colorScheme.surfaceContainerHighest
            : tint.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: onHero ? AppColors.cream : tint,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A list row's icon, in a rounded square: the shape that tells a row's
/// subject from its actions.
class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {this.color, this.background, super.key});

  final IconData icon;
  final Color? color;

  /// The square's own colour — the surface, on a card that is already tinted.
  final Color? background;

  @override
  Widget build(BuildContext context) => Container(
    width: 40.r,
    height: 40.r,
    decoration: BoxDecoration(
      color:
          background ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12.r),
    ),
    child: Icon(icon, color: color),
  );
}

/// A bar that says how much of something is done. Gold, as every progress
/// fill in the app is.
class ProgressBar extends StatelessWidget {
  const ProgressBar({required this.value, this.height, this.color, super.key});

  final double value;
  final double? height;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3.r),
    child: LinearProgressIndicator(
      value: value.isNaN ? 0 : value.clamp(0.0, 1.0),
      minHeight: height ?? 6.r,
      color: color ?? AppColors.gold,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    ),
  );
}

/// A quiet line that explains rather than warns: an icon and a sentence in
/// the muted colour.
class AppNote extends StatelessWidget {
  const AppNote(this.text, {this.icon = Icons.info_outline, super.key});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: 4.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(top: 2.h),
            child: Icon(icon, size: 16.r, color: muted),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one button on a row that starts something: a solid circle in the
/// primary colour. A row has one of these at most.
class PlayButton extends StatelessWidget {
  const PlayButton({
    required this.onPressed,
    this.icon = Icons.play_arrow,
    this.tooltip,
    this.soft = false,
    super.key,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String? tooltip;

  /// Tinted rather than solid — a secondary start beside the main one.
  final bool soft;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: soft ? colors.surfaceContainerHighest : colors.primary,
        foregroundColor: soft ? colors.onSurface : colors.onPrimary,
        disabledBackgroundColor: colors.surfaceContainerHighest,
        disabledForegroundColor: colors.onSurfaceVariant,
        minimumSize: Size(44.r, 44.r),
        fixedSize: Size(44.r, 44.r),
      ),
    );
  }
}

/// A scrolling list drawn as one card: the rows share a bordered, rounded
/// surface with a divider between them, as a short list in an [AppCard]
/// does — but lazily, for an index of hundreds.
class ListCardView extends StatelessWidget {
  const ListCardView({
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    super.key,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return CustomScrollView(
      controller: controller,
      slivers: <Widget>[
        SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(16.w, 4.h, 16.w, 24.h),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.outline),
              borderRadius: BorderRadius.circular(18.r),
            ),
            sliver: SliverList.separated(
              itemCount: itemCount,
              itemBuilder: itemBuilder,
              separatorBuilder: (_, _) => const Divider(height: 1),
            ),
          ),
        ),
      ],
    );
  }
}
