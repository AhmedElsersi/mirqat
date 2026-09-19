// A device-side check, not part of the app:  flutter run -t tool/stream_probe.dart
//
// Does what starting a session does for a surah that is not on the device —
// resolves it through AudioResolver and plays ayah 1 — and prints what happened
// as PROBE lines. It exists because the streamed arm goes through just_audio's
// caching proxy on http://127.0.0.1, which is exactly what a platform's
// cleartext rules block: Android needed a network security config for it, and
// iOS has App Transport Security. A unit test cannot see either.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mirqat/core/di/injection.dart';
import 'package:mirqat/data/models/reciter.dart';
import 'package:mirqat/data/models/surah.dart';
import 'package:mirqat/data/repositories/quran_repository.dart';
import 'package:mirqat/services/audio/audio_resolver.dart';
import 'package:mirqat/services/audio/reciter_catalog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  try {
    await Hive.initFlutter();
    await configureDependencies();

    final List<Reciter> reciters = (await sl<ReciterCatalog>().reciters())
        .getOrElse(() => const <Reciter>[]);
    final Surah surah = (await sl<QuranRepository>().getSurah(
      114,
    )).getOrElse(() => throw StateError('no surah 114'));
    final Reciter reciter = reciters.firstWhere(
      (Reciter r) => r.hasSurah(surah.number),
    );

    final SurahAudio audio = await sl<AudioResolver>().forSurah(
      reciter: reciter,
      surah: surah,
    );
    // ignore: avoid_print
    print('PROBE reciter=${reciter.id} local=${audio.isLocal(1)}');

    final AudioPlayer player = AudioPlayer();
    await player.setAudioSource(audio.sourceFor(1));
    // ignore: avoid_print
    print('PROBE loaded duration=${player.duration}');
    unawaited(player.play());
    await Future<void>.delayed(const Duration(seconds: 3));
    // ignore: avoid_print
    print(
      'PROBE playing=${player.playing} position=${player.position} '
      'state=${player.processingState}',
    );
    // ignore: avoid_print
    print(
      player.position > Duration.zero
          ? 'PROBE RESULT OK'
          : 'PROBE RESULT STALLED',
    );
  } on Object catch (e) {
    // ignore: avoid_print
    print('PROBE RESULT FAILED $e');
  }
}
