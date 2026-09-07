# Assets the developer must supply

Milestone 1 cannot progress past Phase 0 until these exist. Nothing here may be
generated, transcribed from memory, or approximated by the agent
(CLAUDE.md A.2 rules 1 and 6).

## 1. Uthmani text for Al-Fatiha

**File:** `assets/data/ayahs/001.json` (already present, `"ayahs": []`)

Fill the two empty fields, leaving the rest of the shape untouched:

```json
{
  "surah": 1,
  "script": "uthmani",
  "source": "<name + version of the text source, e.g. 'KFGQPC Hafs / Tanzil 1.1'>",
  "ayahs": [
    { "number": 1, "text": "<verbatim>" },
    { "number": 2, "text": "<verbatim>" },
    { "number": 3, "text": "<verbatim>" },
    { "number": 4, "text": "<verbatim>" },
    { "number": 5, "text": "<verbatim>" },
    { "number": 6, "text": "<verbatim>" },
    { "number": 7, "text": "<verbatim>" }
  ]
}
```

Exactly 7 ayahs, numbered 1..7 with no gaps or duplicates — the Phase 1 loader
validates this against `ayahCount` in `assets/data/surahs.json` and fails loudly
on any mismatch rather than padding or trimming.

Bismillah is ayah 1 (`"bismillahMode": "counted_as_ayah_1"`, Hafs numbering).

## 2. Recitation audio — Ahmed Khalil Shaheen, Al-Fatiha

Either shape works; the resolver supports both. Pick one.

### Shape A — `per_ayah_files` (what `reciters.json` currently declares)

```
assets/audio/ahmed_khalil_shaheen/001/001.mp3
assets/audio/ahmed_khalil_shaheen/001/002.mp3
assets/audio/ahmed_khalil_shaheen/001/003.mp3
assets/audio/ahmed_khalil_shaheen/001/004.mp3
assets/audio/ahmed_khalil_shaheen/001/005.mp3
assets/audio/ahmed_khalil_shaheen/001/006.mp3
assets/audio/ahmed_khalil_shaheen/001/007.mp3
```

The directory already exists and is declared in `pubspec.yaml`.

### Shape B — `single_file_with_timings`

```
assets/audio/ahmed_khalil_shaheen/001.mp3
assets/data/timings/ahmed_khalil_shaheen/001.json
```

```json
{
  "surah": 1,
  "ayahs": [
    { "number": 1, "startMs": 0, "endMs": 0 }
  ]
}
```

If you choose Shape B, change `"audioMode"` in `assets/data/reciters.json` to
`"single_file_with_timings"` and add `assets/data/timings/ahmed_khalil_shaheen/`
to the `assets:` list in `pubspec.yaml` (Flutter only bundles the direct
children of a declared directory).

## 3. Silence spacer

**File:** `assets/audio/silence_400ms.mp3`

One silent MP3, 400 ms. Repeated to build the inter-ayah, inter-repeat and
inter-step gaps in the playback queue. Supply it, or approve generating it
locally — note `ffmpeg` is not currently installed on this machine.

## 4. Uthmani-capable font (optional but recommended)

**File:** `assets/fonts/<name>.ttf` + a `fonts:` entry in `pubspec.yaml`

Without a bundled Uthmani font the ayah text falls back to the platform Arabic
font, whose rendering of Uthmani diacritics and pause marks varies by device
and Android version. `AppTextStyles.quranFontFamily` is the single place to
point at it once supplied.
