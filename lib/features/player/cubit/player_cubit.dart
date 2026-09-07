import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:just_audio/just_audio.dart' as ja;

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
    emit(state.copyWith(status: LoadStatus.loading));

    try {
      await _player.load(
        plan: args.plan,
        reciter: args.reciter,
        surah: args.surah,
      );
    } catch (e) {
      emit(state.copyWith(status: LoadStatus.failure, errorMessage: '$e'));
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

    _stateSub = _player.playerStateStream.listen((ja.PlayerState playerState) {
      final bool finished =
          playerState.processingState == ja.ProcessingState.completed;
      emit(state.copyWith(playing: playerState.playing, finished: finished));
      if (finished) unawaited(_recordProgress());
    });

    emit(state.copyWith(status: LoadStatus.ready));
    await _player.play();
  }

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
    await _player.stop();
    return super.close();
  }
}
