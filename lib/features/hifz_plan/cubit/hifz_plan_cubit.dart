import 'dart:async';

import 'package:dartz/dartz.dart' hide State;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failures.dart';
import '../../../core/state/load_status.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/surah.dart';
import '../../../data/repositories/quran_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/engine/hifz_planner.dart';
import '../../../domain/entities/ayah_ref.dart';
import '../../../domain/entities/hifz_plan.dart';

class HifzPlanState extends Equatable {
  const HifzPlanState({
    this.status = LoadStatus.initial,
    this.surahs = const <Surah>[],
    this.plan,
    this.from = const AyahRef(1, 1),
    this.to = const AyahRef(1, 1),
    this.days = 30,
    this.saving = false,
    this.errorMessage,
  });

  final LoadStatus status;
  final List<Surah> surahs;

  /// The plan in force, or null while the reader is making one.
  final HifzPlan? plan;

  /// The plan being made.
  final AyahRef from;
  final AyahRef to;
  final int days;
  final bool saving;
  final String? errorMessage;

  Surah? surah(int number) =>
      surahs.where((Surah s) => s.number == number).firstOrNull;

  /// How many ayahs the draft covers, counted from the catalog.
  int get draftAyahs => ayahsIn(from, to);

  /// How many ayahs lie from [a] to [b], counted from the catalog.
  int ayahsIn(AyahRef a, AyahRef b) {
    int n = 0;
    for (final Surah s in surahs) {
      if (s.number < a.surah || s.number > b.surah) continue;
      final int first = s.number == a.surah ? a.ayah : 1;
      final int last = s.number == b.surah ? b.ayah : s.ayahCount;
      if (last >= first) n += last - first + 1;
    }
    return n;
  }

  HifzPlanState copyWith({
    LoadStatus? status,
    List<Surah>? surahs,
    HifzPlan? plan,
    bool clearPlan = false,
    AyahRef? from,
    AyahRef? to,
    int? days,
    bool? saving,
    String? errorMessage,
    bool clearError = false,
  }) => HifzPlanState(
    status: status ?? this.status,
    surahs: surahs ?? this.surahs,
    plan: clearPlan ? null : (plan ?? this.plan),
    from: from ?? this.from,
    to: to ?? this.to,
    days: days ?? this.days,
    saving: saving ?? this.saving,
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
  );

  @override
  List<Object?> get props => <Object?>[
    status,
    surahs,
    plan,
    from,
    to,
    days,
    saving,
    errorMessage,
  ];
}

/// Making a hifz plan, and following the one in force.
///
/// The plan lives in the settings map, which has several writers; so every
/// write here reads the stored map afresh and changes only the plan
/// (CLAUDE.md A.5).
class HifzPlanCubit extends Cubit<HifzPlanState> {
  HifzPlanCubit({
    required QuranRepository quranRepository,
    required SettingsRepository settingsRepository,
    HifzPlanner hifzPlanner = const HifzPlanner(),
    this.clock = DateTime.now,
  }) : _quran = quranRepository,
       _settings = settingsRepository,
       _planner = hifzPlanner,
       super(const HifzPlanState());

  final QuranRepository _quran;
  final SettingsRepository _settings;
  final HifzPlanner _planner;
  final DateTime Function() clock;

  StreamSubscription<AppSettings>? _changes;

  Future<void> load() async {
    // A portion graded in a session moves the plan on; it is taken up here.
    _changes ??= _settings.changes.listen((AppSettings s) {
      if (!isClosed && s.hifzPlan != state.plan) {
        emit(
          s.hifzPlan == null
              ? state.copyWith(clearPlan: true)
              : state.copyWith(plan: s.hifzPlan),
        );
      }
    });
    final Either<Failure, List<Surah>> surahs = await _quran.getSurahs();
    final AppSettings settings = (await _settings.read()).getOrElse(
      () => const AppSettings(),
    );
    if (isClosed) return;
    surahs.fold(
      (Failure f) => emit(
        state.copyWith(status: LoadStatus.failure, errorMessage: f.message),
      ),
      (List<Surah> list) {
        final Surah? first = list.firstOrNull;
        emit(
          HifzPlanState(
            status: LoadStatus.ready,
            surahs: list,
            plan: settings.hifzPlan,
            from: first == null ? state.from : AyahRef(first.number, 1),
            to: first == null
                ? state.to
                : AyahRef(first.number, first.ayahCount),
            days: state.days,
          ),
        );
      },
    );
  }

  AyahRef _clamped(AyahRef ref) {
    final Surah? s = state.surah(ref.surah);
    if (s == null) return ref;
    return AyahRef(s.number, ref.ayah.clamp(1, s.ayahCount));
  }

  /// Moves the start, taking the end along rather than letting them cross.
  void setFrom(AyahRef ref) {
    final AyahRef from = _clamped(ref);
    emit(state.copyWith(from: from, to: state.to < from ? from : state.to));
  }

  void setTo(AyahRef ref) {
    final AyahRef to = _clamped(ref);
    emit(state.copyWith(to: to, from: to < state.from ? to : state.from));
  }

  void setDays(int days) =>
      emit(state.copyWith(days: days.clamp(1, HifzPlanner.maxDays)));

  /// Cuts the draft into portions and makes it the plan in force.
  Future<void> create() async {
    if (state.saving) return;
    emit(state.copyWith(saving: true, clearError: true));
    final Either<Failure, List<({AyahRef ref, int weight})>> weights =
        await _quran.ayahWeights(state.from, state.to);
    final List<({AyahRef ref, int weight})> list = weights.getOrElse(
      () => const <({AyahRef ref, int weight})>[],
    );
    if (list.isEmpty) {
      emit(
        state.copyWith(
          saving: false,
          errorMessage: weights.fold((Failure f) => f.message, (_) => ''),
        ),
      );
      return;
    }
    final HifzPlan plan = _planner.plan(
      weights: list,
      days: state.days,
      now: clock(),
    );
    await _write((AppSettings s) => s.copyWith(hifzPlan: plan));
    if (!isClosed) emit(state.copyWith(plan: plan, saving: false));
  }

  /// Gives the plan up. Nothing memorized is touched — only the plan goes.
  Future<void> delete() async {
    await _write((AppSettings s) => s.copyWith(clearHifzPlan: true));
    if (!isClosed) emit(state.copyWith(clearPlan: true));
  }

  Future<void> _write(AppSettings Function(AppSettings) change) async {
    final AppSettings fresh = (await _settings.read()).getOrElse(
      () => const AppSettings(),
    );
    await _settings.save(change(fresh));
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
