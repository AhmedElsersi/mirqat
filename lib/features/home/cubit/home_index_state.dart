import 'package:equatable/equatable.dart';

import '../../../data/models/app_settings.dart';
import '../../../data/models/juz_info.dart';
import '../../../data/models/reading_position.dart';
import '../../../data/models/surah.dart';

/// One juz on the home screen: where it begins, and in which surah.
class JuzItem extends Equatable {
  const JuzItem({required this.info, required this.surah});

  final JuzInfo info;
  final Surah surah;

  @override
  List<Object?> get props => <Object?>[info, surah];
}

/// A place the reader has been, with the surah's names looked up.
class PlaceItem extends Equatable {
  const PlaceItem({required this.position, required this.surah});

  final ReadingPosition position;
  final Surah surah;

  @override
  List<Object?> get props => <Object?>[position, surah];
}

class HomeIndexState extends Equatable {
  const HomeIndexState({
    this.ajzaa = const <JuzItem>[],
    this.history = const <PlaceItem>[],
    this.loaded = false,
  });

  final List<JuzItem> ajzaa;

  /// Newest first. The first entry is "where I left off".
  final List<PlaceItem> history;

  /// Whether the first read has finished — the home screen waits for this
  /// before deciding whether to open straight onto the mushaf.
  final bool loaded;

  PlaceItem? get last => history.isEmpty ? null : history.first;

  HomeIndexState copyWith({
    List<JuzItem>? ajzaa,
    List<PlaceItem>? history,
    bool? loaded,
  }) => HomeIndexState(
    ajzaa: ajzaa ?? this.ajzaa,
    history: history ?? this.history,
    loaded: loaded ?? this.loaded,
  );

  @override
  List<Object?> get props => <Object?>[ajzaa, history, loaded];
}

/// Where a launch lands: the mushaf page to open straight onto, or null to
/// stay on the index.
///
/// Only the mushaf view opens onto a page, and it opens onto the last one
/// read — page 1 on a fresh install. A function of its own, away from the
/// widget, because it is the rule the owner asked for and it should be
/// checkable without starting a mushaf to check it.
int? launchPage({required HomeViewMode mode, required ReadingPosition? last}) =>
    mode == HomeViewMode.mushaf ? (last?.page ?? 1) : null;

/// Where the reader left off — one place, whichever way it was set.
///
/// A mark the reader set by hand says where they stopped, and it wins over
/// what the app kept by itself. Without one, it is the first ayah of the
/// last page read, which the mushaf records as it is turned. A function of
/// its own for the same reason [launchPage] is: it is the rule, checkable
/// without a screen.
ReadingPosition? lastPlace({
  required ReadingPosition? mark,
  required ReadingPosition? history,
}) => mark ?? history;
