import 'package:equatable/equatable.dart';

import '../../data/models/ayah.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../domain/entities/session_plan.dart';

/// Typed arguments for the player route, carried in `state.extra`.
class PlayerArgs extends Equatable {
  const PlayerArgs({
    required this.plan,
    required this.surah,
    required this.reciter,
    required this.ayahs,
  });

  final SessionPlan plan;
  final Surah surah;
  final Reciter reciter;

  /// Every ayah of the surah, so the player can show the whole selected range.
  final List<Ayah> ayahs;

  @override
  List<Object?> get props => <Object?>[plan, surah, reciter, ayahs];
}
