import 'dart:math';

import 'package:dartz/dartz.dart' hide State;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/mutashabihat.dart';
import '../../../data/models/surah.dart';
import '../../../data/models/word.dart';
import '../../../data/repositories/mutashabihat_repository.dart';
import '../../../data/repositories/progress_repository.dart';
import '../../../data/repositories/quran_pages_repository.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../domain/entities/ayah_ref.dart';
import 'similar_cubit.dart';

/// Where a round stands.
enum DrillStage {
  /// The ayah is shown up to the end of the shared phrase; which is it?
  identify,

  /// Named; the reader continues it from memory, past where the twins part.
  recite,

  /// The rest is shown; the reader says how it went.
  revealed,

  /// Every ayah of the phrase has had its round.
  done,
}

/// One of the ayahs a round asks the reader to choose between.
class DrillChoice extends Equatable {
  const DrillChoice({required this.ref, required this.surah});

  final AyahRef ref;
  final Surah surah;

  @override
  List<Object?> get props => <Object?>[ref, surah];
}

/// One round: an ayah that holds the phrase, shown as far as the phrase
/// reaches, with what comes after it held back.
class DrillRound extends Equatable {
  const DrillRound({
    required this.ayah,
    required this.phrase,
    required this.choices,
    this.before = const <Word>[],
    this.after = const <Word>[],
  });

  /// The whole ayah, its words from `quran.db`.
  final ComparedAyah ayah;

  /// Where the phrase falls in it — the first time, if more than once.
  final PhraseOccurrence phrase;

  /// The ayah before, shown faintly, when the phrase opens this one: what
  /// precedes the phrase is what tells the twins apart.
  final List<Word> before;

  /// The ayah after, held back with the rest, when the phrase closes this
  /// one: then the continuation is the next ayah.
  final List<Word> after;

  /// Ayahs of the phrase to choose between, this one among them, in no
  /// telling order.
  final List<DrillChoice> choices;

  /// Held back until the reveal: whatever of the ayah follows the phrase,
  /// and its number, which would give the answer away.
  bool isHeldBack(Word w) => w.isMarker || w.position > phrase.toWord;

  @override
  List<Object?> get props => <Object?>[ayah, phrase, choices, before, after];
}

class DrillState extends Equatable {
  const DrillState({
    this.status = LoadStatus.initial,
    this.rounds = const <DrillRound>[],
    this.index = 0,
    this.stage = DrillStage.identify,
    this.picked,
    this.slips = 0,
    this.errorMessage,
  });

  final LoadStatus status;
  final List<DrillRound> rounds;
  final int index;
  final DrillStage stage;

  /// What the reader chose in this round.
  final AyahRef? picked;

  /// Rounds the reader said they slipped in — each noted as a stumble.
  final int slips;
  final String? errorMessage;

  DrillRound? get round =>
      stage == DrillStage.done || index >= rounds.length ? null : rounds[index];

  bool get pickedRight => picked != null && picked == round?.ayah.ref;

  DrillState copyWith({
    LoadStatus? status,
    List<DrillRound>? rounds,
    int? index,
    DrillStage? stage,
    AyahRef? picked,
    bool clearPicked = false,
    int? slips,
  }) => DrillState(
    status: status ?? this.status,
    rounds: rounds ?? this.rounds,
    index: index ?? this.index,
    stage: stage ?? this.stage,
    picked: clearPicked ? null : picked ?? this.picked,
    slips: slips ?? this.slips,
    errorMessage: errorMessage,
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    rounds,
    index,
    stage,
    picked,
    slips,
    errorMessage,
  ];
}

/// The mutashabihat drill (NEW_IDEAS §4): for one shared phrase, each ayah
/// it occurs in, in turn — shown as far as the phrase reaches, the rest
/// held back. The reader says which ayah it is, continues it from memory
/// past the point where the twins part, and sees the rest. A slip is noted
/// where every slip is, as a stumble mark, so the next session over that
/// ayah drills it more.
///
/// Text only: audio plays over the reading view and nowhere else
/// (CLAUDE.md A.1), so hearing an ayah opens it there.
class DrillCubit extends Cubit<DrillState> {
  DrillCubit({
    required MutashabihatRepository mutashabihatRepository,
    required QuranRepository quranRepository,
    required QuranPagesRepository pagesRepository,
    required ProgressRepository progressRepository,
    Random? random,
  }) : _index = mutashabihatRepository,
       _quran = quranRepository,
       _pages = pagesRepository,
       _progress = progressRepository,
       _random = random ?? Random(),
       super(const DrillState());

  final MutashabihatRepository _index;
  final QuranRepository _quran;
  final QuranPagesRepository _pages;
  final ProgressRepository _progress;
  final Random _random;

