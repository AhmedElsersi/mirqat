# Play Store graphics

Generated from `brand/` (the same source `flutter_launcher_icons` reads —
see `pubspec.yaml`), via a one-off script, not checked in as a build step:

- `google/icon-512.png` — 512x512, no alpha (Play rejects an icon with one).
  Downscaled from `brand/icon_1024.png`.
- `google/feature-graphic-1024x500.png` — the app's arch-and-book mark
  (`brand/icon_foreground_1024.png`, transparent) centered on the same
  vertical green gradient as the launcher icon's background
  (`brand/icon_background_1024.png`). No wordmark text on it: rendering
  Arabic correctly needs shaping (joining forms + bidi reordering) that a
  plain image script can't do without pulling in a text-shaping library, and
  Play doesn't require text on this graphic — the store name shows
  underneath it regardless.

Regenerate either with Pillow if `brand/` changes:

```python
from PIL import Image
icon = Image.open("brand/icon_1024.png").convert("RGB")
icon.resize((512, 512), Image.LANCZOS).save("store/google/icon-512.png")
```

(see git history for the full feature-graphic composite script if the
gradient or mark also needs updating).

## Screenshots — not generated, capture these by hand

Play requires 2-8 phone screenshots, 16:9 or 9:16, 320px-3840px on the short
side, JPEG or 24-bit PNG (no alpha). Run the app (`flutter run --release`
once signing is set up, or `--debug` is fine for screenshots) and capture:

1. **Surah list** (`/`, `SurahListScreen`) — the home screen, showing the
   catalog with per-surah memorization progress. Captures the core "what is
   this app" value prop at a glance.
2. **Reader — range selection** (`/surah/:surahNumber`, `ReaderScreen`) —
   the Quranic text with an ayah tapped to start a range, session-settings
   drawer visible if it reads well in a still frame. Shows the text is real
   Uthmani script, not a mockup.
3. **Player — mid-session** (`/session`, `PlayerScreen`) — during playback,
   with the step timeline and repetition counter visible (e.g.
   "Repetition 2 of 5", step header, ayah text highlighted). This is the
   talqeen mechanic the whole app is built around; it should not be skipped.
4. **Progress** (`/surah/:surahNumber/progress`, `ProgressScreen`) — a surah
   with a mix of memorized/in-progress/not-started ayahs, showing the status
   labels and repetition counts.
5. **Settings** (`/settings`, `SettingsScreen`) — reciter, theme, language,
   and default-session sections, to show the app is configurable (reciter
   catalog in particular, since "add a reciter with zero code" is a real
   product property worth this app looking maintained).

Capture on a real or emulated device at a common phone resolution (e.g.
1080x2400) in **Arabic**, the default locale, since that's the primary
audience and the default listing language. An English-locale set is a nice
to have for the English listing, not required at launch.

Save them as `store/screenshots/ar/01-surah-list.png` etc. (create the
directory) — nothing reads this path automatically, it's just where to keep
them before uploading to Play Console under **Store presence → Main store
listing → Phone screenshots**.

## Apple

`apple/LISTING.md` is the whole App Store Connect listing, ready to paste —
name, subtitle, keywords, descriptions in Arabic and English, App Privacy, age
rating, content rights, the reviewer's notes and a checklist.
`apple/PRIVACY_POLICY.md` is the corrected privacy policy the listing depends
on. `apple/iphone/` (1320 × 2868) and `apple/ipad/` (2064 × 2752) are the
screenshots, taken from the running app by `tool/store_screenshots.sh`; the
Play screenshots in `google/` predate the reading-and-session redesign and can
be retaken the same way on an Android emulator.
