import 'package:equatable/equatable.dart';

import '../../core/theme/quran_font.dart';
import 'reading_position.dart';

import '../../domain/entities/daily_wird.dart';
import '../../domain/entities/hifz_plan.dart';
import '../../domain/entities/interrupted_session.dart';
import '../../domain/entities/saved_preset.dart';
import '../../domain/entities/session_config.dart';

/// Theme preference. A local enum rather than Flutter's ThemeMode so the data
/// layer stays free of widget imports.
enum AppThemeMode {
  system('system'),
  light('light'),
  dark('dark');

  const AppThemeMode(this.storageValue);

  final String storageValue;

  static AppThemeMode fromStorage(String? value) {
    for (final AppThemeMode mode in AppThemeMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return AppThemeMode.system;
  }
}

/// How the home screen lays the catalog out.
enum HomeViewMode {
  list('list'),
  grid('grid'),

  /// The real mushaf, page after page. The app opens straight onto the last
  /// page read; the surah and ajzaa lists become the index behind it.
  mushaf('mushaf');

  const HomeViewMode(this.storageValue);

  final String storageValue;

  /// The default — for a fresh install and for a stored value that cannot be
  /// read. The mushaf per the owner's decision (October 2026; it was the list
  /// before): the app opens as a mushaf, and the lists are the index behind
  /// it.
  static HomeViewMode fromStorage(String? value) {
    for (final HomeViewMode mode in HomeViewMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return HomeViewMode.mushaf;
  }
}

/// How a turned page leaves the screen.
enum PageTurnStyle {
  /// The pager's own slide — one page pushes the other out.
  slide('slide'),

  /// A leaf of paper folding over its hinge, the way a printed page turns.
  paper('paper');

  const PageTurnStyle(this.storageValue);

  final String storageValue;

  /// The default — for a fresh install and for a stored value that cannot be
  /// read. The plain slide, per the owner's decision (October 2026): the
  /// paper fold is there for whoever turns it on in the settings.
  static PageTurnStyle fromStorage(String? value) {
    for (final PageTurnStyle style in PageTurnStyle.values) {
      if (style.storageValue == value) return style;
    }
    return PageTurnStyle.slide;
  }
}

/// How much of the page's text is covered while reading, for testing oneself
/// against it — the old practice of covering the page a little more each
/// pass. Covered words keep their place on the page; only their ink is
/// withheld, and a tap on one reveals its ayah.
enum MemorizationView {
  /// The page as it is printed.
  off('off'),

  /// Only the first word of each ayah shows — the cue to recite the rest.
  firstWords('first_words'),

  /// Every word is covered; the ayah markers alone say where each ayah is.
  markersOnly('markers_only');

  const MemorizationView(this.storageValue);

  final String storageValue;

  static MemorizationView fromStorage(Object? value) {
    for (final MemorizationView view in MemorizationView.values) {
      if (view.storageValue == value) return view;
    }
    return MemorizationView.off;
  }
}

/// Which ayah range a freshly opened surah starts with.
enum RangeBehaviour {
  /// Always the whole surah.
  wholeSurah('whole_surah'),

  /// The range last used for that surah, when there is one.
  lastUsed('last_used');

  const RangeBehaviour(this.storageValue);

  final String storageValue;

  static RangeBehaviour fromStorage(String? value) {
    for (final RangeBehaviour mode in RangeBehaviour.values) {
      if (mode.storageValue == value) return mode;
    }
    return RangeBehaviour.wholeSurah;
  }
}

/// The bitrate a download asks the CDN for.
///
/// The values are the ones the manifest publishes, not a made-up scale: a
/// reciter carries a default bitrate and may carry others, and a choice the
/// reciter does not offer falls back to theirs rather than failing
/// (CLAUDE.md A.5).
enum AudioQuality {
  low(32),
  standard(64),
  high(128);

  const AudioQuality(this.bitrate);

  /// kbps, and the `{bitrate}` segment of every audio and pack path.
  final int bitrate;

