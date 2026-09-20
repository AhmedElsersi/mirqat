import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/domain/entities/plan_step.dart';
import 'package:mirqat/domain/entities/playback_unit.dart';
import 'package:mirqat/domain/entities/session_config.dart';
import 'package:mirqat/domain/entities/session_plan.dart';
import 'package:mirqat/services/audio/memorization_player_service.dart';
import 'package:mirqat/services/audio/session_media_controls.dart';

const Surah ikhlas = Surah(
  number: 112,
  nameAr: 'الإخلاص',
  nameEn: 'Al-Ikhlas',
  ayahCount: 4,
  revelationPlace: RevelationPlace.makkah,
  bismillahMode: BismillahMode.separatePreamble,
);

const Reciter reciter = Reciter(
  id: 'ahmed_khalil_shaheen',
  nameAr: 'أحمد خليل شاهين',
  nameEn: 'Ahmed Khalil Shaheen',
  audioMode: AudioMode.perAyahFiles,
  basePath: 'assets/audio/ahmed_khalil_shaheen',
  bundled: true,
  availableSurahs: <int>[],
  hasIstiadhah: true,
  hasBismillah: true,
);

final LoadedSession session = LoadedSession(
  surahs: <Surah>[ikhlas],
  reciter: reciter,
  plan: SessionPlan(
    config: const SessionConfig(surahNumber: 112, startAyah: 1, endAyah: 4),
    steps: const <PlanStep>[],
    units: const <PlaybackUnit>[],
  ),
);

const PlaybackUnit ayah3 = PlaybackUnit(
  stepIndex: 2,
  stepType: StepType.learn,
  surahNumber: 112,
  ayahNumber: 3,
  repeatIndex: 0,
  totalRepeats: 3,
  blockFrom: 3,
  blockTo: 3,
  isLastUnitOfRepeat: true,
  isLastUnitOfStep: false,
);

/// The lock screen is where a session is actually controlled — the phone is
/// usually dark and in a pocket. These pin what it shows and what its buttons
/// mean, without needing a device.
void main() {
  group('what the lock screen shows', () {
    test('the surah and the reciter, in the app\'s language', () {
      final MediaItem ar = SessionMediaControls.describe(
        session,
        unit: null,
        locale: 'ar',
      );
      expect(ar.title, 'الإخلاص');
      expect(ar.artist, 'أحمد خليل شاهين');

      final MediaItem en = SessionMediaControls.describe(
        session,
        unit: null,
        locale: 'en',
      );
      expect(en.title, 'Al-Ikhlas');
      expect(en.artist, 'Ahmed Khalil Shaheen');
    });

    test('Arabic when nothing says otherwise — the app is Arabic-first', () {
      expect(
        SessionMediaControls.describe(session, unit: null).title,
        'الإخلاص',
      );
    });

    test('which ayah is being recited, once one is', () {
      expect(SessionMediaControls.describe(session, unit: null).album, isNull);
      expect(
        SessionMediaControls.describe(session, unit: ayah3, locale: 'ar').album,
        isNotNull,
      );
    });

    test('names only, never ayah text', () {
      // A lock screen truncates and ellipsizes whatever it is handed, and
      // Quranic text is never to be cut short (CLAUDE.md A.2 rule 7). The
      // surah's and the reciter's names are all that may appear.
      final MediaItem item = SessionMediaControls.describe(
        session,
        unit: ayah3,
        locale: 'ar',
      );
      for (final String? field in <String?>[
        item.title,
        item.artist,
        item.displayTitle,
        item.displaySubtitle,
        item.displayDescription,
      ]) {
        if (field == null) continue;
        expect(
          <String>['الإخلاص', 'أحمد خليل شاهين'].contains(field),
          isTrue,
          reason: 'unexpected text on the lock screen: $field',
        );
      }
    });

    test('the same surah keeps the same id, so the system does not treat '
        'every ayah as a new track', () {
      expect(
        SessionMediaControls.describe(session, unit: ayah3).id,
        SessionMediaControls.describe(session, unit: null).id,
      );
    });
  });

  group('what its buttons are', () {
    PlaybackState at(bool playing, ja.ProcessingState state) =>
        SessionMediaControls.stateFor(ja.PlayerState(playing, state));

    test('pause while reciting, play while paused', () {
      final PlaybackState reciting = at(true, ja.ProcessingState.ready);
      expect(reciting.playing, isTrue);
      expect(reciting.controls, contains(MediaControl.pause));
      expect(reciting.controls, isNot(contains(MediaControl.play)));

      final PlaybackState paused = at(false, ja.ProcessingState.ready);
      expect(paused.playing, isFalse);
      expect(paused.controls, contains(MediaControl.play));
      expect(paused.controls, isNot(contains(MediaControl.pause)));
    });

    test('previous and next are always offered, and fit the compact view', () {
      final PlaybackState state = at(true, ja.ProcessingState.ready);
      expect(state.controls.first, MediaControl.skipToPrevious);
      expect(state.controls.last, MediaControl.skipToNext);
      expect(state.androidCompactActionIndices, <int>[0, 1, 2]);
    });

    test('a finished session is not "playing", whatever the player says', () {
      // just_audio leaves `playing` true at the end of a queue. Reporting
      // that would leave a pause button on the lock screen over silence.
      final PlaybackState done = at(true, ja.ProcessingState.completed);
      expect(done.playing, isFalse);
      expect(done.processingState, AudioProcessingState.completed);
      expect(done.controls, contains(MediaControl.play));
    });

    test('every player state has a counterpart', () {
      for (final ja.ProcessingState state in ja.ProcessingState.values) {
        expect(() => at(false, state), returnsNormally, reason: state.name);
      }
      expect(
        at(true, ja.ProcessingState.buffering).processingState,
        AudioProcessingState.buffering,
      );
    });

    test('no seeking: a position inside one clip means nothing across a '
        'queue of repeats', () {
      final PlaybackState state = at(true, ja.ProcessingState.ready);
      expect(state.systemActions, isEmpty);
    });
  });
}
