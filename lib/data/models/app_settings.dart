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

/// Everything the user can change, persisted between launches.
class AppSettings extends Equatable {
  const AppSettings({
    this.reciterId,
    this.defaultRepeatCount = SessionConfig.defaultRepeatCount,
    this.defaultConnectMode = ConnectMode.cumulative,
    this.themeMode = AppThemeMode.system,
    this.arabicFontSize = defaultArabicFontSize,
  });

  static const double defaultArabicFontSize = 24;
  static const double minArabicFontSize = 18;
  static const double maxArabicFontSize = 40;

  /// Null means "whichever reciter the catalog lists first for the surah",
  /// so a fresh install works before anything is chosen.
  final String? reciterId;

  final int defaultRepeatCount;
  final ConnectMode defaultConnectMode;
  final AppThemeMode themeMode;
  final double arabicFontSize;

  AppSettings copyWith({
    String? reciterId,
    int? defaultRepeatCount,
    ConnectMode? defaultConnectMode,
    AppThemeMode? themeMode,
    double? arabicFontSize,
  }) => AppSettings(
    reciterId: reciterId ?? this.reciterId,
    defaultRepeatCount: defaultRepeatCount ?? this.defaultRepeatCount,
    defaultConnectMode: defaultConnectMode ?? this.defaultConnectMode,
    themeMode: themeMode ?? this.themeMode,
    arabicFontSize: arabicFontSize ?? this.arabicFontSize,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'reciterId': reciterId,
    'defaultRepeatCount': defaultRepeatCount,
    'defaultConnectMode': defaultConnectMode.name,
    'themeMode': themeMode.storageValue,
    'arabicFontSize': arabicFontSize,
  };

  factory AppSettings.fromMap(Map<dynamic, dynamic> map) => AppSettings(
    reciterId: map['reciterId'] as String?,
    defaultRepeatCount:
        map['defaultRepeatCount'] as int? ?? SessionConfig.defaultRepeatCount,
    defaultConnectMode: ConnectMode.values.firstWhere(
      (ConnectMode m) => m.name == map['defaultConnectMode'],
      orElse: () => ConnectMode.cumulative,
    ),
    themeMode: AppThemeMode.fromStorage(map['themeMode'] as String?),
    arabicFontSize:
        (map['arabicFontSize'] as num?)?.toDouble() ?? defaultArabicFontSize,
  );

  @override
  List<Object?> get props => <Object?>[
    reciterId,
    defaultRepeatCount,
    defaultConnectMode,
    themeMode,
    arabicFontSize,
  ];
}