  static AudioQuality fromStorage(Object? value) {
    for (final AudioQuality quality in AudioQuality.values) {
      if (quality.bitrate == value) return quality;
    }
    return AudioQuality.standard;
  }
}

/// An ayah range remembered for one surah.
class AyahRange extends Equatable {
  const AyahRange({required this.startAyah, required this.endAyah});

  final int startAyah;
  final int endAyah;

  @override
  List<Object?> get props => <Object?>[startAyah, endAyah];
}

/// Everything the user can change, persisted between launches.
///
/// Stored as a single plain map under one key (see
/// [SettingsLocalDataSourceImpl]), so every field here needs a `toMap` entry
/// and a `fromMap` read with a default — a field absent from an older install's
/// map must resolve to its default rather than throwing.
class AppSettings extends Equatable {
  const AppSettings({
    this.reciterId,
    this.defaultRepeatCount = SessionConfig.defaultRepeatCount,
    this.defaultConnectMode = defaultConnectModeValue,
    this.defaultFinalFullPass,
    this.defaultIntraBlockPauseMs = SessionConfig.defaultIntraBlockPauseMs,
    this.defaultBetweenRepeatPauseMs =
        SessionConfig.defaultBetweenRepeatPauseMs,
    this.defaultBetweenStepsPauseMs = SessionConfig.defaultBetweenStepsPauseMs,
    this.defaultPlaybackSpeed = SessionConfig.defaultPlaybackSpeed,
    this.defaultRecallRounds = SessionConfig.defaultRecallRounds,
    this.defaultChainRecall = false,
    this.defaultPlayIstiadhah = false,
    this.defaultRangeBehaviour = RangeBehaviour.wholeSurah,
    this.lastRanges = const <int, AyahRange>{},
    this.themeMode = AppThemeMode.system,
    this.homeViewMode = HomeViewMode.mushaf,
    this.pageTurnStyle = PageTurnStyle.slide,
    this.arabicFontSize = defaultArabicFontSize,
    this.quranFont = QuranFont.fallback,
    this.audioQuality = AudioQuality.standard,
    this.readingMark,
    this.downloadOverWifiOnly = true,
    this.showReadingRibbon = true,
    this.memorizationView = MemorizationView.off,
    this.showStumbles = true,
    this.bookends = false,
    this.bookendTaken,
    this.savedPresets = const <SavedPreset>[],
    this.wird = const <WirdPart, WirdRange>{},
    this.hifzPlan,
    this.interruptedSession,
    this.onboardingSeen = false,
    this.updatePromptedAt,
  });

  static const double defaultArabicFontSize = 24;
  static const double minArabicFontSize = 18;
  static const double maxArabicFontSize = 40;

  /// The connect mode a fresh install starts on.
  ///
  /// Cumulative per the owner's decision (October 2026; it was continuous
  /// before): the talqeen drill — learn an ayah, then join it to everything
  /// learnt so far — is the app's reason to exist, so it is what a fresh
  /// install opens on.
  static const ConnectMode defaultConnectModeValue = ConnectMode.cumulative;

  /// Null means "whichever reciter the catalog lists first for the surah",
  /// so a fresh install works before anything is chosen.
  final String? reciterId;

  final int defaultRepeatCount;
  final ConnectMode defaultConnectMode;

  /// Null means "whatever the chosen connect mode defaults to", so changing
  /// mode moves the toggle with it until the user sets it explicitly.
  final bool? defaultFinalFullPass;

  final int defaultIntraBlockPauseMs;
  final int defaultBetweenRepeatPauseMs;
  final int defaultBetweenStepsPauseMs;
  final double defaultPlaybackSpeed;

  /// How many recall rounds a new session starts with — the silence after an
  /// ayah's learn step for the reader to recite it back into (see
  /// [SessionConfig.recallRounds]). 0, the product default, asks nothing.
  final int defaultRecallRounds;

  /// Whether a new session closes by testing each link of its range — "what
  /// comes next?" ([SessionConfig.chainRecall]). Off by default.
  final bool defaultChainRecall;

