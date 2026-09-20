import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// One group of settings, in a container of its own: a heading, then the
/// controls, on a surface a shade off the page so that where one group ends
/// and the next begins is seen rather than read.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    required this.title,
    required this.children,
    this.icon,
    super.key,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 16.h),
      // A Material, not a decorated box: the rows inside are list tiles, and
      // a tile's ink is drawn on the nearest Material — a plain coloured box
      // in between would paint over it.
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
          side: BorderSide(color: colors.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(16.w, 14.h, 16.w, 8.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 20.r, color: colors.primary),
                    SizedBox(width: 8.w),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// A row in a [SettingsCard] that leads to a page of its own.
class SettingsLinkRow extends StatelessWidget {
  const SettingsLinkRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsetsDirectional.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    // Directional on purpose: the affordance points the way the language
    // reads, so it mirrors with the locale.
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
