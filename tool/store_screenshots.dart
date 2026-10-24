// Walks the real app through the scenes the store listings and the promo
// videos show, saying on stdout when each is ready, so that
// `tool/store_screenshots.sh` (or its Android twin) can photograph or film the
// device at that moment.
//
//     tool/store_screenshots.sh "iPhone 17 Pro Max" store/raw/iphone ar
//     tool/promo_video.sh       "iPhone 17 Pro Max" promo/raw
//
// It is the app itself — `main()` from `lib/main.dart`, the real catalog, the
// real CDN — driven by real taps where a reader would tap. What a reader would
// have built up over weeks (a wird, memorized surahs, a few weak spots) is
// written first through the app's own repositories and cubits, so the pages
// show a reader's app rather than an empty one. Run it on a device with
// nothing installed: the first thing it expects is the introduction.
//
// SHOT_MODE=shots prints `SHOT:<name>` once a scene is still.
// SHOT_MODE=video prints `REC:<name>` when filming should start and
// `REC:stop` when it should end, and moves at a pace a viewer can follow.
//
// ignore_for_file: avoid_print, depend_on_referenced_packages, use_build_context_synchronously

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/core/router/app_routes.dart';
import 'package:mirqat/core/theme/quran_font.dart';
import 'package:mirqat/data/models/app_settings.dart';
import 'package:mirqat/data/models/memorization_progress.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/progress_repository.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
import 'package:mirqat/domain/entities/daily_wird.dart';
import 'package:mirqat/features/home/screen/home_shell.dart';
import 'package:mirqat/features/mushaf/screen/mushaf_screen.dart';
import 'package:mirqat/features/mushaf/widgets/ayah_actions_sheet.dart';
import 'package:mirqat/features/mushaf/widgets/mushaf_page_view.dart';
import 'package:mirqat/features/my_hifz/my_hifz_view.dart';
import 'package:mirqat/features/onboarding/screen/onboarding_screen.dart';
import 'package:mirqat/features/session/cubit/session_cubit.dart';
import 'package:mirqat/features/session/cubit/session_state.dart';
import 'package:mirqat/features/session/widgets/session_bar.dart';
import 'package:mirqat/features/session/widgets/session_sheet.dart';
import 'package:mirqat/features/settings/cubit/settings_cubit.dart';
import 'package:mirqat/features/settings/screen/mushaf_font_screen.dart';
import 'package:mirqat/features/surah_list/screen/surah_list_screen.dart';
import 'package:mirqat/features/today/today_view.dart';
import 'package:mirqat/features/wird/widgets/wird_card.dart';
import 'package:mirqat/main.dart' as app;
import 'package:mirqat/services/qpc_font_service.dart';

const String kLocale = String.fromEnvironment(
  'SHOT_LOCALE',
  defaultValue: 'ar',
);

const bool kVideo = String.fromEnvironment('SHOT_MODE') == 'video';

/// How long a still scene is held for the camera.
const Duration kHold = Duration(seconds: 4);

late final LiveWidgetController ui;

/// The reader's wird: today's new portion, and the two reviews.
final WirdRange kFresh = WirdRange(from: AyahRef(2, 15), to: AyahRef(2, 21));
final WirdRange kRecent = WirdRange(from: AyahRef(2, 1), to: AyahRef(2, 14));
final WirdRange kOld = WirdRange(from: AyahRef(67, 1), to: AyahRef(67, 30));

Future<void> main() async {
  app.main();
  await Future<void>.delayed(const Duration(seconds: 2));
  ui = LiveWidgetController(WidgetsBinding.instance);

  try {
    await _run();
    print(kVideo ? 'REC:done' : 'SHOT:done');
  } on Object catch (e, stack) {
    print('SHOT:failed $e\n$stack');
    print('REC:failed $e');
  }
}

