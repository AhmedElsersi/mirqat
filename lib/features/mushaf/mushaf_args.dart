import 'package:equatable/equatable.dart';

import 'cubit/mushaf_page.dart';

/// Typed arguments for the mushaf route, carried in `state.extra`.
class MushafArgs extends Equatable {
  const MushafArgs({this.initialAyah});

  /// Open on this ayah's page, highlighted. Null opens at the first page.
  final AyahRef? initialAyah;

  @override
  List<Object?> get props => <Object?>[initialAyah];
}