  /// Whether a new session opens with the isti'adhah, where the reciter has
  /// one ([SessionConfig.playIstiadhah]). Off by default.
  final bool defaultPlayIstiadhah;

  final RangeBehaviour defaultRangeBehaviour;

  /// Last range used, per surah number.
  ///
  /// Per surah rather than one global range: a range remembered from a 7-ayah
  /// surah is meaningless — and often out of bounds — in a 4-ayah one, so a
  /// single value would need clamping on every read and would still hand back
  /// a selection the reader never made.
  final Map<int, AyahRange> lastRanges;

  final AppThemeMode themeMode;
  final HomeViewMode homeViewMode;

  /// How the mushaf's pages turn — folding like paper, or the plain slide.
  final PageTurnStyle pageTurnStyle;
  final double arabicFontSize;

  /// The face the mushaf's text is drawn in ([QuranFont]).
  final QuranFont quranFont;

  /// Which bitrate downloads and streams ask for, where the reciter offers a
  /// choice.
  final AudioQuality audioQuality;

  /// Where the reader said they stopped: the ayah they marked, on its page.
  /// One mark, set by hand from the ayah's own menu, distinct from the
  /// history the app keeps by itself. Null: nothing marked.
  final ReadingPosition? readingMark;

  /// Whether a pack may be fetched over mobile data.
  ///
  /// True by default: a surah is tens of megabytes, and someone on a metered
  /// plan should have to say so rather than find out afterwards.
  final bool downloadOverWifiOnly;

  /// Whether the page the reading mark is on hangs a ribbon down its edge.
  /// On by default; the ribbon lies over the page's margin, translucent, and
  /// a reader who would rather have the page bare turns it off.
  final bool showReadingRibbon;

  /// How much of the page is covered while reading ([MemorizationView]).
  /// Off by default: the page is the printed page until the reader asks.
  final MemorizationView memorizationView;

  /// Whether ayahs the reader stumbles at are dotted on the page. On by
  /// default; the marks still make the drill longer either way.
  final bool showStumbles;

  /// Whether the Today card suggests the day's new portion again before
  /// sleep, and once more the next morning (NEW_IDEAS §5). Off by default:
  /// it is an option the reader takes up, not a routine laid on them.
  final bool bookends;

  /// The last bookend suggestion the reader took up (`Bookend.key`), so it
  /// is not made again. Null: none yet.
  final String? bookendTaken;

  /// Ways of working the reader named and saved, oldest first.
  final List<SavedPreset> savedPresets;

  /// The ranges the reader set for today's wird — new, recent, old — each
  /// kept until they change it.
  final DailyWird wird;

  /// The reader's plan to memorize a range in so many days, if they made
  /// one. Null: no plan.
  final HifzPlan? hifzPlan;

  /// The session the app was closed in the middle of, to offer back. Null:
  /// none — the last one played out, or was stopped on purpose.
  final InterruptedSession? interruptedSession;

  /// Whether the introduction has been shown. False for a fresh install —
  /// and for one updating from before there was an introduction, which is
  /// deliberate: that update is also when the player screen went away, and
  /// the introduction is where the new way of working is explained.
  final bool onboardingSeen;

  /// When an optional update was last mentioned, so that it is not mentioned
  /// again the same day. Null: never.
  final DateTime? updatePromptedAt;

  /// The remembered range for [surahNumber], or null when there is none or
  /// when the behaviour is set to always use the whole surah.
  AyahRange? rememberedRangeFor(int surahNumber) =>
      defaultRangeBehaviour == RangeBehaviour.lastUsed
      ? lastRanges[surahNumber]
      : null;

