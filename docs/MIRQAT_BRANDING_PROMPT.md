# Build Prompt — Mirqat Branding

**Target agent:** Claude Code (CLI)
**Prerequisite:** Milestone 1 Phase 0 scaffold exists. This prompt can run before
or after the data layer; it touches theme, identity and one widget, nothing else.
**Reference:** `docs/BRAND_GUIDE.md`, `docs/FILE_PLACEMENT.md`

Read the whole document before writing code. Do not begin Phase 1 until the
Phase 0 hard stop is cleared.

---

## Phase 0 — Discovery and hard stop

Report, do not fix:

1. Current `name:` in `pubspec.yaml`, the Android `applicationId`, the iOS
   `PRODUCT_BUNDLE_IDENTIFIER`, and every place the old placeholder name appears.
2. Whether `assets/fonts/` contains the five TTFs listed in `FILE_PLACEMENT.md`,
   and whether `brand/icon/` contains the three PNGs.
3. Existing `AppColors` / `AppTextStyles` / `AppTheme` symbols — **exact** names,
   so this prompt extends them rather than creating parallel duplicates.
4. Whether any widget currently hardcodes a `Color(0x…)` or `Colors.*` literal.
   List every occurrence with file and line.

**STOP.** Report the above and wait. Do not rename anything yet — a bundle-ID
change touches Android and iOS project files and must not be mixed into an
unreviewed batch.

## Phase 1 — Design tokens

`lib/core/theme/app_colors.dart`

Two secondary tokens differ per mode; this is deliberate and comes from measured
WCAG contrast, not taste. Do not "simplify" them back into one value.

```dart
abstract final class AppColors {
  // brand constants
  static const ink     = Color(0xFF16233F);
  static const inkDeep = Color(0xFF0E1626);
  static const gold    = Color(0xFFC8A54B);
  static const vellum  = Color(0xFFF7F3EA);

  // mode-specific — see the contrast table in FILE_PLACEMENT.md
  static const mutedLight = Color(0xFF666E7F); // 4.62:1 on vellum
  static const mutedDark  = Color(0xFF798193); // 4.63:1 on inkDeep
  static const sabrLight  = Color(0xFF2D7968); // 4.69:1 on vellum
  static const sabrDark   = Color(0xFF35907B); // 4.67:1 on inkDeep
}
```

**Hard rule:** `gold` is never a text colour on `vellum` — the pairing measures
2.12:1 and fails every WCAG threshold. Gold is permitted as: the active rung in
the mark, a progress-bar fill, an icon tint on ink, and a focus ring. Nowhere
else. Add this as a comment above the token so nobody re-litigates it later.

**Acceptance:** a unit test computes the WCAG contrast ratio for
(mutedLight, vellum), (sabrLight, vellum), (mutedDark, inkDeep),
(sabrDark, inkDeep) and asserts each ≥ 4.5. Write the ratio helper yourself; it
is eight lines and needs no package.

## Phase 2 — Typography, and the one rule that matters

Register in `pubspec.yaml`:

```yaml
  fonts:
    - family: MirqatUI
      fonts:
        - asset: assets/fonts/IBMPlexSansArabic-Regular.ttf
          weight: 400
        - asset: assets/fonts/IBMPlexSansArabic-Medium.ttf
          weight: 500
        - asset: assets/fonts/IBMPlexSansArabic-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/IBMPlexSansArabic-Bold.ttf
          weight: 700
    - family: QuranUthmani
      fonts:
        - asset: assets/fonts/KFGQPCHafs-Uthmanic-v18.ttf
```

`lib/core/theme/app_text_styles.dart`:

- All UI styles use `MirqatUI`.
- **Exactly one** style may use `QuranUthmani`: `AppTextStyles.ayah`. Give it a
  generous `height` (1.9–2.1) — Uthmani diacritics stack tall and clip at default
  line height.

### The enforcement problem

IBM Plex Sans Arabic **contains** U+06E1, U+0671 and the rest of the Quranic mark
set. An ayah accidentally rendered in the UI font shows **no tofu and no visible
error** — it renders cleanly, with diacritic placement that simply isn't the
mushaf's. You cannot catch this by looking at the screen.

So enforce it structurally:

1. Create `AyahText` in `lib/core/widgets/ayah_text.dart`. It is the **only**
   widget permitted to render Quranic text, and it hardcodes
   `AppTextStyles.ayah`. It accepts no `style` parameter and no
   `TextStyle` override.
2. Every screen renders ayat exclusively through `AyahText`. A raw `Text()`
   holding ayah content anywhere else is a defect.
3. **Acceptance test:** a repo-wide source scan asserts that the string
   `QuranUthmani` appears in exactly two files — `pubspec.yaml` and
   `app_text_styles.dart` — and that `ayah_text.dart` is the only file
   referencing `AppTextStyles.ayah`.

## Phase 3 — The mark, in Dart

`lib/core/widgets/mirqat_mark.dart`

Do **not** add `flutter_svg`. The mark is four rounded rectangles; a
`CustomPainter` draws it exactly, scales without raster artefacts, and costs no
dependency.