Future<void> _run() async {
  // --- the introduction ------------------------------------------------------
  await _until(
    () => _has(find.byType(OnboardingScreen)),
    'the introduction',
    // A first launch copies the mushaf's database out first; an emulator
    // takes its time.
    seconds: 90,
  );
  if (kLocale != 'ar') {
    await ui.element(find.byType(OnboardingScreen)).setLocale(Locale(kLocale));
    await _settle(2);
  }
  if (kVideo) await _rec('intro');
  // Leaf by leaf, as a reader would; each turn is let finish before the next.
  for (int i = 0; i < 12 && _has(find.byType(OnboardingScreen)); i++) {
    await _settle(kVideo ? 2.2 : 1.2);
    if (_has(find.byType(OnboardingScreen))) {
      await _tap(_onlyFilledButton(find.byType(OnboardingScreen)));
    }
  }
  // A first launch opens on the mushaf itself, the home beneath it.
  await _until(
    () => _has(find.byType(HomeShell, skipOffstage: false)),
    'the home page',
  );
  await _settle(2);
  if (_has(find.byType(MushafPageView))) await _back();
  if (kVideo) await _stop();

  // --- what a reader has built up ---------------------------------------------
  await _seed();
  await _settle(2);

  // --- Today -----------------------------------------------------------------
  // The home may open on another tab; Today is chosen as a reader would.
  if (!_has(find.byType(TodayView))) {
    await _tap(find.byIcon(Icons.wb_twilight_outlined));
  }
  await _until(() => _has(find.byType(TodayView)), 'Today');
  await _settle(2);
  if (kVideo) {
    await _rec('today');
    await _settle(8);
  } else {
    await _shoot('01-today');
  }

  // --- reading, in the Madinah print -----------------------------------------
  await _openPage(_tab, 562);
  await _until(() => _has(find.byType(MushafPageView)), 'a mushaf page');
  await _settle(3);
  if (kVideo) {
    await _settle(3);
    await _back();
    await _stop();
  } else {
    await _shoot('02-reading');
    await _back();
  }

  // --- a review with recall rounds, from Today --------------------------------
  if (kVideo) await _rec('recall');
  openWirdPart(_home, WirdPart.recent, kRecent);
  await _until(() => _has(find.byType(SessionBar)), 'the reading view');
  final SessionCubit session = _session();
  await _until(
    () =>
        session.state.phase == SessionPhase.failed ||
        (session.state.playing && session.state.currentUnit != null),
    'the recitation to start',
    seconds: 60,
  );
  if (session.state.phase == SessionPhase.failed) {
    throw StateError('The session did not start: ${session.state.errorDetail}');
  }
  await _until(
    () =>
        !session.state.recalling &&
        (session.state.currentUnit?.ayahNumber ?? 0) >= 2,
    'the second ayah',
    seconds: 60,
  );
  await _settle(1);
  if (!kVideo) await _shoot('03-session');
  await _until(() => session.state.recalling, 'a recall gap', seconds: 90);
  await _settle(0.8);
  if (!kVideo) await _shoot('04-recall');
  if (kVideo) {
    await _until(
      () => !session.state.recalling,
      'the gap to close',
      seconds: 30,
    );
    await _settle(4);
  }

  // --- the session's ways of working ------------------------------------------
  if (kVideo) {
    await _stop();
    await _rec('presets');
  }
  await _tap(
    find.descendant(
      of: find.byType(SessionBar),
      matching: find.byIcon(Icons.tune),
    ),
  );
  await _until(() => _has(find.byType(SessionSheet)), 'the session sheet');
  await _settle(2);
  if (kVideo) {
    await _settle(2);
    await ui.drag(find.byType(SessionSheet), const Offset(0, -500));
    await _settle(3);
  } else {
    await _shoot('07-presets');
  }
  await _tap(
    find
        .descendant(
          of: find.byType(SessionSheet),
          matching: find.byIcon(Icons.close),
        )
        .first,
  );
  await _settle(1);
  session.stop();
  await _settle(1);
  await _back();
  if (kVideo) await _stop();

  // --- the memorization view ---------------------------------------------------
  final SettingsCubit settings = _settings();
  await settings.setMemorizationView(MemorizationView.firstWords);
  if (kVideo) await _rec('cover');
  await _openPage(_tab, 562);
  await _until(() => _has(find.byType(MushafPageView)), 'the covered page');
  await _settle(3);
  if (!kVideo) await _shoot('05-memorization');
  // A tap on a covered ayah shows it.
  final Finder words = _words();
  if (_has(words)) {
    await ui.tap(words.at(12));
    await _settle(kVideo ? 3 : 1.5);
  }

  // --- the ayah menu: "I stumble here" ----------------------------------------
  await settings.setMemorizationView(MemorizationView.off);
  await _settle(1.5);
  if (kVideo) {
    await _stop();
    await _rec('stumble');
    await _settle(1.5);
  }
  await ui.longPress(_words().at(30));
  await _until(() => _has(find.byType(AyahActionsSheet)), 'the ayah menu');
  await _settle(2);
  if (kVideo) {
    await _settle(3);
  } else {
    await _shoot('06-ayah-menu');
  }
  Navigator.of(ui.element(find.byType(AyahActionsSheet))).pop();
  await _settle(1);
  await _back();

  // --- the mushaf tab: weak spots on the surah list ---------------------------
  if (kVideo) {
    await _stop();
    await _rec('index');
  }
  await _tap(find.byIcon(Icons.menu_book_outlined));
  await _until(() => _has(find.byType(SurahListScreen)), 'the mushaf tab');
  await _settle(2);
  if (kVideo) {
    await _settle(2);
    await ui.drag(find.byType(SurahListScreen), const Offset(0, -300));
    await _settle(4);
    await _stop();
  } else {
    await _shoot('09-mushaf-index');
  }

  // --- My hifz -------------------------------------------------------------------
  if (kVideo) await _rec('hifz');
  await _tap(find.byIcon(Icons.layers_outlined));
  await _until(() => _has(find.byType(MyHifzView)), 'My hifz');
  await _settle(2);
  if (kVideo) {
    await _settle(7);
    await _stop();
  } else {
    await _shoot('08-my-hifz');
  }

  // --- the mushaf's face --------------------------------------------------------
  if (kVideo) await _rec('font');
  unawaited(_home.pushNamed<void>(AppRoutes.mushafFontName));
  await _until(() => _has(find.byType(MushafFontScreen)), 'the font page');
  await _settle(3);
  if (kVideo) {
    await _settle(6);
    await _back();
    await _stop();
  } else {
    await _shoot('10-font');
    await _back();
  }

  await _tap(find.byIcon(Icons.wb_twilight_outlined));
  await _settle(1);
}

