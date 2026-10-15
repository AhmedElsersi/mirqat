import 'package:equatable/equatable.dart';

/// Where a mushaf page sits: the surah, juz, hizb and rub' of the first word
/// printed on it — what a printed mushaf writes in the margin of that page.
class PageInfo extends Equatable {
  const PageInfo({
    required this.surahNumber,
    required this.juz,
    required this.hizb,
    required this.rub,
  });

  final int surahNumber;
  final int juz;
  final int hizb;

  /// The rub' al-hizb, 1..240 over the whole mushaf. Four to a hizb, so which
  /// quarter of [hizb] the page opens in is `(rub - 1) % 4`.
  final int rub;

  @override
  List<Object?> get props => <Object?>[surahNumber, juz, hizb, rub];
}
