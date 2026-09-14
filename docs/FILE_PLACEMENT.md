# Where every file goes

Two zips were delivered: `hifz_assets_milestone1.zip` and `mirqat_brand.zip`.
This is the merged target tree.

```
mirqat/                                     ← repo root
├── pubspec.yaml
├── CLAUDE.md
│
├── assets/                                 ← BUNDLED into the app
│   ├── data/
│   │   ├── surahs.json
│   │   ├── reciters.json
│   │   ├── ayahs/
│   │   │   └── 001.json
│   │   └── timings/
│   │       └── ahmed_khalil_shaheen/
│   │           └── 001.json
│   ├── audio/
│   │   ├── silence_400ms.wav               ← use this one
│   │   ├── silence_400ms.mp3               ← keep only if you reject the WAV
│   │   └── ahmed_khalil_shaheen/
│   │       └── 001/
│   │           ├── istiadhah.mp3
│   │           └── 001.mp3 … 007.mp3
│   └── fonts/
│       ├── KFGQPCHafs-Uthmanic-v18.ttf     ← mushaf text ONLY
│       ├── IBMPlexSansArabic-Regular.ttf   ← UI
│       ├── IBMPlexSansArabic-Medium.ttf
│       ├── IBMPlexSansArabic-SemiBold.ttf
│       ├── IBMPlexSansArabic-Bold.ttf
│       └── IBMPlexSansArabic-OFL.txt
│
├── brand/                                  ← NOT bundled. Design source of truth.
│   ├── mirqat-lockup-ar.svg
│   ├── mirqat-lockup-ar-plain.svg
│   ├── mirqat-lockup-ar-onDark.svg
│   ├── mirqat-lockup-ar-plain-onDark.svg
│   ├── mirqat-mark.svg
│   ├── mirqat-mark-onDark.svg
│   ├── mirqat-icon.svg
│   ├── icon/
│   │   ├── icon.png                        ← 1024², build-time input
│   │   ├── icon-foreground.png             ← 1024², Android adaptive
│   │   └── icon-monochrome.png             ← 1024², Android 13 themed
│   └── fallback/
│       ├── AmiriQuran.ttf                  ← licence fallback, NOT shipped
│       └── AmiriQuran-OFL.txt
│
├── docs/
│   ├── BRAND_GUIDE.md
│   └── ASSETS_README.md
│
├── tool/                                   ← Dart convention: `tool/`, not `tools/`
│   └── make_timings.py
│
└── lib/ …
```

## Why things sit where they do

**`brand/` is deliberately outside `assets/`.** Two reasons. Rendering SVG at
runtime needs `flutter_svg`, a package not on the approved list — and it isn't
needed, because the mark is four rounded rectangles and a `CustomPainter` draws
it in about forty lines with perfect scaling and no dependency. The icon PNGs are
build-time inputs to `flutter_launcher_icons`; bundling them would ship three
1024×1024 images inside the APK for nothing.

**Ship one mushaf font, not two.** KFGQPC Hafs is 242 KB and Amiri Quran is
133 KB. Only one is ever used. Amiri Quran moves to `brand/fallback/` and gets
swapped into `assets/fonts/` only if the KFGQPC licence turns out not to cover
your distribution. Don't declare it in `pubspec.yaml` until then.

**Amiri Regular is not in this tree at all.** It was used to draw the wordmark,
and that wordmark is already outlined into the SVG paths. The font itself never
needs to ship.

**`tool/` not `tools/`.** Dart's convention is singular; `pub` and several
analysis presets expect it.

## A trap worth knowing about

IBM Plex Sans Arabic contains U+06E1 (Uthmani sukūn), U+0671 (alef wasla) and the
rest of the Quranic mark repertoire. So if an ayah is accidentally rendered in the
UI font, **it will not show tofu** — it renders cleanly, just with diacritic
positioning that isn't the mushaf's. The "never set ayat in the UI font" rule
therefore cannot be caught by looking at the screen or by a missing-glyph check.
It has to be enforced in code. The prompt turns it into a single-constructor rule
plus a test.

## Palette correction — the guide's first numbers were wrong

Running WCAG contrast on the original palette turned up three real failures:

| Pairing | Original | Result |
|---|---|---|
| `muted` on vellum | 4.29:1 | fails AA body (needs 4.5) |
| `sabr` on vellum | 4.45:1 | fails AA body, barely |
| `muted` on ink-deep | 3.80:1 | fails |
| `sabr` on ink-deep | 3.67:1 | fails |
| **`gold` on vellum** | **2.12:1** | fails everything |

Fixed by splitting the two secondary tokens per mode, the way Material 3 does:

| Token | Light (on vellum) | Dark (on ink-deep) |
|---|---|---|
| `muted` | `#666E7F` (4.62:1) | `#798193` (4.63:1) |
| `sabr` | `#2D7968` (4.69:1) | `#35907B` (4.67:1) |

Gold is unfixable as text on a light surface without ceasing to be gold — so it
stays an **accent only**, never a text colour on vellum. It is fine on ink
(6.64:1) and ink-deep (7.70:1). `BRAND_GUIDE.md` already says gold is accent-only;
this is the number that proves it has to be.

Unchanged and passing: ink on vellum 14.09:1, vellum on ink-deep 16.33:1.
