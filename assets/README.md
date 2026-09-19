# Asset bundle

Every surah, reciter and font is data — no Dart changes to add one
(CLAUDE.md A.2 rule 2).

## What ships

| Path | Contents |
|---|---|
| `data/quran.db` | All 114 surahs: names, ayah counts, bismillah placement, ayah text, mushaf pages/lines/words. Built by `tool/build_quran_data.py`; read-only. |
| `data/reciters.json` | Reciter catalog. Ahmed Khalil Shaheen only. |
| `data/timings/ahmed_khalil_shaheen/001.json` | Offsets into the original full-surah recording. Unused in `per_ayah_files` mode; kept in case the mode is switched. |
| `audio/ahmed_khalil_shaheen/001/001.mp3 … 007.mp3` | One clip per ayah. |
| `audio/ahmed_khalil_shaheen/001/istiadhah.mp3` | The isti'adhah. **Not an ayah** — see below. |
| `audio/silence_400ms.wav` | Gap spacer. |
| `fonts/UthmanicHafs_V22.ttf` | Bundled Quran font (`QuranUthmani`), the companion of `data/quran.db`'s text. |
| `fonts/KFGQPCHafs-Uthmanic-v18.ttf` | Unbundled. Companion of the retired per-surah JSON text. |
| `fonts/AmiriQuran.ttf` | Unbundled fallback, SIL OFL 1.1. |
| `translations/{ar,en}.json` | UI strings. |

## The isti'ādhah is not ayah 1

The source recording opens with أعوذ بالله من الشيطان الرجيم before the
Bismillah. It is a preamble, and it must never enter the `PlaybackUnit` queue
as an ayah — that would shift every ayah by one and break the repetition
counts. `Reciter.hasIstiadhah` marks its availability; the session setup screen
exposes it as an opt-in toggle.

The same slot serves surahs whose `bismillahMode` is `separatePreamble` and
which therefore need a standalone Bismillah clip.

## Text is never generated

Ayah text reaches the screen byte-for-byte as `quran.db` stores it — no
normalization, no tatweel removal, no whitespace fixing. A tatweel here is often
the seat of a hamza or small yeh; removing it moves the mark to another letter.
The loader rejects a surah whose ayah count, numbering or ordering disagrees
with its catalog row rather than padding or trimming it. Comparison-only
stripping lives in `test/text_comparison.dart`.

## Adding a surah's audio

Every surah is already listed and readable; one with no audio from any reciter
is marked «قراءة فقط». To make it memorizable:

1. Drop `audio/<reciter>/<nnn>/*.mp3` and add that directory to the `assets:`
   list in `pubspec.yaml` — Flutter bundles only the direct children of a
   declared directory.
2. Add the surah number to the reciter's `availableSurahs`.
3. Run `dart run tools/verify_assets.dart`.

## Adding a reciter

Append one object to `data/reciters.json` and drop the audio. Both
`per_ayah_files` and `single_file_with_timings` are supported. A
`single_file_with_timings` reciter also needs its
`data/timings/<reciter_id>/` directory listed in `pubspec.yaml`.

## Rights

The recordings' metadata credits `www.islamway.net` (2019). Redistribution
permission is still unsettled — hosting for listening is not a licence to
bundle. The KFGQPC font's terms permit free use without modification; confirm
coverage at `qurancomplex.gov.sa/en/techquran/dev`, or switch the `fonts:`
entry in `pubspec.yaml` to Amiri Quran, which is OFL and commercial-safe.
