import 'package:equatable/equatable.dart';

enum MemorizationStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  memorized('memorized');

  const MemorizationStatus(this.storageValue);

  final String storageValue;

  static MemorizationStatus fromStorage(String? value) {
    for (final MemorizationStatus status in MemorizationStatus.values) {
      if (status.storageValue == value) return status;
    }
    return MemorizationStatus.notStarted;
  }
}

/// Memorization state for one ayah.
///
/// Persisted as a plain map rather than through a generated Hive adapter, so
/// the project needs neither `build_runner` nor `hive_ce_generator`
/// (CLAUDE.md A.4 allows neither).
class MemorizationProgress extends Equatable {
  const MemorizationProgress({
    required this.surahNumber,
    required this.ayahNumber,
    this.status = MemorizationStatus.notStarted,
    this.lastSessionAt,
    this.cumulativeRepeats = 0,
  });

  final int surahNumber;
  final int ayahNumber;
  final MemorizationStatus status;
  final DateTime? lastSessionAt;

  /// Every repetition this ayah has been played across all sessions.
  final int cumulativeRepeats;

  /// Storage key: `<surah>:<ayah>`.
  String get storageKey => keyFor(surahNumber, ayahNumber);

  static String keyFor(int surahNumber, int ayahNumber) =>
      '$surahNumber:$ayahNumber';

  MemorizationProgress copyWith({
    MemorizationStatus? status,
    DateTime? lastSessionAt,
    int? cumulativeRepeats,
  }) => MemorizationProgress(
    surahNumber: surahNumber,
    ayahNumber: ayahNumber,
    status: status ?? this.status,
    lastSessionAt: lastSessionAt ?? this.lastSessionAt,
    cumulativeRepeats: cumulativeRepeats ?? this.cumulativeRepeats,
  );

  Map<String, dynamic> toMap() => <String, dynamic>{
    'surahNumber': surahNumber,
    'ayahNumber': ayahNumber,
    'status': status.storageValue,
    'lastSessionAt': lastSessionAt?.toIso8601String(),
    'cumulativeRepeats': cumulativeRepeats,
  };

  factory MemorizationProgress.fromMap(Map<dynamic, dynamic> map) {
    final Object? lastSessionAt = map['lastSessionAt'];
    return MemorizationProgress(
      surahNumber: map['surahNumber'] as int,
      ayahNumber: map['ayahNumber'] as int,
      status: MemorizationStatus.fromStorage(map['status'] as String?),
      lastSessionAt: lastSessionAt is String
          ? DateTime.tryParse(lastSessionAt)
          : null,
      cumulativeRepeats: map['cumulativeRepeats'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    surahNumber,
    ayahNumber,
    status,
    lastSessionAt,
    cumulativeRepeats,
  ];
}
