# Asset bundle — Milestone 1 (complete)

Drop `assets/` into the repo root. **All four blockers are now closed.** Phase 0 can
proceed straight to Phase 1.

---

## The one thing to read before anything else

**Your recording opens with the isti'ādhah, not with ayah 1.**

The file has nine speech segments separated by silence, but Al-Fatiha has seven
ayahs. The first segment (0.48–4.56 s) is
أعوذ بالله من الشيطان الرجيم, and the last two segments are both ayah 7,
split by a breath pause at 34.8 s.

A naive "split on the six longest silences" would have mapped isti'ādhah → ayah 1,
ayah 1 → ayah 2, and so on: **every ayah shifted by one**, with ayahs 6 and 7
merged. The text on screen would have disagreed with the audio for the entire
surah, and in a memorization app that teaches the error by repetition.

How it was confirmed rather than assumed: ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ ends ayah 1 and is also
the whole of ayah 3, so those two stretches should sound alike. Comparing them
acoustically (DTW over log-mel spectra) gave a distance of **0.11** under
"segment 1 is isti'ādhah" versus **0.28–0.30** for unrelated control segments —
a clean 2.5× separation. Under the alternative reading, the same test gave 0.299
against controls of 0.29 and 0.27: no match at all.

The isti'ādhah is preserved as its own optional clip. Don't delete it — surahs
other than Al-Fatiha need a standalone Bismillah clip anyway
(`bismillahMode: separate_preamble`), and the same slot handles both.

## 1. Uthmani text — DONE

`assets/data/ayahs/001.json`

**Source:** KFGQPC Hafs Unicode text v18 (King Fahd Glorious Quran Printing
Complex, `qurancomplex.gov.sa`), normalised to **Unicode NFC**.

Three independent sources now agree: KFGQPC, the quranenc.com Uthmani edition,
and the text you pasted. All seven ayahs are canonically identical across all
three.

**One subtlety worth knowing.** Your text and the raw KFGQPC file were *not*
byte-identical, even though they are the same scripture. Two encoding
differences: combining marks in a different order (fatha before vs. after a
neighbouring mark), and آ written as the precomposed U+0622 in yours but as
U+0627 + U+0653 in KFGQPC's. Both render identically and are canonically
equivalent — but `==` returns false, so search, highlighting, and any
text-to-audio mapping keyed on strings would silently fail across the two forms.

The shipped file is normalised to NFC, which makes it byte-identical to the text
you sent. **Normalise to NFC on load for anything you ever compare** — if a
future surah arrives in a different form, this bites again, and the symptom
(highlighting that mysteriously misses one ayah) looks nothing like the cause.

Bismillah is ayah 1, 7 ayahs numbered 1–7, no BOM. Have someone read it against a
physical mushaf before you publish; cross-source agreement catches transcription
drift, not scripture review.

## 2. Recitation audio — DONE, per-ayah

`reciters.json` is set to `"audioMode": "per_ayah_files"` — real cuts, so no
`ClippingAudioSource` and no timings lookup at runtime.

| File | Duration | Content |
|---|---|---|
| `001/istiadhah.mp3` | 3.94 s | أعوذ بالله… (optional, not an ayah) |
| `001/001.mp3` | 3.53 s | بِسۡمِ ٱللَّهِ… |
| `001/002.mp3` | 3.92 s | ٱلۡحَمۡدُ لِلَّهِ… |
| `001/003.mp3` | 2.80 s | ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ |
| `001/004.mp3` | 2.82 s | مَٰلِكِ يَوۡمِ ٱلدِّينِ |
| `001/005.mp3` | 4.68 s | إِيَّاكَ نَعۡبُدُ… |
| `001/006.mp3` | 3.66 s | ٱهۡدِنَا ٱلصِّرَٰطَ… |
| `001/007.mp3` | 14.11 s | صِرَٰطَ ٱلَّذِينَ… (includes the natural breath pause) |

Cut with ffmpeg, re-encoded 128 kbps / 44.1 kHz / mono, metadata stripped.
Boundaries were placed at each segment's true speech onset and offset (35 dB below
that segment's own peak, not a global threshold), then padded 80 ms in and 150 ms
out. Every file was decoded again after cutting and checked for clipped edges:
lead silence 60–80 ms, tail 30–180 ms on all eight. Nothing is cut mid-word.

