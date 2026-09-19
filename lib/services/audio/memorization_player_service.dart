import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../core/error/exceptions.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../domain/entities/playback_unit.dart';
import '../../domain/entities/session_plan.dart';
import 'audio_resolver.dart';
import 'playback_queue.dart';
import 'session_preambles.dart';

/// What is loaded into the player: enough to name it on a lock screen.
class LoadedSession {
  const LoadedSession({
    required this.surah,
    required this.reciter,
    required this.plan,
  });

  final Surah surah;
  final Reciter reciter;
  final SessionPlan plan;
}

/// Every player call goes through this class.
///
/// Keeping `just_audio` behind it is what let lock-screen controls be added
/// without touching the UI or the engine: `SessionMediaControls` listens to
/// [sessionStream] and the two streams below, and calls back into [play],
/// [pause] and the step skips — it never sees the player. Wake-lock handling
/// deliberately lives in the player screen, not here.
class MemorizationPlayerService {
  MemorizationPlayerService({
    required AudioResolver audioResolver,
    AudioPlayer? player,
    this.queueBuilder = const PlaybackQueueBuilder(),
  }) : _resolver = audioResolver,
       _player = player ?? AudioPlayer();

  final AudioResolver _resolver;
  final AudioPlayer _player;
  final PlaybackQueueBuilder queueBuilder;

  PlaybackQueue? _queue;

  final StreamController<LoadedSession?> _sessions =
      StreamController<LoadedSession?>.broadcast();

  /// The session that is loaded, and null when it ends. What the lock screen
  /// shows hangs off this: there is something to control exactly while there
  /// is a session.
  Stream<LoadedSession?> get sessionStream => _sessions.stream;

  /// Where this session's audio comes from — bundled, downloaded or streamed.
  /// Settled by [load], because resolution has to be synchronous once the
  /// queue is being built.
  SurahAudio? _sources;

  PlaybackQueue? get queue => _queue;

  /// The ayah currently being recited. Spacers and preambles leave it
  /// unchanged rather than clearing it.
  PlaybackUnit? get currentUnit {
    final int? index = _player.currentIndex;
    if (index == null) return _lastUnit;
    return _queue?.unitAt(index) ?? _lastUnit;
  }

  PlaybackUnit? _lastUnit;

  /// Emits each time the recited ayah changes.
  Stream<PlaybackUnit> get currentUnitStream {
    final PlaybackQueue? queue = _queue;
    if (queue == null) return const Stream<PlaybackUnit>.empty();
    return queue.unitStreamFrom(_player.currentIndexStream).map((
      PlaybackUnit unit,
    ) {
      _lastUnit = unit;
      return unit;
    });
  }

  Stream<bool> get playingStream => _player.playingStream;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  bool get isPlaying => _player.playing;

  /// Builds the queue for [plan] and hands it to the player. Nothing starts
  /// until [play] is called.
  Future<void> load({
    required SessionPlan plan,
    required Reciter reciter,
    required Surah surah,
  }) async {
    if (!reciter.hasSurah(surah.number)) {
      throw SessionConfigException(
        'Reciter "${reciter.id}" has no audio for surah ${surah.number}.',
      );
    }

    _sources = await _resolver.forSurah(reciter: reciter, surah: surah);

    final SessionPreambles preambles = SessionPreambles.forSession(
      surah: surah,
      reciter: reciter,
      istiadhahEnabled: plan.config.playIstiadhah,
    );

    final PlaybackQueue queue = queueBuilder.build(
      plan: plan,
      includeIstiadhah: preambles.istiadhah,
      includeBismillah: preambles.bismillah,
    );
    _queue = queue;
    _lastUnit = null;

    // The spec calls for a ConcatenatingAudioSource; that type is deprecated
    // in just_audio 0.10, and setAudioSources is its replacement. Same flat
    // queue, same gapless behaviour.
    await _player.setAudioSources(
      <AudioSource>[
        for (final QueueEntry entry in queue.entries)
          _sourceFor(entry, reciter: reciter),
      ],
      initialIndex: 0,
      initialPosition: Duration.zero,
    );
    await _player.setSpeed(plan.config.playbackSpeed);
    _sessions.add(LoadedSession(surah: surah, reciter: reciter, plan: plan));
  }

