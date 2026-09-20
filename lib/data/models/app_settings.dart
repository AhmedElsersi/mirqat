import 'package:equatable/equatable.dart';

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

  static HomeViewMode fromStorage(String? value) {
    for (final HomeViewMode mode in HomeViewMode.values) {
      if (mode.storageValue == value) return mode;
    }
    return HomeViewMode.list;
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
    this.defaultRangeBehaviour = RangeBehaviour.wholeSurah,
    this.lastRanges = const <int, AyahRange>{},
    this.themeMode = AppThemeMode.system,
    this.homeViewMode = HomeViewMode.list,
    this.arabicFontSize = defaultArabicFontSize,
    this.audioQuality = AudioQuality.standard,
    this.downloadOverWifiOnly = true,
    this.onboardingSeen = false,
  });

  static const double defaultArabicFontSize = 24;
  static const double minArabicFontSize = 18;
  static const double maxArabicFontSize = 40;

  /// The connect mode a fresh install starts on.
  ///
  /// Continuous per the owner's decision: reciting the range straight through
  /// is the mode most people reach for first, and the drill modes are a
  /// deliberate choice made after that.
  static const ConnectMode defaultConnectModeValue = ConnectMode.continuous;

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
  final double arabicFontSize;

  /// Which bitrate downloads and streams ask for, where the reciter offers a
  /// choice.
  final AudioQuality audioQuality;

  /// Whether a pack may be fetched over mobile data.
  ///
  /// True by default: a surah is tens of megabytes, and someone on a metered
  /// plan should have to say so rather than find out afterwards.
  final bool downloadOverWifiOnly;

  /// Whether the introduction has been shown. False for a fresh install —
  /// and for one updating from before there was an introduction, which is
  /// deliberate: that update is also when the player screen went away, and
  /// the introduction is where the new way of working is explained.
  final bool onboardingSeen;

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
    RangeBehaviour? defaultRangeBehaviour,
    Map<int, AyahRange>? lastRanges,
    AppThemeMode? themeMode,
    HomeViewMode? homeViewMode,
    double? arabicFontSize,
    AudioQuality? audioQuality,
    bool? downloadOverWifiOnly,
    bool? onboardingSeen,
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
    defaultRangeBehaviour: defaultRangeBehaviour ?? this.defaultRangeBehaviour,
    lastRanges: lastRanges ?? this.lastRanges,
    themeMode: themeMode ?? this.themeMode,
    homeViewMode: homeViewMode ?? this.homeViewMode,
    arabicFontSize: arabicFontSize ?? this.arabicFontSize,
    audioQuality: audioQuality ?? this.audioQuality,
    downloadOverWifiOnly: downloadOverWifiOnly ?? this.downloadOverWifiOnly,
    onboardingSeen: onboardingSeen ?? this.onboardingSeen,
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
    'defaultRangeBehaviour': defaultRangeBehaviour.storageValue,
    // Hive stores plain maps, so the surah number becomes a string key and the
    // range a two-element list.
    'lastRanges': <String, List<int>>{
      for (final MapEntry<int, AyahRange> e in lastRanges.entries)
        '${e.key}': <int>[e.value.startAyah, e.value.endAyah],
    },
    'themeMode': themeMode.storageValue,
    'homeViewMode': homeViewMode.storageValue,
    'arabicFontSize': arabicFontSize,
    // The bitrate itself, not the enum name: it is the number the manifest
    // and every path use, so a stored 64 stays meaningful even if these cases
    // are ever renamed.
    'audioQuality': audioQuality.bitrate,
    'downloadOverWifiOnly': downloadOverWifiOnly,
    'onboardingSeen': onboardingSeen,
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
    defaultRangeBehaviour: RangeBehaviour.fromStorage(
      map['defaultRangeBehaviour'] as String?,
    ),
    lastRanges: _rangesFromStorage(map['lastRanges']),
    themeMode: AppThemeMode.fromStorage(map['themeMode'] as String?),
    homeViewMode: HomeViewMode.fromStorage(map['homeViewMode'] as String?),
    arabicFontSize:
        (map['arabicFontSize'] as num?)?.toDouble() ?? defaultArabicFontSize,
    audioQuality: AudioQuality.fromStorage(map['audioQuality']),
    downloadOverWifiOnly: map['downloadOverWifiOnly'] as bool? ?? true,
    onboardingSeen: map['onboardingSeen'] as bool? ?? false,
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
    defaultRangeBehaviour,
    lastRanges,
    themeMode,
    homeViewMode,
    arabicFontSize,
    audioQuality,
    downloadOverWifiOnly,
    onboardingSeen,
  ];
}
