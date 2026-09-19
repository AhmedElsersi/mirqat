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

  @override
  Future<void> play(
    File source, {
    required Duration from,
    required Duration to,
  }) async {
    await _player.stop();
    if (_loadedPath != source.path) {
      await _player.setFilePath(source.path);
      _loadedPath = source.path;
    }
    await _player.setClip(start: from, end: to);
    await _player.seek(Duration.zero);
    // Not awaited: `play` completes when playback ends, and the caller wants
    // to get on with showing that something is playing.
    unawaited(_player.play());
  }

  @override
  Future<void> stop() => _player.stop();

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
