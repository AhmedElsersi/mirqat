import 'package:equatable/equatable.dart';

/// Where a juz begins: read out of `quran.db`, never written down here
/// (CLAUDE.md A.2 rule 2).
class JuzInfo extends Equatable {
  const JuzInfo({
    required this.number,
    required this.surahNumber,
    required this.ayahNumber,
    required this.page,
  });

  final int number;
  final int surahNumber;
  final int ayahNumber;
  final int page;

  @override
  List<Object?> get props => <Object?>[number, surahNumber, ayahNumber, page];
}
