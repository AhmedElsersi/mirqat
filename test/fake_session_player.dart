import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/services/audio/memorization_player_service.dart';
import 'package:mirqat/services/audio/playback_queue.dart';

class SessionLoad {
  const SessionLoad(this.plan, this.reciter, this.surahs, this.startAtUnit);

  final SessionPlan plan;
  final Reciter reciter;
  final List<Surah> surahs;
  final int startAtUnit;
}

/// The player, without a player: records what it is asked to do and lets a
/// test say which ayah has been reached.
class FakeSessionPlayer implements MemorizationPlayerService {
  final List<SessionLoad> loads = <SessionLoad>[];
  final List<double> speeds = <double>[];

  /// +1 for each skip to the next step, -1 for each skip back.
  final List<int> skips = <int>[];
  int playCalls = 0;
  int ended = 0;
  bool failOnPlay = false;

  StreamController<PlaybackUnit> _units =
      StreamController<PlaybackUnit>.broadcast();
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();

  void reach(PlaybackUnit unit) => _units.add(unit);

  @override
  Future<void> load({
    required SessionPlan plan,
    required Reciter reciter,
    required List<Surah> surahs,
    int startAtUnit = 0,
  }) async {
    loads.add(SessionLoad(plan, reciter, surahs, startAtUnit));
    _units = StreamController<PlaybackUnit>.broadcast();
  }

  @override
  Stream<PlaybackUnit> get currentUnitStream => _units.stream;

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  @override
  Future<void> play() async {
    playCalls++;
    if (failOnPlay) throw PlayerException(0, 'Source error', null);
    _states.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async =>
      _states.add(PlayerState(false, ProcessingState.ready));

  @override
  Future<void> stop() async {}

  @override
  Future<void> skipToNextStep() async => skips.add(1);

  @override
  Future<void> skipToPreviousStep() async => skips.add(-1);

  @override
  Stream<LoadedSession?> get sessionStream =>
      const Stream<LoadedSession?>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> endSession() async => ended++;

  @override
  Future<void> setSpeed(double speed) async => speeds.add(speed);

  @override
  bool get streamsAnyAyah => true;

  @override
  PlaybackQueueBuilder get queueBuilder => const PlaybackQueueBuilder();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
