import 'package:equatable/equatable.dart';

/// Somewhere the reader was: a surah, an ayah, the mushaf page it is on, and
/// when. The unit of both "open where I left off" and the history list.
class ReadingPosition extends Equatable {
  const ReadingPosition({
    required this.surahNumber,
    required this.ayahNumber,
    required this.page,
    required this.at,
  });

  factory ReadingPosition.fromMap(Map<dynamic, dynamic> map) => ReadingPosition(
    surahNumber: map['surah'] as int,
    ayahNumber: map['ayah'] as int,
    page: map['page'] as int,
    at: DateTime.fromMillisecondsSinceEpoch(map['at'] as int),
  );

  final int surahNumber;
  final int ayahNumber;
  final int page;
  final DateTime at;

  /// Whether [other] is the same place, whenever it was visited. Leaving a
  /// page and coming straight back is one visit, not two.
  bool samePlaceAs(ReadingPosition other) =>
      other.page == page && other.surahNumber == surahNumber;

  Map<String, Object> toMap() => <String, Object>{
    'surah': surahNumber,
    'ayah': ayahNumber,
    'page': page,
    'at': at.millisecondsSinceEpoch,
  };

  @override
  List<Object?> get props => <Object?>[surahNumber, ayahNumber, page, at];
}
