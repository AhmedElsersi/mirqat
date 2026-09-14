import 'package:just_audio/just_audio.dart';

import '../../core/error/exceptions.dart';
import '../../data/models/reciter.dart';
import '../../data/models/surah.dart';
import '../../data/repositories/quran_repository.dart';
import '../../domain/entities/playback_unit.dart';
import '../../domain/entities/session_plan.dart';
import 'ayah_audio_resolver.dart';
import 'playback_queue.dart';
import 'session_preambles.dart';

/// Every player call goes through this class.
///
/// Keeping `just_audio` behind it means `just_audio_background` can be added
/// later for lock-screen controls without touching the UI or the engine
/// (CLAUDE.md / Part B, Phase 3). Wake-lock handling deliberately lives in the
/// player screen, not here.
class MemorizationPlayerService {
  MemorizationPlayerService({
    required QuranRepository quranRepository,
    AudioPlayer? player,
    this.queueBuilder = const PlaybackQueueBuilder(),
  }) : _quran = quranRepository,
       _player = player ?? AudioPlayer();

  final QuranRepository _quran;
  final AudioPlayer _player;
  final PlaybackQueueBuilder queueBuilder;

  PlaybackQueue? _queue;
  AyahAudioResolver? _resolver;

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

    final AyahAudioResolver resolver = await _createResolver(reciter, surah);
    _resolver = resolver;

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
          _sourceFor(entry, reciter: reciter, surah: surah),
      ],
      initialIndex: 0,
      initialPosition: Duration.zero,
    );
    await _player.setSpeed(plan.config.playbackSpeed);
  }

  AudioSource _sourceFor(
    QueueEntry entry, {
    required Reciter reciter,
    required Surah surah,
  }) {
    final AyahAudioResolver resolver = _requireResolver;
    return switch (entry) {
      AyahQueueEntry(unit: final PlaybackUnit unit) => resolver.resolve(
        reciter: reciter,
        surah: surah.number,
        ayah: unit.ayahNumber,
      ),
      SpacerQueueEntry() => resolver.resolveSpacer(),
      PreambleQueueEntry(kind: PreambleKind.istiadhah) => _requirePreamble(
        resolver.resolveIstiadhah(reciter: reciter),
        reciter: reciter,
        flag: 'hasIstiadhah',
      ),
      PreambleQueueEntry(kind: PreambleKind.bismillah) => _requirePreamble(
        resolver.resolveBismillah(reciter: reciter),
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

  Future<AyahAudioResolver> _createResolver(
    Reciter reciter,
    Surah surah,
  ) async {
    switch (reciter.audioMode) {
      case AudioMode.perAyahFiles:
        return PerAyahFilesResolver();
      case AudioMode.singleFileWithTimings:
        final result = await _quran.getTimings(
          reciterId: reciter.id,
          surahNumber: surah.number,
        );
        return result.fold(
          (failure) => throw SessionConfigException(failure.message),
          TimingsAudioResolver.new,
        );
    }
  }

  AyahAudioResolver get _requireResolver {
    final AyahAudioResolver? resolver = _resolver;
    if (resolver == null) {
      throw const SessionConfigException(
        'The player was used before load() was called.',
      );
    }
    return resolver;
  }

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  /// Stops and rewinds to the top of the queue.
  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero, index: 0);
    _lastUnit = null;
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

  Future<void> dispose() => _player.dispose();

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