The natural 470–940 ms gaps between ayahs were deliberately **excluded** from the
cuts, so the repetition engine's `intraBlockPauseMs` / `betweenRepeatPauseMs`
settings fully control pacing rather than fighting silence baked into the audio.

`assets/data/timings/ahmed_khalil_shaheen/001.json` holds the same boundaries as
offsets into your original full-surah file, in case you ever switch back to
`single_file_with_timings`. Not used in `per_ayah_files` mode.

**Rights — NOT SETTLED.** The recordings were downloaded from
**surahquran.com**; the files' own metadata credits `www.islamway.net` (2019),
so they had already been passed along before that. surahquran.com's terms
(`surahquran.com/terms.html`) allow downloading only for
«الاستخدام الشخصي غير التجاري» — personal, non-commercial use — and forbid
«أي استخدام آخر» without their prior written permission. Bundling the clips,
re-hosting them on our CDN and shipping them in a store app is none of that.

Neither site recorded the recitation, so neither can license it: the rights are
Sheikh Ahmed Khalil Shaheen's, or his producer's. **Get his permission in
writing before release** — see `docs/APP_REVIEW_NOTES.md` and the content-rights
section of `store/apple/LISTING.md`, which is what blocks the App Store
submission. Hosting for listening is not a licence to bundle.

## 3. Silence spacer — DONE, use the WAV

| File | Actual duration | Size |
|---|---|---|
| `silence_400ms.wav` | **400.000 ms** exactly | 35 KB |
| `silence_400ms.mp3` | 391.7 ms (−8.3 ms) | 1.6 KB |

MP3 cannot encode exactly 400 ms: LAME adds encoder delay and pads the final
frame, and frames quantise to ~26 ms at 44.1 kHz. A naive encode came out at
444 ms — 11% long. Tuned to the closest achievable it still misses by 8.3 ms, and
that error accumulates across every gap in a session. The WAV is sample-exact at
44.1 kHz mono, matching the ayah files, so the player won't re-initialise when it
crosses a spacer.

If you keep the MP3 anyway, change the Phase 3 spec to say 391.7 ms, not 400 ms.

## 4. Font — DONE, two options

Both verified against the **actual** 32 unique codepoints in Al-Fatiha, including
U+0671 alef wasla, U+06E1 Uthmani sukun, U+0670 superscript alef and U+0653
maddah. Neither is missing a glyph.

| File | Glyphs | Licence |
|---|---|---|
| `KFGQPCHafs-Uthmanic-v18.ttf` | 615 | KFGQPC terms — free use, no modification; confirm at qurancomplex.gov.sa/en/techquran/dev |
| `AmiriQuran.ttf` | 266 | **SIL OFL 1.1** (`AmiriQuran-OFL.txt` included) — commercial-safe |

Ship KFGQPC Hafs: it is the exact companion to the v18 text, so diacritic
positioning is as its designers intended. Amiri Quran is the fallback if the
KFGQPC terms don't cover your distribution.

## pubspec.yaml

```yaml
flutter:
  assets:
    - assets/data/
    - assets/data/ayahs/
    - assets/data/timings/ahmed_khalil_shaheen/
    - assets/audio/
    - assets/audio/ahmed_khalil_shaheen/001/

  fonts:
    - family: QuranUthmani
      fonts:
        - asset: assets/fonts/KFGQPCHafs-Uthmanic-v18.ttf
```

Flutter only bundles the **direct children** of a declared directory, so each
nested folder needs its own line. Point `AppTextStyles.quranFontFamily` at
`QuranUthmani`.

## Two spec changes this forces

1. **`Reciter` needs a `hasIstiadhah` flag** (already in `reciters.json`). The
   Phase 1 model and the Phase 4 session-setup screen should expose an optional
   "play isti'ādhah before the session" toggle. It is not an ayah and must never
   enter the `PlaybackUnit` queue as one, or the repetition counts break.
2. **Phase 1's validator should compare NFC-normalised text**, and the loader
   should normalise on read. Add it to the corrupted-fixture test set: the same
   ayah in NFD should pass, not fail.

`tools/make_timings.py` is still included for the next surah — but note it would
have gotten this one wrong on its own. Run it, then verify by ear, then check
segment durations against ayah word counts before trusting the output.
