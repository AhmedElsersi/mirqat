# GLOBAL PROJECT CONTRACT

> This file is permanent project law. It is Part A of the Milestone 1 build prompt,
> reproduced verbatim. Any change to it is a product decision, not a refactor.

## A.1 Product definition

An offline Quran memorization (hifz) app built around **talqeen-style spaced repetition of audio**: the app plays one ayah N times, then the next ayah N times, then joins them and plays the pair N times, and continues that pattern until the selected range is memorized.

Milestone 1 ships **Surat Al-Fatiha only**, with **one reciter: Ahmed Khalil Shaheen**, fully offline.
Every later surah and every later reciter must be addable **without writing a single line of new Dart code**.

## A.2 Non-negotiable rules

1. **Quranic text is never generated.** The agent must never type, complete, autocorrect, "fix", normalize, or re-diacritize Quranic text from memory. Ayah text is loaded verbatim from the JSON asset files supplied by the developer. If a text asset is missing or looks malformed, **STOP and report** — do not fill the gap.
2. **No surah-specific or reciter-specific code.** No `if (surah == 1)`, no hardcoded ayah counts, no hardcoded reciter IDs, no switch on surah number anywhere outside the JSON catalog. Surahs and reciters are pure data.
3. **Offline only.** Zero network calls in Milestone 1. Do **not** add the `INTERNET` permission to `AndroidManifest.xml`. No Firebase, no analytics, no crash reporting, no remote config.
4. **Arabic-first, RTL-first.** Default locale is `ar`. `EdgeInsetsDirectional` everywhere — never raw `EdgeInsets` with left/right assumptions. Layout, icons, sliders, and progress indicators must be RTL-correct.
5. **No new packages** beyond the approved list in A.4. If a requirement seems to need one, raise it as a numbered blocker instead of adding it.
6. **Audio assets are read-only.** Never trim, re-encode, normalize, or programmatically modify recitation audio files.
7. **Respectful presentation.** Ayah text is never truncated, ellipsized, marquee'd, or overlaid with promotional UI. No ads anywhere in the app.

## A.3 Architecture

Clean-architecture-lite, feature-scoped:

```
lib/
  core/
    theme/           AppColors, AppTextStyles, AppTheme
    router/          GoRouter config + route names
    di/              GetIt registrations
    localization/    ar.json, en.json keys
    constants/       AppConstants, AssetPaths
    extensions/
  data/
    models/          Surah, Ayah, Reciter, MemorizationProgress
    datasources/     QuranLocalDataSource, ProgressLocalDataSource
    repositories/    QuranRepository, ProgressRepository
  domain/
    entities/        PlanStep, PlaybackUnit, SessionPlan, SessionConfig
    engine/          RepetitionPlanBuilder  (pure Dart, zero Flutter imports)
  features/
    surah_list/      cubit + screen + widgets
    session_setup/   cubit + screen + widgets
    player/          cubit + screen + widgets
    progress/        cubit + screen + widgets
    settings/        cubit + screen + widgets
  services/
    audio/           AyahAudioResolver, MemorizationPlayerService
```

- **State management:** `flutter_bloc`, Cubit-per-screen. No global god-cubit.
- **DI:** `GetIt` — `lazySingleton` for repositories, data sources and services; `factory` for cubits.
- **Routing:** `GoRouter`, typed args via `state.extra`.
- **Sizing:** `flutter_screenutil` (`.w / .h / .r / .sp`) for all dimensions.
- **Colors:** `Theme.of(context)` / `AppColors` tokens only — no raw `Colors.*` literals.
- **Strings:** `easy_localization`, both `ar.json` and `en.json` populated with accurate Arabic. No hardcoded user-facing strings.
- **Errors:** repository methods return `Either<Failure, T>` (`dartz`).

## A.4 Approved package list

| Concern | Package | Note |
|---|---|---|
| State | `flutter_bloc` | |
| DI | `get_it` | |
| Routing | `go_router` | |
| Sizing | `flutter_screenutil` | |
| i18n | `easy_localization` | |
| Audio | `just_audio` | Milestone 1 uses local assets only |
| Local storage | `hive_ce` + `hive_ce_flutter` | **Not** the original `hive` — it is unmaintained; `hive_ce` is the maintained community fork |
| FP types | `dartz` | |
| Value equality | `equatable` | |

Nothing else without an explicit blocker.

## A.5 Data contracts (JSON assets — the single source of truth)

### `assets/data/surahs.json`
```json
[
  {
    "number": 1,
    "nameAr": "الفاتحة",
    "nameEn": "Al-Fatiha",
    "ayahCount": 7,
    "revelationPlace": "makkah",
    "bismillahMode": "counted_as_ayah_1"
  }
]
```
`bismillahMode` ∈ `counted_as_ayah_1` | `separate_preamble` | `none` (At-Tawbah).
Milestone 1 only needs `counted_as_ayah_1`, but the model, the parser, and the audio resolver must all handle the other two values so surahs 2+ drop in cleanly.

### `assets/data/ayahs/001.json`
```json
{
  "surah": 1,
  "script": "uthmani",
  "source": "<filled in by developer>",
  "ayahs": [
    { "number": 1, "text": "<verbatim from source file>" }
  ]
}
```
One file per surah, named by zero-padded surah number. **The agent does not author the `text` values.**

### `assets/data/reciters.json`
```json
[
  {
    "id": "ahmed_khalil_shaheen",
    "nameAr": "أحمد خليل شاهين",
    "nameEn": "Ahmed Khalil Shaheen",
    "audioMode": "per_ayah_files",
    "basePath": "assets/audio/ahmed_khalil_shaheen",
    "bundled": true,
    "availableSurahs": [1]
  }
]
```
`audioMode` ∈ `per_ayah_files` | `single_file_with_timings`. Both must be implemented in Milestone 1 (see A.6) even though only one is used, because the second reciter's assets may arrive in the other shape.

### Audio asset layout

`per_ayah_files` mode:
```
assets/audio/ahmed_khalil_shaheen/001/001.mp3 ... 007.mp3
assets/audio/ahmed_khalil_shaheen/bismillah.mp3   (only for surahs with separate_preamble)
```

`single_file_with_timings` mode:
```
assets/audio/<reciter_id>/001.mp3
assets/data/timings/<reciter_id>/001.json
```
```json
{ "surah": 1, "ayahs": [ { "number": 1, "startMs": 0, "endMs": 4120 } ] }
```

### `assets/audio/silence_400ms.mp3`
A single short silent clip, used as a gap spacer inside the playback queue (see B.4).

## A.6 `AyahAudioResolver`

One interface, two implementations behind it:

```
AudioSource resolve({ required Reciter reciter, required int surah, required int ayah })
```

- `per_ayah_files` → `AudioSource.asset('<basePath>/<surah3>/<ayah3>.mp3')`
- `single_file_with_timings` → `ClippingAudioSource(child: asset('<basePath>/<surah3>.mp3'), start: startMs, end: endMs)`

The player layer must never know which mode is in use. Adding a reciter = drop assets + append one object to `reciters.json`.
