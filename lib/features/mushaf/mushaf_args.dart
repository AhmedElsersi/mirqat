import 'package:equatable/equatable.dart';

import 'cubit/mushaf_page.dart';

/// Typed arguments for the mushaf route, carried in `state.extra`.
class MushafArgs extends Equatable {
  const MushafArgs({this.initialAyah, this.initialPage});

  /// Open on this ayah's page, highlighted. Wins over [initialPage].
  final AyahRef? initialAyah;

  /// Open on this page with nothing highlighted — coming back to where the
  /// reader left off. Null, with no [initialAyah] either, opens at page 1.
  final int? initialPage;

  @override
  List<Object?> get props => <Object?>[initialAyah, initialPage];
}