  AudioSource _sourceFor(QueueEntry entry, {required Reciter reciter}) {
    final SurahAudio sources = _requireSources;
    return switch (entry) {
      AyahQueueEntry(unit: final PlaybackUnit unit) => sources.sourceFor(
        unit.ayahNumber,
      ),
      SpacerQueueEntry() => sources.spacer(),
      PreambleQueueEntry(kind: PreambleKind.istiadhah) => _requirePreamble(
        sources.istiadhah(),
        reciter: reciter,
        flag: 'hasIstiadhah',
      ),
      PreambleQueueEntry(kind: PreambleKind.bismillah) => _requirePreamble(
        sources.basmala(),
        reciter: reciter,
        flag: 'hasBismillah',
      ),
    };
  }

  /// [SessionPreambles] only queues a preamble whose flag is set, and the
  /// resolver returns a source for exactly those, so this is unreachable in a
  /// well-formed catalog. It throws rather than substituting silence: a
  /// swallowed preamble is a packaging bug that the asset-integrity test is
  /// there to catch at build time, and hiding it would let it ship.
  AudioSource _requirePreamble(
    AudioSource? source, {
    required Reciter reciter,
    required String flag,
  }) {
    if (source != null) return source;
    throw SessionConfigException(
      'A preamble was queued for reciter "${reciter.id}" but no clip resolved. '
      'Check that "$flag" in reciters.json matches the files under '
      '${reciter.basePath}.',
    );
  }

  SurahAudio get _requireSources {
    final SurahAudio? sources = _sources;
    if (sources == null) {
      throw const SessionConfigException(
        'The player was used before load() was called.',
      );
    }
    return sources;
  }

  /// Whether any ayah this session queued would have to be fetched.
  ///
  /// Asked only after a failure, to tell "the network was not there" apart
  /// from a packaging fault: a queue of files already on the device does not
  /// fail for want of a CDN, so if one of these did, the missing piece was
  /// the network. False before [load] has resolved anything.
  bool get streamsAnyAyah {
    final SurahAudio? sources = _sources;
    final PlaybackQueue? queue = _queue;
    if (sources == null || queue == null) return false;
    return queue.entries.whereType<AyahQueueEntry>().any(
      (AyahQueueEntry entry) => !sources.isLocal(entry.unit.ayahNumber),
    );
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  /// Stops and rewinds to the top of the queue.
  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero, index: 0);
    _lastUnit = null;
  }

  /// The listener has left the session: stop, and take the controls off the
  /// lock screen. Distinct from [stop], after which the same session can be
  /// played again from the top.
  Future<void> endSession() async {
    await stop();
    _sessions.add(null);
  }

  /// Jumps to the first ayah play of the next step. At the last step this
  /// does nothing.
  Future<void> skipToNextStep() => _seekToStep(_currentStepIndex + 1);

  /// Jumps to the first ayah play of the previous step. At the first step it
  /// restarts that step, which is what a listener expects from a back button.
  Future<void> skipToPreviousStep() => _seekToStep(_currentStepIndex - 1);

  Future<void> restartCurrentStep() => _seekToStep(_currentStepIndex);

  /// Changing speed does not move the play position.
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> dispose() async {
    await _sessions.close();
    await _player.dispose();
  }

  int get _currentStepIndex => currentUnit?.stepIndex ?? 0;

  Future<void> _seekToStep(int stepIndex) async {
    final PlaybackQueue? queue = _queue;
    if (queue == null) return;

    final int clamped = stepIndex.clamp(0, queue.plan.stepCount - 1);
    final int queueIndex = queue.indexOfStep(clamped);
    _lastUnit = queue.unitAt(queueIndex);
    await _player.seek(Duration.zero, index: queueIndex);
  }
}
