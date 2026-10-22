import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/number_extensions.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/widgets/panel.dart';

/// One step of the guide: what it is about, and what to do.
class HowToStep {
  const HowToStep(this.icon, this.titleKey, this.bodyKey);

  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

/// How the app is used, in the order someone would meet it.
///
/// In the app and not in `app.json`: it describes this build's own screens and
/// gestures, so it has to change with them, in the same commit — a guide
/// fetched from elsewhere would describe whichever version its author last
/// looked at.
class HowToUseScreen extends StatelessWidget {
  const HowToUseScreen({super.key});

  static const List<HowToStep> steps = <HowToStep>[
    HowToStep(
      Icons.auto_stories_outlined,
      LocaleKeys.howtoReadTitle,
      LocaleKeys.howtoReadBody,
    ),
    HowToStep(
      Icons.play_circle_outline,
      LocaleKeys.howtoListenTitle,
      LocaleKeys.howtoListenBody,
    ),
    HowToStep(
      Icons.touch_app_outlined,
      LocaleKeys.howtoRangeTitle,
      LocaleKeys.howtoRangeBody,
    ),
    HowToStep(
      Icons.link,
      LocaleKeys.howtoModesTitle,
      LocaleKeys.howtoModesBody,
    ),
    HowToStep(
      Icons.record_voice_over_outlined,
      LocaleKeys.howtoRecallTitle,
      LocaleKeys.howtoRecallBody,
    ),
    HowToStep(
      Icons.bookmark_add_outlined,
      LocaleKeys.howtoPresetsTitle,
      LocaleKeys.howtoPresetsBody,
    ),
    HowToStep(
      Icons.tune,
      LocaleKeys.howtoChangeTitle,
      LocaleKeys.howtoChangeBody,
    ),
    HowToStep(
      Icons.visibility_off_outlined,
      LocaleKeys.howtoViewTitle,
      LocaleKeys.howtoViewBody,
    ),
    HowToStep(
      Icons.flag_outlined,
      LocaleKeys.howtoStumbleTitle,
      LocaleKeys.howtoStumbleBody,
    ),
    HowToStep(
      Icons.hearing_outlined,
      LocaleKeys.howtoTasmeeTitle,
      LocaleKeys.howtoTasmeeBody,
    ),
    HowToStep(
      Icons.event_repeat,
      LocaleKeys.howtoReviewTitle,
      LocaleKeys.howtoReviewBody,
    ),
    HowToStep(
      Icons.flag_circle_outlined,
      LocaleKeys.howtoPlanTitle,
      LocaleKeys.howtoPlanBody,
    ),
    HowToStep(
      Icons.compare_arrows,
      LocaleKeys.howtoSimilarTitle,
      LocaleKeys.howtoSimilarBody,
    ),
    HowToStep(
      Icons.download_outlined,
      LocaleKeys.howtoOfflineTitle,
      LocaleKeys.howtoOfflineBody,
    ),
    HowToStep(
      Icons.save_alt,
      LocaleKeys.howtoBackupTitle,
      LocaleKeys.howtoBackupBody,
    ),
    HowToStep(
      Icons.history,
      LocaleKeys.howtoResumeTitle,
      LocaleKeys.howtoResumeBody,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.aboutHowToUse.tr())),
      body: ListView(
        padding: EdgeInsetsDirectional.all(16.r),
        children: <Widget>[
          for (int i = 0; i < steps.length; i++)
            _StepCard(number: i + 1, step: steps[i]),
          SizedBox(height: 4.h),
          OutlinedButton.icon(
            onPressed: () => context.pushNamed(AppRoutes.onboardingName),
            icon: const Icon(Icons.slideshow_outlined),
            label: Text(LocaleKeys.aboutShowIntro.tr()),
          ),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.number, required this.step});

  final int number;
  final HowToStep step;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Padding(
      padding: EdgeInsetsDirectional.only(bottom: 12.h),
      child: AppCard(
        padding: EdgeInsetsDirectional.all(16.r),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 16.r,
              backgroundColor: colors.primary,
              child: Text(
                number.toLocalisedString(),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onPrimary,
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          step.titleKey.tr(),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Icon(step.icon, color: colors.primary, size: 22.r),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    step.bodyKey.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
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
