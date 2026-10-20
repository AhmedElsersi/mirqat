import 'package:equatable/equatable.dart';

import '../session/session_request.dart';
import 'cubit/mushaf_page.dart';
import 'reading_section.dart';

/// Typed arguments for the mushaf route, carried in `state.extra`.
class MushafArgs extends Equatable {
  const MushafArgs({
    this.initialAyah,
    this.initialPage,
    this.section,
    this.session,
  });

  /// Open on this ayah's page, highlighted. Wins over [initialPage].
  final AyahRef? initialAyah;

  /// Open on this page with nothing highlighted — coming back to where the
  /// reader left off. Null, with no [initialAyah] either, opens at page 1.
  final int? initialPage;

  /// Read this surah or juz on its own, with the next and the previous one
  /// offered at its end. Null is the whole mushaf, cover to cover.
  final SectionRequest? section;

  /// A session to set up on the way in — a weak spot to drill, a review that
  /// is due — and, if it says so, to start.
  final SessionRequest? session;

  @override
  List<Object?> get props => <Object?>[
    initialAyah,
    initialPage,
    section,
    session,
  ];
}
