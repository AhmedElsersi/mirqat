import 'package:equatable/equatable.dart';

/// Where a mushaf page sits: the surah, juz and hizb of the first word printed
/// on it — what a printed mushaf writes in the margin of that page.
class PageInfo extends Equatable {
  const PageInfo({
    required this.surahNumber,
    required this.juz,
    required this.hizb,
  });

  final int surahNumber;
  final int juz;
  final int hizb;

  @override
  List<Object?> get props => <Object?>[surahNumber, juz, hizb];
}