  AppSettings copyWith({
    String? reciterId,
    int? defaultRepeatCount,
    ConnectMode? defaultConnectMode,
    bool? defaultFinalFullPass,
    bool clearDefaultFinalFullPass = false,
    int? defaultIntraBlockPauseMs,
    int? defaultBetweenRepeatPauseMs,
    int? defaultBetweenStepsPauseMs,
    double? defaultPlaybackSpeed,
    int? defaultRecallRounds,
    bool? defaultChainRecall,
    bool? defaultPlayIstiadhah,
    RangeBehaviour? defaultRangeBehaviour,
    Map<int, AyahRange>? lastRanges,
    AppThemeMode? themeMode,
    HomeViewMode? homeViewMode,
    PageTurnStyle? pageTurnStyle,
    double? arabicFontSize,
    QuranFont? quranFont,
    AudioQuality? audioQuality,
    ReadingPosition? readingMark,
    bool clearReadingMark = false,
    bool? downloadOverWifiOnly,
    bool? showReadingRibbon,
    MemorizationView? memorizationView,
    bool? showStumbles,
    bool? bookends,
    String? bookendTaken,
    List<SavedPreset>? savedPresets,
    DailyWird? wird,
    HifzPlan? hifzPlan,
    bool clearHifzPlan = false,
    InterruptedSession? interruptedSession,
    bool clearInterruptedSession = false,
    bool? onboardingSeen,
    DateTime? updatePromptedAt,
  }) => AppSettings(
    reciterId: reciterId ?? this.reciterId,
    defaultRepeatCount: defaultRepeatCount ?? this.defaultRepeatCount,
    defaultConnectMode: defaultConnectMode ?? this.defaultConnectMode,
    // A nullable field cannot be reset through `??`, so clearing it back to
    // "follow the mode" is its own flag.
    defaultFinalFullPass: clearDefaultFinalFullPass
        ? null
        : (defaultFinalFullPass ?? this.defaultFinalFullPass),
    defaultIntraBlockPauseMs:
        defaultIntraBlockPauseMs ?? this.defaultIntraBlockPauseMs,
    defaultBetweenRepeatPauseMs:
        defaultBetweenRepeatPauseMs ?? this.defaultBetweenRepeatPauseMs,
    defaultBetweenStepsPauseMs:
        defaultBetweenStepsPauseMs ?? this.defaultBetweenStepsPauseMs,
    defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
    defaultRecallRounds: defaultRecallRounds ?? this.defaultRecallRounds,
    defaultChainRecall: defaultChainRecall ?? this.defaultChainRecall,
    defaultPlayIstiadhah: defaultPlayIstiadhah ?? this.defaultPlayIstiadhah,
    defaultRangeBehaviour: defaultRangeBehaviour ?? this.defaultRangeBehaviour,
    lastRanges: lastRanges ?? this.lastRanges,
    themeMode: themeMode ?? this.themeMode,
    homeViewMode: homeViewMode ?? this.homeViewMode,
    pageTurnStyle: pageTurnStyle ?? this.pageTurnStyle,
    arabicFontSize: arabicFontSize ?? this.arabicFontSize,
    quranFont: quranFont ?? this.quranFont,
    audioQuality: audioQuality ?? this.audioQuality,
    readingMark: clearReadingMark ? null : (readingMark ?? this.readingMark),
    downloadOverWifiOnly: downloadOverWifiOnly ?? this.downloadOverWifiOnly,
    showReadingRibbon: showReadingRibbon ?? this.showReadingRibbon,
    memorizationView: memorizationView ?? this.memorizationView,
    showStumbles: showStumbles ?? this.showStumbles,
    bookends: bookends ?? this.bookends,
    bookendTaken: bookendTaken ?? this.bookendTaken,
    savedPresets: savedPresets ?? this.savedPresets,
    wird: wird ?? this.wird,
    hifzPlan: clearHifzPlan ? null : (hifzPlan ?? this.hifzPlan),
    interruptedSession: clearInterruptedSession
        ? null
        : (interruptedSession ?? this.interruptedSession),
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
    updatePromptedAt: updatePromptedAt ?? this.updatePromptedAt,
  );

  /// Records [range] as the last one used for [surahNumber].
  AppSettings rememberRange(int surahNumber, AyahRange range) =>
      copyWith(lastRanges: <int, AyahRange>{...lastRanges, surahNumber: range});