Geometry, in a 100 × 100 logical box (copy these numbers exactly — they are the
SVG's):

```
bar height  13.0      length 44.0      corner radius 6.5
step dx    -12.0      step dy  -19.5   (each rung up-and-left)
rung 0 (bottom)  x 46.00  y 72.75
rung 1           x 34.00  y 53.25
rung 2           x 22.00  y 33.75
rung 3 (top)     x 10.00  y 14.25      ← gold
```

Ink extent is x 10→90, y 14.25→85.75. Scale by `size.width / 100`.

API: `MirqatMark({double size, Color? baseColor, Color? accentColor})`, defaulting
to `ink`/`gold` on light and `vellum`/`gold` on dark, read from the theme.
`shouldRepaint` returns true only when a colour or size changes.

Rungs must climb up-and-**left**. That is forward for an Arabic reader, and it is
the whole point of the mark. Do not mirror it under `Directionality`; it is
already correct for RTL and mirroring would make it descend.

**Acceptance:** a golden test at 48, 96 and 512 px in both light and dark. Verify
all four rungs remain visually separated at 48 px.

## Phase 4 — App identity

### 4a. Name and bundle ID

| Field | Value |
|---|---|
| pubspec `name` | `mirqat` |
| Android `applicationId` | `com.mirqat.app` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `com.mirqat.app` |
| Android `android:label` | `مرقاة` |
| iOS `CFBundleDisplayName` | `مرقاة` |
| iOS `CFBundleName` | `Mirqat` |

Add `ar` to iOS `CFBundleLocalizations` and set
`CFBundleDevelopmentRegion` to `ar`, or the Arabic display name will not appear
on an Arabic-locale device.

### 4b. Icons

Add **`flutter_launcher_icons` as a `dev_dependency`.** This is a proposed
exception to the no-new-packages rule: it is build-time only, contributes nothing
to the runtime or the APK, and the alternative is hand-generating fifteen raster
sizes across two platforms.

```yaml
flutter_launcher_icons:
  image_path: "brand/icon/icon.png"
  android: true
  adaptive_icon_background: "#16233F"
  adaptive_icon_foreground: "brand/icon/icon-foreground.png"
  adaptive_icon_monochrome: "brand/icon/icon-monochrome.png"
  ios: true
  remove_alpha_ios: true
```

`icon-foreground.png` is already inset for the Android adaptive safe zone —
content sits inside the central 626 px circle of the 1024 px canvas. **Do not
substitute `icon.png` as the foreground**; it fills 66% of its canvas and the
circular mask would clip the outer rungs.

`remove_alpha_ios: true` is required — App Store Connect rejects iOS icons with
an alpha channel.

### 4c. Splash

Solid `inkDeep` with the mark centred at 96 dp. No wordmark: Arabic at splash
scale on a small phone is unreadable, and a splash that flashes text is worse than
one that doesn't. If `flutter_native_splash` is proposed, flag it as a second
dev-dependency exception rather than adding it silently.

## Phase 5 — Brand strings

Into `ar.json` / `en.json`. Never hardcoded.

| Key | ar | en |
|---|---|---|
| `app.name` | مرقاة | Mirqat |
| `app.tagline` | ٱرْقَ آيةً آية | Ascend, one ayah at a time |
| `app.subtitle` | حفظ بالتكرار والوصل — بلا إنترنت | Memorize by repetition — offline |

`app.tagline` is vocalised deliberately: ٱرْقَ without harakat reads ambiguously.
Keep the marks.

## Phase 6 — Voice, as constraints

These are implementation rules, not copy suggestions.

1. **No streak state anywhere.** No consecutive-day counter in the progress
   model, no "last opened" comparison driving a message, no red badge for a
   missed day. If a future ticket asks for streaks, that is a product decision to
   escalate, not a feature to add. Pressuring someone back to worship through
   loss-aversion is a dark pattern pointed at their relationship with the Quran.
2. **No emoji** in any string file, and none in any widget adjacent to an ayah.
3. **Completion copy is flat.** `«تمّ»` / "Done." Never superlatives, never
   exclamation marks stacked on praise.
4. **Counters are neutral and localised.** `«٣ من ٥»` in Arabic with
   Arabic-Indic digits; `3 of 5` in English. Use the locale's numeral system —
   do not force Western digits into Arabic UI.

**Acceptance:** a test asserts no emoji codepoint (U+1F300–U+1FAFF, U+2600–U+27BF)
appears in either localisation file.

## Verification checklist

- [ ] `flutter analyze` clean; no `Colors.*` or raw `Color(0x…)` outside `app_colors.dart`
- [ ] Contrast test passes for all four mode-specific pairings
- [ ] `QuranUthmani` appears in exactly two files
- [ ] `AyahText` is the only renderer of Quranic text and accepts no style override
- [ ] Mark golden tests pass at 48 / 96 / 512 px, light and dark
- [ ] Mark climbs up-and-left in both `TextDirection.rtl` and `.ltr`
- [ ] Adaptive icon: nothing clipped under a circular mask
- [ ] iOS icon has no alpha channel
- [ ] App name shows as مرقاة on an Arabic-locale device, Mirqat on English
- [ ] No emoji in `ar.json` / `en.json`
- [ ] Dark mode complete — not an inverted afterthought

## Assumptions

1. `# ASSUMED` Bundle ID `com.mirqat.app`. Changing it after first store upload is
   impossible, so confirm before Phase 4.
2. `# ASSUMED` Ship KFGQPC Hafs only; Amiri Quran stays unbundled in
   `brand/fallback/`.
3. `# ASSUMED` `flutter_launcher_icons` is acceptable as a dev-dependency.
4. `# ASSUMED` The WAV spacer is chosen over the MP3. If reversed, Phase 3 of the
   Milestone 1 prompt must be updated to say 391.7 ms rather than 400 ms.

## Blockers

1. **Trademark for مرقاة / Mirqat is unverified** — Egyptian Trademark Office, plus
   a current App Store and Play search. Do this before the first store upload;
   after that a rename costs the listing, the URL and any reviews.
2. **`com.mirqat.app` availability is unverified.** Check before Phase 4.
3. **Recitation redistribution rights** remain open from Milestone 1. Unchanged by
   this prompt, still blocking release.
