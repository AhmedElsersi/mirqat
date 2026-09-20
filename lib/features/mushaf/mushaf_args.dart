import 'package:equatable/equatable.dart';

import 'cubit/mushaf_page.dart';
import 'reading_section.dart';

/// Typed arguments for the mushaf route, carried in `state.extra`.
class MushafArgs extends Equatable {
  const MushafArgs({this.initialAyah, this.initialPage, this.section});

  /// Open on this ayah's page, highlighted. Wins over [initialPage].
  final AyahRef? initialAyah;

  /// Open on this page with nothing highlighted — coming back to where the
  /// reader left off. Null, with no [initialAyah] either, opens at page 1.
  final int? initialPage;

  /// Read this surah or juz on its own, with the next and the previous one
  /// offered at its end. Null is the whole mushaf, cover to cover.
  final SectionRequest? section;

  @override
  List<Object?> get props => <Object?>[initialAyah, initialPage, section];
}
