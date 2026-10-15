import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';

/// Plays a stretch of the chosen recording, so a cut can be judged by ear.
///
/// An interface because the cubit is tested without an audio device, and
/// because the screen should not care how the sound is made.
abstract class SegmentPreview {
  /// Plays [source] from [from] to [to], replacing whatever was playing.
  Future<void> play(
    File source, {
    required Duration from,
    required Duration to,
  });

  Future<void> stop();

  /// True while something is playing; false when it stops or runs out.
  Stream<bool> get playing;

  /// Where playback has reached, measured from the start of the stretch
  /// being played — zero at [play]'s `from`, and `to - from` at its end.
  ///
  /// Within the stretch and not within the recording, because that is what
  /// the player actually reports once a clip is set, and the one real device
  /// this runs on is the measure of what the fakes must do.
  Stream<Duration> get position;

  Future<void> dispose();
}

/// [SegmentPreview] over `just_audio`, which is already the app's player.
///
/// It plays the *recording* between two times, not an exported clip: nothing
/// is encoded to listen, so an operator nudging a boundary hears the change at
/// once. `setFilePath` and `setClip` are used rather than building an
/// `AudioSource` by hand — that stays `AudioResolver`'s job in this codebase
/// (CLAUDE.md A.6), and this file has no business knowing where the app's
/// audio lives.
class JustAudioSegmentPreview implements SegmentPreview {
  JustAudioSegmentPreview({AudioPlayer? player})
    : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  String? _loadedPath;

  /// Every operation on [_player] runs through this chain, one at a time.
  ///
  /// The player is one shared device and its methods are long `await`
  /// sequences. Two [play] calls close together — an operator stepping down
  /// the review list faster than a clip loads — used to interleave: the
  /// first tap's `setClip` could land *after* the second's, and from then on
  /// every row replayed the first row's stretch while the screen named
  /// another. Serialised, the later tap always acts last.
  Future<void> _serial = Future<void>.value();

  /// Which request is the newest. A queued operation that is no longer the
  /// newest does nothing: the tap it belonged to has been overtaken.
  int _generation = 0;

  @override
  Future<void> play(
    File source, {
    required Duration from,
    required Duration to,
  }) {
    final int mine = ++_generation;
    return _serial = _serial.then((_) async {
      if (mine != _generation) return;
      // Pause, never stop: `stop` tears the platform player down, and
      // `setClip` after it races the rebuild — which is exactly the state
      // a stale clip gets stuck in. A paused player keeps its decoder and
      // takes the new clip deterministically.
      await _player.pause();
      try {
        if (_loadedPath != source.path) {
          await _player.setFilePath(source.path);
          _loadedPath = source.path;
        }
        await _player.setClip(start: from, end: to);
        await _player.seek(Duration.zero);
      } on Object {
        // Whatever state the player was left in, it is not the state the
        // cache claims: the next play must load afresh.
        _loadedPath = null;
        rethrow;
      }
      if (mine != _generation) return;
      // Not awaited: `play` completes when playback ends, and the caller
      // wants to get on with showing that something is playing.
      unawaited(_player.play());
    });
  }

  @override
  Future<void> stop() {
    final int mine = ++_generation;
    return _serial = _serial.then((_) async {
      if (mine != _generation) return;
      await _player.pause();
    });
  }

  @override
  Stream<Duration> get position => _player.positionStream;

  @override
  Stream<bool> get playing => _player.playerStateStream
      .map(
        (PlayerState state) =>
            state.playing &&
            state.processingState != ProcessingState.completed &&
            state.processingState != ProcessingState.idle,
      )
      .distinct();

  @override
  Future<void> dispose() => _player.dispose();
}
