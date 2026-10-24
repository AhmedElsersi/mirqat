import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/desktop.dart';
import '../../../core/di/injection.dart';
import '../../../core/localization/locale_keys.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/reading_position.dart';
import '../../../data/models/surah.dart';
import '../../my_hifz/cubit/my_hifz_cubit.dart';
import '../../my_hifz/my_hifz_view.dart';
import '../../review/cubit/review_cubit.dart';
import '../../settings/cubit/settings_cubit.dart';
import '../../settings/cubit/settings_state.dart';
import '../../settings/screen/settings_screen.dart';
import '../../stats/cubit/stats_cubit.dart';
import '../../surah_list/cubit/surah_list_cubit.dart';
import '../../surah_list/cubit/surah_list_state.dart';
import '../../surah_list/screen/surah_list_screen.dart';
import '../../today/today_view.dart';
import '../../update/cubit/update_cubit.dart';
import '../cubit/home_index_cubit.dart';
import '../cubit/home_index_state.dart';

/// The four places the app is used from, one tap apart (design/README.md):
/// **Today** — what to do now; **Mushaf** — where to read; **My hifz** —
/// what has been memorized and every tool for keeping it; **Settings**.
///
/// Each tab keeps its place while another is shown. The reading view opens
/// over all of them, full screen.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<SurahListCubit>(
          create: (_) => sl<SurahListCubit>()..load(),
        ),
        BlocProvider<HomeIndexCubit>(
          create: (_) => sl<HomeIndexCubit>()..load(),
        ),
        BlocProvider<ReviewCubit>(create: (_) => sl<ReviewCubit>()..load()),
        // Read when their tab is first opened, not at launch: nothing on
        // the first screen needs them, and the mutashabihat index they count
        // is the reading view's to load first.
        BlocProvider<MyHifzCubit>(create: (_) => sl<MyHifzCubit>()),
        BlocProvider<StatsCubit>(create: (_) => sl<StatsCubit>()),
      ],
      child: const _HomeShellView(),
    );
  }
}

/// The tabs, in the order of the bar.
enum HomeTab { today, mushaf, hifz, settings }

/// Which tab is open, kept outside the widget tree: changing the interface
/// language rebuilds the app from the top, and the reader who switched it
/// from Settings must still be in Settings afterwards.
class HomeTabs extends ValueNotifier<HomeTab> {
  HomeTabs() : super(HomeTab.today);
}

class _HomeShellView extends StatefulWidget {
  const _HomeShellView();

  @override
  State<_HomeShellView> createState() => _HomeShellViewState();
}

class _HomeShellViewState extends State<_HomeShellView> {
  final HomeTabs _tabs = sl<HomeTabs>();
  HomeTab get _tab => _tabs.value;

  /// Whether this launch has already decided how to open. It is decided
  /// exactly once, the first moment the settings and the history are both
  /// known — and never again. Coming *back* from the mushaf must stay here;
  /// and choosing "mushaf" in Settings must not throw the mushaf open over
  /// the Settings tab, which is what re-deciding on every change did.
  bool _launchDecided = false;

  /// Whether this launch has looked for an update yet. Asked from here, the
  /// first screen past the splash and the introduction, and once: the cubit
  /// goes on listening for a newer `app.json` by itself.
  bool _updateChecked = false;

  void _checkForUpdate(SettingsState settings) {
    if (_updateChecked || !settings.settingsRead) return;
    _updateChecked = true;
    // After the frame: this runs during build, and the answer may be a state
    // change in a cubit above this widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UpdateCubit>().check(
        lastPrompted: settings.settings.updatePromptedAt,
      );
    });
  }

  /// In mushaf mode the app opens on the last page read, with the tabs
  /// underneath it — so "back" from the mushaf lands here, and there is
  /// always a way to another surah, the history and the settings.
  void _decideLaunch(HomeViewMode mode, PlaceItem? last, bool loaded) {
    if (_launchDecided || !loaded) return;
    _launchDecided = true;
    final int? page = launchPage(mode: mode, last: last?.position);
    if (page == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) openMushaf(context, page: page);
    });
  }

  /// Where the reader left off — the mark they set, or the page the app
  /// kept — with the surah's names looked up. Null before anything is read.
  PlaceItem? _lastPlace(SettingsState settings, HomeIndexState index) {
    final ReadingPosition? position = lastPlace(
      mark: settings.settings.readingMark,
      history: index.last?.position,
    );
    if (position == null) return null;
    final Surah? surah = context.read<HomeIndexCubit>().surahOf(
      position.surahNumber,
    );
    return surah == null ? null : PlaceItem(position: position, surah: surah);
  }

  @override
  void initState() {
    super.initState();
    // Rebuilt with My hifz already open — a language change does that.
    if (_tab == HomeTab.hifz) _readHifz();
  }

  void _readHifz() {
    final MyHifzCubit hifz = context.read<MyHifzCubit>();
    if (hifz.state.status == LoadStatus.initial) hifz.load();
    // The practice record is not a store the cubit watches: read afresh.
    context.read<StatsCubit>().load();
  }

  void _select(int i) {
    final HomeTab tab = HomeTab.values[i];
    if (tab == _tab) return;
    if (tab == HomeTab.hifz) _readHifz();
    setState(() => _tabs.value = tab);
  }

  @override
  Widget build(BuildContext context) {
    final SettingsState settings = context.watch<SettingsCubit>().state;
    final HomeIndexState index = context.watch<HomeIndexCubit>().state;
    final PlaceItem? last = _lastPlace(settings, index);
    if (settings.status.isReady) {
      _decideLaunch(settings.settings.homeViewMode, last, index.loaded);
    }
    _checkForUpdate(settings);

    void openPlace() {
      if (last != null) openMushaf(context, page: last.position.page);
    }

    final List<Surah> surahs = context.select<SurahListCubit, List<Surah>>(
      (SurahListCubit c) => <Surah>[
        for (final SurahListItem i in c.state.items) i.surah,
      ],
    );

    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: <Widget>[
          SafeArea(
            bottom: false,
            child: DesktopWidth(
              child: TodayView(
                settings: settings.settings,
                surahs: surahs,
                place: last,
                onOpenPlace: openPlace,
                onWirdChanged: context.read<SettingsCubit>().setWird,
                onBookendTaken: context.read<SettingsCubit>().takeBookend,
              ),
            ),
          ),
          SurahListScreen(place: last, onOpenPlace: openPlace),
          const SafeArea(
            bottom: false,
            child: DesktopWidth(child: MyHifzView()),
          ),
          const SettingsScreen(),
        ],
      ),
      // A hairline above the bar, as the design draws it: the bar is the
      // page's own surface, and only the line tells it from the list above.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: BorderDirectional(
            top: BorderSide(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _tab.index,
          onDestinationSelected: _select,
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.wb_twilight_outlined),
              selectedIcon: const Icon(Icons.wb_twilight),
              label: LocaleKeys.tabsToday.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: LocaleKeys.tabsMushaf.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.layers_outlined),
              selectedIcon: const Icon(Icons.layers),
              label: LocaleKeys.tabsHifz.tr(),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: LocaleKeys.tabsSettings.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