  Map<String, dynamic> toMap() => <String, dynamic>{
    'reciterId': reciterId,
    'defaultRepeatCount': defaultRepeatCount,
    'defaultConnectMode': defaultConnectMode.name,
    'defaultFinalFullPass': defaultFinalFullPass,
    'defaultIntraBlockPauseMs': defaultIntraBlockPauseMs,
    'defaultBetweenRepeatPauseMs': defaultBetweenRepeatPauseMs,
    'defaultBetweenStepsPauseMs': defaultBetweenStepsPauseMs,
    'defaultPlaybackSpeed': defaultPlaybackSpeed,
    'defaultRecallRounds': defaultRecallRounds,
    'defaultChainRecall': defaultChainRecall,
    'defaultPlayIstiadhah': defaultPlayIstiadhah,
    'defaultRangeBehaviour': defaultRangeBehaviour.storageValue,
    // Hive stores plain maps, so the surah number becomes a string key and the
    // range a two-element list.
    'lastRanges': <String, List<int>>{
      for (final MapEntry<int, AyahRange> e in lastRanges.entries)
        '${e.key}': <int>[e.value.startAyah, e.value.endAyah],
    },
    'themeMode': themeMode.storageValue,
    'homeViewMode': homeViewMode.storageValue,
    'pageTurnStyle': pageTurnStyle.storageValue,
    'arabicFontSize': arabicFontSize,
    'quranFont': quranFont.storageValue,
    // The bitrate itself, not the enum name: it is the number the manifest
    // and every path use, so a stored 64 stays meaningful even if these cases
    // are ever renamed.
    'audioQuality': audioQuality.bitrate,
    'readingMark': readingMark?.toMap(),
    'downloadOverWifiOnly': downloadOverWifiOnly,
    'showReadingRibbon': showReadingRibbon,
    'memorizationView': memorizationView.storageValue,
    'showStumbles': showStumbles,
    'bookends': bookends,
    'bookendTaken': bookendTaken,
    'savedPresets': <Map<String, dynamic>>[
      for (final SavedPreset p in savedPresets) p.toMap(),
    ],
    'wird': dailyWirdToMap(wird),
    'hifzPlan': hifzPlan?.toMap(),
    'interruptedSession': interruptedSession?.toMap(),
    'onboardingSeen': onboardingSeen,
    'updatePromptedAt': updatePromptedAt?.millisecondsSinceEpoch,
  };

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) => AppSettings(
    reciterId: map['reciterId'] as String?,
    defaultRepeatCount:
        map['defaultRepeatCount'] as int? ?? SessionConfig.defaultRepeatCount,
    // Goes through ConnectMode.decodeStored so a retired value (`pairwise`)
    // resolves to its replacement rather than silently collapsing to the
    // default. The data source inspects the same decode to decide whether the
    // box needs rewriting — see SettingsLocalDataSourceImpl.read.
    defaultConnectMode: ConnectMode.decodeStored(
      map['defaultConnectMode'],
      absentFallback: defaultConnectModeValue,
    ).mode,
    defaultFinalFullPass: map['defaultFinalFullPass'] as bool?,
    defaultIntraBlockPauseMs:
        map['defaultIntraBlockPauseMs'] as int? ??
        SessionConfig.defaultIntraBlockPauseMs,
    defaultBetweenRepeatPauseMs:
        map['defaultBetweenRepeatPauseMs'] as int? ??
        SessionConfig.defaultBetweenRepeatPauseMs,
    defaultBetweenStepsPauseMs:
        map['defaultBetweenStepsPauseMs'] as int? ??
        SessionConfig.defaultBetweenStepsPauseMs,
    defaultPlaybackSpeed:
        (map['defaultPlaybackSpeed'] as num?)?.toDouble() ??
        SessionConfig.defaultPlaybackSpeed,
    // Read forgivingly and held to its bounds: a value the plan builder would
    // refuse must not reach it, or every session would fail to build.
    defaultRecallRounds: switch (map['defaultRecallRounds']) {
      final int n => n.clamp(
        SessionConfig.minRecallRounds,
        SessionConfig.maxRecallRounds,
      ),
      _ => SessionConfig.defaultRecallRounds,
    },
    defaultChainRecall: map['defaultChainRecall'] == true,
    defaultPlayIstiadhah: map['defaultPlayIstiadhah'] == true,
    defaultRangeBehaviour: RangeBehaviour.fromStorage(
      map['defaultRangeBehaviour'] as String?,
    ),
    lastRanges: _rangesFromStorage(map['lastRanges']),
    themeMode: AppThemeMode.fromStorage(map['themeMode'] as String?),
    homeViewMode: HomeViewMode.fromStorage(map['homeViewMode'] as String?),
    pageTurnStyle: PageTurnStyle.fromStorage(map['pageTurnStyle'] as String?),
    arabicFontSize:
        (map['arabicFontSize'] as num?)?.toDouble() ?? defaultArabicFontSize,
    quranFont: QuranFont.fromStorage(map['quranFont']),
    audioQuality: AudioQuality.fromStorage(map['audioQuality']),
    readingMark: switch (map['readingMark']) {
      final Map<dynamic, dynamic> m
          when m['surah'] is int && m['ayah'] is int && m['page'] is int =>
        ReadingPosition.fromMap(<dynamic, dynamic>{...m, 'at': m['at'] ?? 0}),
      _ => null,
    },
    downloadOverWifiOnly: map['downloadOverWifiOnly'] as bool? ?? true,
    showReadingRibbon: map['showReadingRibbon'] as bool? ?? true,
    memorizationView: MemorizationView.fromStorage(map['memorizationView']),
    showStumbles: map['showStumbles'] != false,
    bookends: map['bookends'] == true,
    bookendTaken: map['bookendTaken'] is String
        ? map['bookendTaken'] as String
        : null,
    savedPresets: <SavedPreset>[
      if (map['savedPresets'] is List)
        for (final Object? raw in map['savedPresets'] as List)
          ?SavedPreset.fromMap(raw),
    ],
    wird: dailyWirdFromMap(map['wird']),
    hifzPlan: HifzPlan.fromMap(map['hifzPlan']),
    interruptedSession: InterruptedSession.fromMap(map['interruptedSession']),
    onboardingSeen: map['onboardingSeen'] as bool? ?? false,
    updatePromptedAt: map['updatePromptedAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(map['updatePromptedAt'] as int)
        : null,
  );

  /// Reads the remembered ranges back, skipping anything malformed.
  ///
  /// A bad entry here is worth ignoring rather than throwing: it costs the
  /// reader one remembered selection, where refusing to load the settings at
  /// all would cost them the theme, the reciter and the font size too.
  static Map<int, AyahRange> _rangesFromStorage(Object? raw) {
    if (raw is! Map) return const <int, AyahRange>{};
    final Map<int, AyahRange> out = <int, AyahRange>{};
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final int? surah = int.tryParse('${entry.key}');
      final Object? value = entry.value;
      if (surah == null || value is! List || value.length != 2) continue;
      final Object? start = value[0];
      final Object? end = value[1];
      if (start is! int || end is! int || start < 1 || end < start) continue;
      out[surah] = AyahRange(startAyah: start, endAyah: end);
    }
    return Map<int, AyahRange>.unmodifiable(out);
  }

  @override
  List<Object?> get props => <Object?>[
    reciterId,
    defaultRepeatCount,
    defaultConnectMode,
    defaultFinalFullPass,
    defaultIntraBlockPauseMs,
    defaultBetweenRepeatPauseMs,
    defaultBetweenStepsPauseMs,
    defaultPlaybackSpeed,
    defaultRecallRounds,
    defaultChainRecall,
    defaultPlayIstiadhah,
    defaultRangeBehaviour,
    lastRanges,
    themeMode,
    homeViewMode,
    pageTurnStyle,
    arabicFontSize,
    quranFont,
    audioQuality,
    readingMark,
    downloadOverWifiOnly,
    showReadingRibbon,
    memorizationView,
    showStumbles,
    bookends,
    bookendTaken,
    savedPresets,
    wird,
    hifzPlan,
    interruptedSession,
    onboardingSeen,
    updatePromptedAt,
  ];
}
