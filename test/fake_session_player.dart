import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/entities/ayah_ref.dart';
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

  StreamController<PlaybackMoment> _moments =
      StreamController<PlaybackMoment>.broadcast();
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();

  /// The recall clip map each load was handed, parallel to [loads].
  final List<Map<AyahRef, Duration>> recallClipLoads =
      <Map<AyahRef, Duration>>[];

  void reach(PlaybackUnit unit) =>
      _moments.add(PlaybackMoment(unit: unit, recalling: false));

  /// A recall gap for [unit] has begun.
  void recall(PlaybackUnit unit) =>
      _moments.add(PlaybackMoment(unit: unit, recalling: true));

  @override
  Future<void> load({
    required SessionPlan plan,
    required Reciter reciter,
    required List<Surah> surahs,
    int startAtUnit = 0,
    Map<AyahRef, Duration> recallClips = const <AyahRef, Duration>{},
  }) async {
    loads.add(SessionLoad(plan, reciter, surahs, startAtUnit));
    recallClipLoads.add(recallClips);
    _moments = StreamController<PlaybackMoment>.broadcast();
  }

  @override
  Stream<PlaybackMoment> get momentStream => _moments.stream;

  @override
  Stream<PlaybackUnit> get currentUnitStream => momentStream
      .where((PlaybackMoment m) => !m.recalling)
      .map((PlaybackMoment m) => m.unit);

  @override
  Stream<PlayerState> get playerStateStream => _states.stream;

  /// The queue has played out.
  void complete() => _states.add(PlayerState(false, ProcessingState.completed));

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
