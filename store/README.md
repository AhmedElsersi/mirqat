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

## Screenshots

`google/phone/` (1080 × 1920) and `google/tablet/` (1600 × 2560) are taken from
the running app on Android emulators by `tool/store_screenshots_android.sh`;
`docs/PLAY_LISTING.md` has what each one shows, the order to upload them in, and
how to regenerate them.

## Apple

`apple/LISTING.md` is the whole App Store Connect listing, ready to paste —
name, subtitle, keywords, descriptions in Arabic and English, App Privacy, age
rating, content rights, the reviewer's notes and a checklist.
`apple/PRIVACY_POLICY.md` is the corrected privacy policy the listing depends
on. `apple/iphone/` (1320 × 2868) and `apple/ipad/` (2064 × 2752) are the
screenshots, taken from the running app by `tool/store_screenshots.sh`; the
Play set is taken the same way on Android, by `tool/store_screenshots_android.sh`.