  /// More choices than this and the question is a list to read, not a
  /// choice to make; the rest of the phrase's ayahs still get their rounds.
  static const int maxChoices = 4;

  List<ComparedAyah> _ayahs = const <ComparedAyah>[];

  Future<void> load(int phraseId) async {
    emit(const DrillState(status: LoadStatus.loading));
    final MutashabihatIndex index = await _index.index();
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final Map<int, Surah> byNumber = <int, Surah>{
      for (final Surah s in surahs.getOrElse(() => const <Surah>[]))
        s.number: s,
    };

    final Map<AyahRef, List<PhraseOccurrence>> byAyah =
        <AyahRef, List<PhraseOccurrence>>{};
    for (final PhraseOccurrence o in index.occurrencesOf(phraseId)) {
      (byAyah[o.ref] ??= <PhraseOccurrence>[]).add(o);
    }
    final List<ComparedAyah> ayahs = <ComparedAyah>[];
    for (final MapEntry<AyahRef, List<PhraseOccurrence>> e in byAyah.entries) {
      final ComparedAyah? a = await ComparedAyah.load(
        _pages,
        byNumber,
        e.key,
        e.value,
      );
      if (a != null) ayahs.add(a);
    }
    if (isClosed) return;
    // One ayah is nothing to tell apart.
    if (ayahs.length < 2) {
      emit(
        DrillState(
          status: LoadStatus.failure,
          errorMessage: surahs.fold((Failure f) => f.message, (_) => null),
        ),
      );
      return;
    }
    _ayahs = ayahs;
    await _begin();
  }

  /// The same phrase again, in a new order.
  Future<void> restart() => _begin();

  Future<void> _begin() async {
    final List<ComparedAyah> order = List<ComparedAyah>.of(_ayahs)
      ..shuffle(_random);
    final List<DrillRound> rounds = <DrillRound>[];
    for (final ComparedAyah a in order) {
      rounds.add(await _roundFor(a));
    }
    if (isClosed) return;
    emit(DrillState(status: LoadStatus.ready, rounds: rounds));
  }

  Future<DrillRound> _roundFor(ComparedAyah a) async {
    final PhraseOccurrence phrase = a.shared.reduce(
      (PhraseOccurrence x, PhraseOccurrence y) =>
          x.fromWord <= y.fromWord ? x : y,
    );
    final int recited = a.words.where((Word w) => !w.isMarker).length;
    final bool opens = phrase.fromWord == 1;
    final bool closes = phrase.toWord >= recited;

    Future<List<Word>> words(int ayah) async =>
        ayah < 1 || ayah > a.surah.ayahCount
        ? const <Word>[]
        : (await _pages.wordsForAyah(
            a.ref.surah,
            ayah,
          )).getOrElse(() => const <Word>[]);

    final List<ComparedAyah> others = <ComparedAyah>[
      for (final ComparedAyah o in _ayahs)
        if (o.ref != a.ref) o,
    ]..shuffle(_random);
    final List<DrillChoice> choices = <DrillChoice>[
      DrillChoice(ref: a.ref, surah: a.surah),
      for (final ComparedAyah o in others.take(maxChoices - 1))
        DrillChoice(ref: o.ref, surah: o.surah),
    ]..shuffle(_random);

    return DrillRound(
      ayah: a,
      phrase: phrase,
      before: opens ? await words(a.ref.ayah - 1) : const <Word>[],
      after: closes ? await words(a.ref.ayah + 1) : const <Word>[],
      choices: choices,
    );
  }

  /// The reader's answer to "which ayah is this?". Right or not, it is
  /// named, and the round moves on to reciting it.
  void pick(AyahRef ref) {
    if (state.stage != DrillStage.identify || state.round == null) return;
    emit(state.copyWith(stage: DrillStage.recite, picked: ref));
  }

  /// Shows what was held back: the rest of the ayah, and the next one if
  /// the phrase closed it.
  void reveal() {
    if (state.stage != DrillStage.recite) return;
    emit(state.copyWith(stage: DrillStage.revealed));
  }

  /// How the continuation went, in the reader's own word. A slip is noted
  /// as a stumble at the ayah; storage that cannot be written costs the
  /// note, never the drill.
  Future<void> grade({required bool slipped}) async {
    final DrillRound? round = state.round;
    if (state.stage != DrillStage.revealed || round == null) return;
    if (slipped) {
      await _progress.markStumble(round.ayah.ref.surah, round.ayah.ref.ayah);
    }
    if (isClosed) return;
    final int next = state.index + 1;
    emit(
      state.copyWith(
        index: next,
        stage: next >= state.rounds.length
            ? DrillStage.done
            : DrillStage.identify,
        clearPicked: true,
        slips: state.slips + (slipped ? 1 : 0),
      ),
    );
  }
}
