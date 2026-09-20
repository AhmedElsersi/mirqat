import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/locale_keys.dart';
import '../../../core/router/app_routes.dart';
import '../../settings/cubit/settings_cubit.dart';

class OnboardingPage {
  const OnboardingPage(this.icon, this.titleKey, this.bodyKey);

  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

/// The introduction: four leaves on what the app is for and how it is worked,
/// shown once on first launch and again, on request, from How to use.
///
/// Icons and words only. No ayah appears on it — an ayah used as decoration
/// on a slide is an ayah cropped to fit one (CLAUDE.md A.2 rule 7).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const List<OnboardingPage> pages = <OnboardingPage>[
    OnboardingPage(
      Icons.auto_stories_outlined,
      LocaleKeys.onboardingReadTitle,
      LocaleKeys.onboardingReadBody,
    ),
    OnboardingPage(
      Icons.stairs_outlined,
      LocaleKeys.onboardingMethodTitle,
      LocaleKeys.onboardingMethodBody,
    ),
    OnboardingPage(
      Icons.touch_app_outlined,
      LocaleKeys.onboardingControlTitle,
      LocaleKeys.onboardingControlBody,
    ),
    OnboardingPage(
      Icons.self_improvement_outlined,
      LocaleKeys.onboardingYoursTitle,
      LocaleKeys.onboardingYoursBody,
    ),
  ];

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _index = 0;

  bool get _last => _index == OnboardingScreen.pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Read to the end or skipped, it has been seen. Reached from How to use it
  /// is on top of something and goes back to it; on first launch it is the
  /// only thing there is, and gives way to the home page.
  void _finish() {
    context.read<SettingsCubit>().markOnboardingSeen();
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed(AppRoutes.surahListName);
    }
  }

  void _next() => _last
      ? _finish()
      : _controller.nextPage(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: 8.w, top: 4.h),
                // Kept in the layout on the last leaf so that the leaves do
                // not jump when it goes — invisible, and deaf too: a button
                // nobody can see must not be one somebody can press.
                child: IgnorePointer(
                  ignoring: _last,
                  child: Visibility.maintain(
                    visible: !_last,
                    child: TextButton(
                      onPressed: _finish,
                      child: Text(LocaleKeys.onboardingSkip.tr()),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: OnboardingScreen.pages.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext context, int i) =>
                    _Leaf(page: OnboardingScreen.pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < OnboardingScreen.pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsetsDirectional.symmetric(horizontal: 4.w),
                    width: i == _index ? 22.w : 8.w,
                    height: 8.h,
                    decoration: BoxDecoration(
                      color: i == _index ? colors.primary : colors.outline,
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(24.w, 20.h, 24.w, 20.h),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(
                    _last
                        ? LocaleKeys.onboardingStart.tr()
                        : LocaleKeys.onboardingNext.tr(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Leaf extends StatelessWidget {
  const _Leaf({required this.page});

  final OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    // Scrolls rather than overflows: at the largest system font the body is
    // taller than a small phone.
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 132.r,
              height: 132.r,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                shape: BoxShape.circle,
                border: Border.all(color: colors.secondary, width: 2),
              ),
              child: Icon(page.icon, size: 60.r, color: colors.primary),
            ),
            SizedBox(height: 32.h),
            Text(
              page.titleKey.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              page.bodyKey.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}
