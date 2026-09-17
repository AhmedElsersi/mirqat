# Asset bundle

Every surah, reciter and font is data. Adding either means dropping files in
here and appending to the JSON catalog — no Dart changes
(CLAUDE.md A.2 rule 2).

## What ships

| Path | Contents |
|---|---|
| `data/surahs.json` | Surah catalog. Al-Fatiha only in Milestone 1. |
| `data/ayahs/001.json` | Uthmani text, KFGQPC Hafs v18, NFC-normalised. |
| `data/reciters.json` | Reciter catalog. Ahmed Khalil Shaheen only. |
| `data/timings/ahmed_khalil_shaheen/001.json` | Offsets into the original full-surah recording. Unused in `per_ayah_files` mode; kept in case the mode is switched. |
| `audio/ahmed_khalil_shaheen/001/001.mp3 … 007.mp3` | One clip per ayah. |
| `audio/ahmed_khalil_shaheen/001/istiadhah.mp3` | The isti'adhah. **Not an ayah** — see below. |
| `audio/silence_400ms.wav` | Gap spacer. |
| `fonts/UthmanicHafs_V22.ttf` | Bundled Quran font (`QuranUthmani`), the companion of `data/quran.db`'s text. |
| `fonts/KFGQPCHafs-Uthmanic-v18.ttf` | Unbundled. Companion of the legacy `data/ayahs/*.json` text, which the reader no longer renders. |
| `fonts/AmiriQuran.ttf` | Unbundled fallback, SIL OFL 1.1. |
| `translations/{ar,en}.json` | UI strings. |

## The isti'ādhah is not ayah 1

The source recording opens with أعوذ بالله من الشيطان الرجيم before the
Bismillah. It is a preamble, and it must never enter the `PlaybackUnit` queue
as an ayah — that would shift every ayah by one and break the repetition
counts. `Reciter.hasIstiadhah` marks its availability; the session setup screen
exposes it as an opt-in toggle.

The same slot serves surahs whose `bismillahMode` is `separate_preamble` and
which therefore need a standalone Bismillah clip.

## Text is never generated

Ayah text is loaded verbatim and only ever NFC-normalised, so two canonically
equivalent encodings of the same ayah compare equal. The loader rejects a file
whose ayah count, numbering or ordering disagrees with the catalog rather than
padding or trimming it. See `QuranLocalDataSource`.

## Adding a surah

1. Drop `data/ayahs/<nnn>.json` — verbatim text, contiguous `1..ayahCount`.
2. Append the surah to `data/surahs.json` with its `bismillahMode`.
3. Drop `audio/<reciter>/<nnn>/*.mp3` and add that directory to the `assets:`
   list in `pubspec.yaml` — Flutter bundles only the direct children of a
   declared directory.
4. Add the surah number to the reciter's `availableSurahs`.
5. Run `python3 tools/check_font_coverage.py`; a codepoint the font lacks
   renders as a tofu box.

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
