// Walks the real app through the scenes the store listings show, pausing on
// each one and saying so on stdout, so that `tool/store_screenshots.sh` can
// photograph the simulator at that moment.
//
//     tool/store_screenshots.sh "iPhone 17 Pro Max" store/apple/iphone ar
//
// It is the app itself — `main()` from `lib/main.dart`, the real catalog, the
// real CDN — driven by real taps, so a screenshot cannot show something the
// app does not do. Run it on a simulator with nothing installed: the first
// thing it expects is the introduction.
//
// ignore_for_file: avoid_print, depend_on_referenced_packages

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:mirqat/features/onboarding/screen/onboarding_screen.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/session/cubit/session_state.dart';
import 'package:mirqat/features/session/widgets/session_bar.dart';
import 'package:mirqat/features/session/widgets/session_sheet.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';
import 'package:mirqat/features/settings/screen/settings_screen.dart';
import 'package:mirqat/features/surah_list/screen/surah_list_screen.dart';
import 'package:mirqat/features/surah_list/widgets/surah_row.dart';
import 'package:mirqat/main.dart' as app;

const String kLocale = String.fromEnvironment(
  'SHOT_LOCALE',
  defaultValue: 'ar',
);

/// How long a scene is held still for the camera.
const Duration kHold = Duration(seconds: 4);

late final LiveWidgetController ui;

Future<void> main() async {
  app.main();
  await Future<void>.delayed(const Duration(seconds: 2));
  ui = LiveWidgetController(WidgetsBinding.instance);

  try {
    await _run();
    print('SHOT:done');
  } on Object catch (e, stack) {
    print('SHOT:failed $e\n$stack');
  }
}

Future<void> _run() async {
  // --- the introduction ------------------------------------------------------
  await _until(() => _has(find.byType(OnboardingScreen)), 'the introduction');
  if (kLocale != 'ar') {
    await ui.element(find.byType(OnboardingScreen)).setLocale(Locale(kLocale));
    await _settle(2);
  }
  await _tap(_onlyFilledButton(find.byType(OnboardingScreen)));
  await _settle(1);
  await _shoot('06-method');

  // Through to the end, the way a reader would.
  for (int i = 0; i < OnboardingScreen.pages.length - 1; i++) {
    await _tap(_onlyFilledButton(find.byType(OnboardingScreen)));
    await _settle(1);
  }
  await _until(() => _has(find.byType(SurahRow)), 'the home page');

  // --- reading ---------------------------------------------------------------
  // The third surah: it opens on a full page under its own heading.
  await _tap(find.byType(SurahRow).at(2));
  await _until(() => _has(find.byType(MushafPageView)), 'a mushaf page');
  await _settle(2);
  await _shoot('01-reading');

  // --- a session, over the text ----------------------------------------------
  await _tap(find.byType(MushafPageView).first);
  await _settle(1);
  await _tap(_onlyFilledButton(find.byType(SessionBar)));
  final SessionCubit session = BlocProvider.of<SessionCubit>(
    ui.element(find.byType(MushafView)),
  );
  await _until(
    () =>
        session.state.phase == SessionPhase.failed ||
        (session.state.playing && session.state.currentUnit != null),
    'the recitation to start',
    seconds: 40,
  );
  if (session.state.phase == SessionPhase.failed) {
    throw StateError('The session did not start: ${session.state.errorDetail}');
  }
  // Into the second ayah, so that the mark is somewhere down the page.
  await _until(
    () => (session.state.currentUnit?.ayahNumber ?? 0) >= 2,
    'the second ayah',
    seconds: 40,
  );
  await _settle(1);
  await _shoot('02-session');

  await _tap(find.byIcon(Icons.tune));
  await _until(() => _has(find.byType(SessionSheet)), 'the session sheet');
  await _settle(2);
  await _shoot('04-session-settings');
  await _tap(find.byIcon(Icons.close));
  await _settle(1);
  await _tap(find.byIcon(Icons.stop));
  await _settle(1);

  // --- home, with somewhere to continue from ---------------------------------
  await _tap(find.byType(BackButtonIcon));
  await _until(() => _has(find.byType(SurahRow)), 'the home page again');
  await _settle(2);
  await _shoot('03-home');

  // --- settings --------------------------------------------------------------
  await _tap(find.byIcon(Icons.settings_outlined));
  await _until(() => _has(find.byType(SettingsScreen)), 'settings');
  await _settle(1);
  await _shoot('07-settings');

  // The grid, chosen where a reader would choose it.
  await BlocProvider.of<SettingsCubit>(
    ui.element(find.byType(SettingsScreen)),
  ).setHomeViewMode(HomeViewMode.grid);
  await _tap(find.byType(BackButton));
  await _until(() => _has(find.byType(SurahListScreen)), 'home, as a grid');
  await _settle(1);

  // --- the ajzaa -------------------------------------------------------------
  final double reach = ui.getSize(find.byType(TabBarView)).width * 0.8;
  // The second tab is on the right where the page reads right to left.
  await ui.drag(
    find.byType(TabBarView),
    Offset(kLocale == 'ar' ? reach : -reach, 0),
  );
  await _settle(2);
  await _shoot('05-ajzaa');
}

// --- helpers -----------------------------------------------------------------

bool _has(Finder finder) => finder.evaluate().isNotEmpty;

Finder _onlyFilledButton(Finder within) => find
    .descendant(
      of: within,
      matching: find.byWidgetPredicate((Widget w) => w is FilledButton),
    )
    .first;

Future<void> _tap(Finder finder) async {
  await _until(() => _has(finder), '$finder');
  await ui.tap(finder);
  await _settle(0.6);
}

Future<void> _settle(num seconds) =>
    Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()));

Future<void> _until(
  bool Function() ready,
  String what, {
  int seconds = 25,
}) async {
  final DateTime giveUp = DateTime.now().add(Duration(seconds: seconds));
  while (!ready()) {
    if (DateTime.now().isAfter(giveUp)) {
      throw TimeoutException('Waited $seconds s for $what.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<void> _shoot(String name) async {
  print('SHOT:$name');
  await Future<void>.delayed(kHold);
}
