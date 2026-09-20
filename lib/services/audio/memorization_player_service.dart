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
    required this.surahs,
    required this.reciter,
    required this.plan,
  });

  /// Every surah the session recites from, in order. One, usually.
  final List<Surah> surahs;

  /// The surah the session starts in.
  Surah get surah => surahs.first;

  /// The surah [number] names, for a unit that says which one it is in.
  Surah surahOf(int number) =>
      surahs.firstWhere((Surah s) => s.number == number, orElse: () => surah);

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

  /// Where this session's audio comes from — bundled, downloaded or streamed
  /// — surah by surah. Settled by [load], because resolution has to be
  /// synchronous once the queue is being built.
  Map<int, SurahAudio> _sources = const <int, SurahAudio>{};

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
  ///
  /// [surahs] is every surah the plan recites from, in order. [startAtUnit]
  /// is where to pick the plan up — 0 for a session from the top, and the
  /// index of an ayah play for one carried over from a session whose settings
  /// changed under it.
  Future<void> load({
    required SessionPlan plan,
    required Reciter reciter,
    required List<Surah> surahs,
    int startAtUnit = 0,
  }) async {
    final List<int> needed = plan.surahNumbers;
    for (final int number in needed) {
      if (!surahs.any((Surah s) => s.number == number)) {
        throw SessionConfigException(
          'The session recites from surah $number, but it was not handed to '
          'the player.',
        );
      }
      if (!reciter.hasSurah(number)) {
        throw SessionConfigException(
          'Reciter "${reciter.id}" has no audio for surah $number.',
        );
      }
    }
    final List<Surah> inPlan = <Surah>[
      for (final int number in needed)
        surahs.firstWhere((Surah s) => s.number == number),
    ];

    _sources = <int, SurahAudio>{
      for (final Surah surah in inPlan)
        surah.number: await _resolver.forSurah(reciter: reciter, surah: surah),
    };

    final SessionPreambles preambles = SessionPreambles.forSession(
      surah: inPlan.first,
      reciter: reciter,
      istiadhahEnabled: plan.config.playIstiadhah,
      startAyah: plan.config.startAyah,
    );

    final PlaybackQueue queue = queueBuilder.build(
      plan: plan,
      includeIstiadhah: preambles.istiadhah,
      includeBismillah: preambles.bismillah,
      basmalaBeforeSurahs: SessionPreambles.forLaterSurahs(
        surahs: inPlan.skip(1),
        reciter: reciter,
      ),
    );
    _queue = queue;
    _lastUnit = null;

    // The spec calls for a ConcatenatingAudioSource; that type is deprecated
    // in just_audio 0.10, and setAudioSources is its replacement. Same flat
    // queue, same gapless behaviour.
    await _player.setAudioSources(
      <AudioSource>[
        for (final QueueEntry entry in queue.entries)
          _sourceFor(entry, reciter: reciter, firstSurah: inPlan.first.number),
      ],
      initialIndex: queue.indexOfUnit(startAtUnit),
      initialPosition: Duration.zero,
    );
    await _player.setSpeed(plan.config.playbackSpeed);
    _sessions.add(LoadedSession(surahs: inPlan, reciter: reciter, plan: plan));
  }

  AudioSource _sourceFor(
    QueueEntry entry, {
    required Reciter reciter,
    required int firstSurah,
  }) => switch (entry) {
    AyahQueueEntry(unit: final PlaybackUnit unit) => _sourcesOf(
      unit.surahNumber,
    ).sourceFor(unit.ayahNumber),
    SpacerQueueEntry() => _sourcesOf(firstSurah).spacer(),
    PreambleQueueEntry(kind: PreambleKind.istiadhah) => _requirePreamble(
      _sourcesOf(firstSurah).istiadhah(),
      reciter: reciter,
      flag: 'hasIstiadhah',
    ),
    PreambleQueueEntry(kind: PreambleKind.bismillah, surah: final int? surah) =>
      _requirePreamble(
        _sourcesOf(surah ?? firstSurah).basmala(),
        reciter: reciter,
        flag: 'hasBismillah',
      ),
  };

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

  SurahAudio _sourcesOf(int surah) {
    final SurahAudio? sources = _sources[surah];
    if (sources == null) {
      throw SessionConfigException(
        _sources.isEmpty
            ? 'The player was used before load() was called.'
            : 'No audio was resolved for surah $surah.',
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
    final PlaybackQueue? queue = _queue;
    if (queue == null) return false;
    return queue.entries.whereType<AyahQueueEntry>().any(
      (AyahQueueEntry entry) =>
          !(_sources[entry.unit.surahNumber]?.isLocal(entry.unit.ayahNumber) ??
              true),
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