/// A reader some weeks in: Juz' 'Amma, Al-Fatiha, Ya-Sin and Al-Mulk held,
/// the opening of Al-Baqarah under review, a few places where they slip, and
/// the Madinah print as their face.
Future<void> _seed() async {
  final SettingsCubit settings = _settings();
  await settings.setQuranFont(QuranFont.qpcV2);
  await settings.setDefaultRecallRounds(1);
  await settings.setWird(WirdPart.fresh, kFresh);
  await settings.setWird(WirdPart.recent, kRecent);
  await settings.setWird(WirdPart.old, kOld);

  final List<Surah> surahs = (await sl<QuranRepository>().getSurahs())
      .getOrElse(() => <Surah>[]);
  final ProgressRepository progress = sl<ProgressRepository>();
  Future<void> held(int surah, [int? upTo]) async {
    final int last = upTo ?? surahs[surah - 1].ayahCount;
    for (int a = 1; a <= last; a++) {
      await progress.setStatus(surah, a, MemorizationStatus.memorized);
    }
  }

  for (final int s in <int>[1, 36, 67, for (int s = 78; s <= 114; s++) s]) {
    await held(s);
  }
  await held(2, 14);
  for (final (int s, int a) in <(int, int)>[
    (2, 9),
    (2, 12),
    (67, 15),
    (78, 30),
  ]) {
    await progress.markStumble(s, a);
  }

  // The pages the scenes show, in the Madinah print's own fonts.
  final QpcFontService fonts = sl<QpcFontService>();
  for (final int page in <int>[2, 3, 562, 563]) {
    await fonts.ensure(page);
  }
}

// --- helpers -----------------------------------------------------------------

BuildContext get _home =>
    ui.element(find.byType(HomeShell, skipOffstage: false));

/// Inside the home's providers, where the tabs are.
BuildContext get _tab =>
    ui.element(find.byType(TodayView, skipOffstage: false));

SettingsCubit _settings() => BlocProvider.of<SettingsCubit>(_home);

SessionCubit _session() =>
    BlocProvider.of<SessionCubit>(ui.element(find.byType(MushafView)));

Future<void> _openPage(BuildContext context, int page) async {
  unawaited(openMushaf(context, page: page));
  await _settle(1);
}

/// Every word on the pages in view that can be pressed.
Finder _words() => find.descendant(
  of: find.byType(MushafPageView),
  matching: find.byWidgetPredicate(
    (Widget w) => w is GestureDetector && w.onLongPress != null,
  ),
);

Future<void> _back() async {
  final NavigatorState nav = Navigator.of(
    ui.element(find.byType(Scaffold).last),
  );
  if (nav.canPop()) nav.pop();
  await _settle(1.5);
}

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
  await _settle(kVideo ? 1.2 : 0.6);
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

/// Filming starts, and is given a moment to be rolling before anything moves:
/// the simulator's recorder takes a few seconds to start.
Future<void> _rec(String name) async {
  print('REC:$name');
  await _settle(4.5);
}

Future<void> _stop() async {
  await _settle(0.5);
  print('REC:stop');
  await _settle(1.5);
}
