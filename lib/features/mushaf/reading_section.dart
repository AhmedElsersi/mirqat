import 'package:equatable/equatable.dart';

import '../../domain/entities/ayah_ref.dart';

/// What "one at a time" reading is divided by.
enum SectionKind { surah, juz }

/// A request to read one surah or one juz on its own — what a route carries.
class SectionRequest extends Equatable {
  const SectionRequest(this.kind, this.number);

  const SectionRequest.surah(int number) : this(SectionKind.surah, number);
  const SectionRequest.juz(int number) : this(SectionKind.juz, number);

  final SectionKind kind;
  final int number;

  @override
  List<Object?> get props => <Object?>[kind, number];
}

/// One surah or one juz, as the pages it is printed on and the ayahs of those
/// pages that belong to it.
///
/// Everything here is read out of `quran.db` when the section is opened —
/// where it starts, where it ends, how many of its kind there are. Nothing
/// about any particular surah or juz is written down in code.
class ReadingSection extends Equatable {
  const ReadingSection({
    required this.kind,
    required this.number,
    required this.first,
    required this.last,
    required this.firstPage,
    required this.lastPage,
    required this.total,
    this.leadPage,
  });

  final SectionKind kind;
  final int number;

  /// The first and last ayah of the section, both included.
  final AyahRef first;
  final AyahRef last;

  /// The printed pages the section starts and ends on. Either may be shared
  /// with a neighbour, and then only this section's lines are shown on it.
  final int firstPage;
  final int lastPage;

  /// The page before [firstPage], when all it holds of this section is the
  /// opening surah's heading — the layout sometimes sets a heading as the
  /// last line of a page and the surah's first ayah on the next. Those lines
  /// are carried over to the top of [firstPage], so that the reader opens on
  /// the surah and not on a page that is bare but for its name.
  final int? leadPage;

  /// How many sections of this kind the mushaf has.
  final int total;

  SectionRequest get request => SectionRequest(kind, number);

  SectionRequest? get previous =>
      number > 1 ? SectionRequest(kind, number - 1) : null;

  SectionRequest? get next =>
      number < total ? SectionRequest(kind, number + 1) : null;

  bool holds(AyahRef ref) => ref.isWithin(first, last);

  @override
  List<Object?> get props => <Object?>[
    kind,
    number,
    first,
    last,
    firstPage,
    lastPage,
    total,
    leadPage,
  ];
}
