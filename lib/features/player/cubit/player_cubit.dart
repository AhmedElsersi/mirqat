import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../../core/error/exceptions.dart';
import '../../../core/state/load_status.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../domain/entities/playback_unit.dart';
import '../../../services/audio/memorization_player_service.dart';
import '../../../services/keep_awake_service.dart';
import '../player_args.dart';
import 'player_state.dart';

class PlayerCubit extends Cubit<PlayerScreenState> {
  PlayerCubit({
    required MemorizationPlayerService playerService,
    required ProgressRepository progressRepository,
    required KeepAwakeService keepAwakeService,
  }) : _player = playerService,
       _progress = progressRepository,
       _keepAwake = keepAwakeService,
       super(const PlayerScreenState());

  final MemorizationPlayerService _player;
  final ProgressRepository _progress;
  final KeepAwakeService _keepAwake;

  StreamSubscription<PlaybackUnit>? _unitSub;
  StreamSubscription<ja.PlayerState>? _stateSub;

  PlayerArgs? _args;

  /// How many times each ayah has actually been recited this session. Written
  /// to storage when the session ends or is stopped, so a session abandoned
  /// halfway still counts what it played.
  final Map<int, int> _playedPerAyah = <int, int>{};

  Future<void> start(PlayerArgs args) async {
    _args = args;
    // Retry calls this again on the same cubit, so the previous attempt's
    // subscriptions have to go first or a second stream would double-count
    // every repeat.
    await _unitSub?.cancel();
    await _stateSub?.cancel();
    _unitSub = null;
    _stateSub = null;
    emit(
      PlayerScreenState(status: LoadStatus.loading, keepAwake: state.keepAwake),
    );

    try {
      await _player.load(
        plan: args.plan,
        reciter: args.reciter,
        surah: args.surah,
      );
    } catch (e) {
      _fail(e);
      return;
    }

    _unitSub = _player.currentUnitStream.listen((PlaybackUnit unit) {
      _playedPerAyah.update(
        unit.ayahNumber,
        (int count) => count + 1,
        ifAbsent: () => 1,
      );
      emit(state.copyWith(currentUnit: unit));
    });

    _stateSub = _player.playerStateStream.listen(
      (ja.PlayerState playerState) {
        final bool finished =
            playerState.processingState == ja.ProcessingState.completed;
        emit(state.copyWith(playing: playerState.playing, finished: finished));
        if (finished) unawaited(_recordProgress());
      },
      // A connection lost mid-session surfaces here rather than at load. What
      // was recited up to that point is still worth keeping.
      onError: (Object error) {
        unawaited(_recordProgress());
        _fail(error);
      },
    );

    emit(state.copyWith(status: LoadStatus.ready));

    // The first clip is opened here, so an unreachable source raises on this
    // call rather than on load.
    try {
      await _player.play();
    } catch (e) {
      _fail(e);
    }
  }

  /// Ends the session in a failure the listener can read.
  void _fail(Object error) => emit(
    state.copyWith(
      status: LoadStatus.failure,
      failure: classifyFailure(error, streamsAnyAyah: _player.streamsAnyAyah),
      errorMessage: '$error',
    ),
  );

  /// Which sentence the listener gets.
  ///
  /// The exception itself only ever says *that* a source would not open —
  /// `PlayerException` carries a platform code, not a cause — so what
  /// separates the two cases is the queue: if every clip was already on the
  /// device, the network is not what went missing, and telling someone to
  /// check their connection would send them after the wrong thing.
  @visibleForTesting
  static PlayerFailure classifyFailure(
    Object error, {
    required bool streamsAnyAyah,
  }) => switch (error) {
    SessionConfigException() => PlayerFailure.configuration,
    _ when streamsAnyAyah => PlayerFailure.audioUnreachable,
    _ => PlayerFailure.unknown,
  };

  Future<void> togglePlayPause() =>
      state.playing ? _player.pause() : _player.play();

  Future<void> nextStep() => _player.skipToNextStep();

  Future<void> previousStep() => _player.skipToPreviousStep();

  Future<void> restartStep() => _player.restartCurrentStep();

  Future<void> stop() async {
    await _player.stop();
    await _recordProgress();
    emit(state.copyWith(playing: false));
  }

  Future<void> setKeepAwake(bool enabled) async {
    await _keepAwake.setEnabled(enabled);
    emit(state.copyWith(keepAwake: enabled));
  }

  /// Writes what was actually recited, then clears the tally so a stop
  /// followed by a completion cannot double-count.
  Future<void> _recordProgress() async {
    final PlayerArgs? args = _args;
    if (args == null || _playedPerAyah.isEmpty) return;

    final Map<int, int> tally = Map<int, int>.from(_playedPerAyah);
    _playedPerAyah.clear();

    final DateTime now = DateTime.now();
    for (final MapEntry<int, int> entry in tally.entries) {
      await _progress.recordRepeats(
        args.surah.number,
        entry.key,
        entry.value,
        at: now,
      );
    }
  }

  @override
  Future<void> close() async {
    await _unitSub?.cancel();
    await _stateSub?.cancel();
    await _recordProgress();
    await _keepAwake.setEnabled(false);
    // Not just stop(): leaving the screen ends the session, and the lock
    // screen should stop offering to resume it.
    await _player.endSession();
    return super.close();
  }
}
