import 'dart:async';
import 'dart:developer' as developer;

import 'package:audio_service/audio_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:just_audio/just_audio.dart' as ja;

import '../../core/localization/locale_keys.dart';
import '../../data/models/surah.dart';
import '../../domain/entities/playback_unit.dart';
import '../reciter_image_cache.dart';
import 'memorization_player_service.dart';

/// The lock screen, the notification shade, a headset button, CarPlay's
/// now-playing card: everywhere the system lets someone pause a session
/// without opening the app.
///
/// A memorization session is long and mostly hands-off, usually with the
/// screen dark, so this is how it is actually controlled. On Android it is
/// also what keeps the session alive: the media-playback foreground service
/// behind it is the difference between "playing in the background" and "the
/// system may stop this whenever it likes".
///
/// The handler owns no audio. It mirrors [MemorizationPlayerService] outward
/// and passes button presses back in, so the repetition engine and the UI are
/// exactly what they were (CLAUDE.md A.3).
class SessionMediaControls extends BaseAudioHandler {
  SessionMediaControls({
    required MemorizationPlayerService playerService,
    ReciterImageCache? imageCache,
  }) : _player = playerService,
       _images = imageCache {
    _sessionSub = _player.sessionStream.listen(_onSession);
  }

  final MemorizationPlayerService _player;
  final ReciterImageCache? _images;

  StreamSubscription<LoadedSession?>? _sessionSub;
  StreamSubscription<ja.PlayerState>? _stateSub;
  StreamSubscription<PlaybackUnit>? _unitSub;
  LoadedSession? _session;

  /// Registers the handler with the system. Once per process, from
  /// `AppBootstrap` — never from dependency registration, which has to stay
  /// free of platform calls so that tests can run it.
  ///
  /// A failure here costs the lock-screen controls and nothing else, so it is
  /// logged and swallowed: the app plays the same with or without them.
  static Future<SessionMediaControls?> start({
    required MemorizationPlayerService playerService,
    ReciterImageCache? imageCache,
  }) async {
    try {
      return await AudioService.init<SessionMediaControls>(
        builder: () => SessionMediaControls(
          playerService: playerService,
          imageCache: imageCache,
        ),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.mirqat.app.session',
          androidNotificationChannelName: 'Session',
          // Pausing lets the notification be swiped away and the service
          // stand down, which is what Android asks of a well-behaved player.
          androidStopForegroundOnPause: true,
        ),
      );
    } on Object catch (error, stack) {
      developer.log(
        'lock-screen controls unavailable',
        name: 'mirqat.media',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  Future<void> _onSession(LoadedSession? session) async {
    await _stateSub?.cancel();
    await _unitSub?.cancel();
    _session = session;

    if (session == null) {
      mediaItem.add(null);
      playbackState.add(
        PlaybackState(processingState: AudioProcessingState.idle),
      );
      return;
    }

    mediaItem.add(describe(session, unit: null));
    // Subscribed now, not in the constructor: the unit stream only exists
    // once a queue has been loaded.
    _unitSub = _player.currentUnitStream.listen(
      (PlaybackUnit unit) => mediaItem.add(
        describe(session, unit: unit, artUri: mediaItem.value?.artUri),
      ),
    );
    _stateSub = _player.playerStateStream.listen(
      (ja.PlayerState state) => playbackState.add(stateFor(state)),
      // The player screen reports failures; here a broken stream just means
      // there is nothing left to control.
      onError: (Object _) => playbackState.add(
        PlaybackState(processingState: AudioProcessingState.error),
      ),
    );

    // The portrait is a nicety fetched off to the side: the controls must not
    // wait on the network to appear.
    unawaited(_attachPortrait(session));
  }

  Future<void> _attachPortrait(LoadedSession session) async {
    try {
      final Uri? art = (await _images?.imageFor(session.reciter))?.uri;
      final MediaItem? current = mediaItem.value;
      if (art != null && current != null && identical(_session, session)) {
        mediaItem.add(current.copyWith(artUri: art));
      }
    } on Object {
      // No portrait, then.
    }
  }

  /// What the lock screen shows: the surah, who is reciting, and which ayah.
  ///
  /// Names only — never ayah text. A lock screen truncates and ellipsizes
  /// whatever it is given, and Quranic text is not to be cut short
  /// (CLAUDE.md A.2 rule 7).
  static MediaItem describe(
    LoadedSession session, {
    required PlaybackUnit? unit,
    Uri? artUri,
    String? locale,
  }) {
    final bool arabic = (locale ?? Intl.defaultLocale ?? 'ar').startsWith('ar');
    // The surah being recited, not the one the session began in: a session
    // that has run on into the next surah should say so.
    final Surah surah = unit == null
        ? session.surah
        : session.surahOf(unit.surahNumber);
    return MediaItem(
      id: 'surah-${surah.number}',
      title: arabic ? surah.nameAr : surah.nameEn,
      artist: arabic ? session.reciter.nameAr : session.reciter.nameEn,
      album: unit == null
          ? null
          : LocaleKeys.commonAyahNumber.tr(
              args: <String>['${unit.ayahNumber}'],
            ),
      artUri: artUri,
    );
  }

  /// The player's state, in the system's terms. Previous and next move by
  /// *step* — one ayah's repeats, or one joined block — because that is the
  /// unit a listener thinks in; skipping a single repeat is not a thing
  /// anyone wants from a headset button.
  static PlaybackState stateFor(ja.PlayerState state) {
    final bool finished = state.processingState == ja.ProcessingState.completed;
    final bool playing = state.playing && !finished;
    return PlaybackState(
      controls: <MediaControl>[
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      androidCompactActionIndices: const <int>[0, 1, 2],
      processingState: switch (state.processingState) {
        ja.ProcessingState.idle => AudioProcessingState.idle,
        ja.ProcessingState.loading => AudioProcessingState.loading,
        ja.ProcessingState.buffering => AudioProcessingState.buffering,
        ja.ProcessingState.ready => AudioProcessingState.ready,
        ja.ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.pause();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => _player.skipToNextStep();

  @override
  Future<void> skipToPrevious() => _player.skipToPreviousStep();

  Future<void> dispose() async {
    await _sessionSub?.cancel();
    await _stateSub?.cancel();
    await _unitSub?.cancel();
  }
}
