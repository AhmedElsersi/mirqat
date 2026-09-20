import 'package:equatable/equatable.dart';

/// One ayah, by surah and number — the address everything that spans surahs
/// is written in.
///
/// Ordered the way the mushaf is: by surah, then by ayah.
class AyahRef extends Equatable implements Comparable<AyahRef> {
  const AyahRef(this.surah, this.ayah);

  final int surah;
  final int ayah;

  @override
  int compareTo(AyahRef other) =>
      surah != other.surah ? surah - other.surah : ayah - other.ayah;

  bool operator <(AyahRef other) => compareTo(other) < 0;
  bool operator <=(AyahRef other) => compareTo(other) <= 0;
  bool operator >(AyahRef other) => compareTo(other) > 0;
  bool operator >=(AyahRef other) => compareTo(other) >= 0;

  /// Whether this ayah lies in `from..to`, both ends included.
  bool isWithin(AyahRef from, AyahRef to) => this >= from && this <= to;

  @override
  List<Object?> get props => <Object?>[surah, ayah];

  @override
  String toString() => '$surah:$ayah';
}
