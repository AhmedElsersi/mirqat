import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/localization/locale_keys.dart';

/// Shared failure state: the developer-facing detail plus a way back.
class ErrorView extends StatelessWidget {
  const ErrorView({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 40.r,
              color: theme.colorScheme.error,
            ),
            SizedBox(height: 12.h),
            Text(
              LocaleKeys.commonError.tr(),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8.h),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...<Widget>[
              SizedBox(height: 16.h),
              FilledButton(
                onPressed: onRetry,
                child: Text(LocaleKeys.commonRetry.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
