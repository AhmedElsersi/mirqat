import 'package:equatable/equatable.dart';

import 'ayah_ref.dart';

/// The three parts of the reader's daily wird: what is memorized new, what
/// was memorized lately and is gone over again, and what is kept from long
/// ago. Each is named by the key the session sheet marks its chip by.
enum WirdPart {
  fresh('new'),
  recent('recent'),
  old('old');

  const WirdPart(this.key);

  final String key;

  static WirdPart? fromKey(Object? key) =>
      WirdPart.values.where((WirdPart p) => p.key == key).firstOrNull;
}

/// The range the reader set for one part of the wird. It stays until they
/// change it: there is no day it belongs to, so none is ever missed.
class WirdRange extends Equatable {
  const WirdRange({required this.from, required this.to});

  final AyahRef from;
  final AyahRef to;

  Map<String, dynamic> toMap() => <String, dynamic>{
    'from': <int>[from.surah, from.ayah],
    'to': <int>[to.surah, to.ayah],
  };

  /// Read forgivingly: anything that is not two ends in order is no range,
  /// never a failure of the settings around it.
  static WirdRange? fromMap(Object? raw) {
    if (raw is! Map) return null;
    AyahRef? end(Object? v) => v is List && v.length == 2
        ? switch ((v[0], v[1])) {
            (final int s, final int a) when s >= 1 && a >= 1 => AyahRef(s, a),
            _ => null,
          }
        : null;
    final AyahRef? from = end(raw['from']);
    final AyahRef? to = end(raw['to']);
    if (from == null || to == null || to < from) return null;
    return WirdRange(from: from, to: to);
  }

  @override
  List<Object?> get props => <Object?>[from, to];
}

/// The parts of the wird the reader has set, by part. Absent: not set.
typedef DailyWird = Map<WirdPart, WirdRange>;

Map<String, dynamic> dailyWirdToMap(DailyWird wird) => <String, dynamic>{
  for (final MapEntry<WirdPart, WirdRange> e in wird.entries)
    e.key.key: e.value.toMap(),
};

DailyWird dailyWirdFromMap(Object? raw) {
  if (raw is! Map) return const <WirdPart, WirdRange>{};
  return <WirdPart, WirdRange>{
    for (final MapEntry<dynamic, dynamic> e in raw.entries)
      if (WirdPart.fromKey(e.key) case final WirdPart part)
        if (WirdRange.fromMap(e.value) case final WirdRange range) part: range,
  };
}
