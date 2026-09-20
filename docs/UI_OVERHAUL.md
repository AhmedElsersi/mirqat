# UI / UX overhaul

One branch per stage, each stacked on the one before: `ui/1-colours`,
`ui/2-frames`, and so on. Nothing here is released: version 1 is in Play review, and
a release only ever happens from a `v*` tag or a manual run of the Release
workflow. Each stage ends with screenshots for the owner's approval.

## Decisions (owner, 2026-09-19 — every default accepted)

**Contract changes**
- `app.json` is approved remote config: one public GET beside `manifest.json`
  on the GitHub Pages site, failing quietly to a bundled default. It carries
  the update rules and the About / Goal / Developer content. CLAUDE.md A.2
  rule 3 is amended to allow exactly this.
- New packages: `package_info_plus` (the app's own version) and `url_launcher`
  (store page, email, social links).
- Sessions may span surahs, which changes the repetition engine: the next
  surah's basmala plays once before its ayah 1 and is not an ayah; cumulative
  joining continues across the boundary; a range runs forward only.

**Look**
- Navy → the icon's palette: deep green `#0B4E35`→`#063221`, gold `#E1B45C`,
  cream `#FAEDD5`. Dark theme is green-black with cream text. The cave splash
  stays as it is.
- The Islamic frame and the surah-name cartouche are drawn in code — no image
  assets, no SVG package — on the real mushaf pages and the one-surah view.
- After seeing the first, thin frame the owner asked for more presence: the
  band is 18-30 px with a woven lattice, guard stripes and ruled corner cells.
  A page's text size comes from its **width alone**; a page too tall for the
  screen **scrolls**, frame and all, rather than shrinking.
- The page carries its own furniture in the borders, like a printed mushaf:
  **surah and juz** along the top, the **page number** at the foot, the
  **hizb** in the right-hand border. The mushaf screen therefore has **no app
  bar**.
- **A tap** anywhere shows a bar at the foot of the page, and a second tap puts
  it away; **a long press** on an ayah opens its actions. (A tap used to open
  the ayah; one gesture cannot mean both.)

**Home and reading**
- Home has two tabs, surahs and ajzaa, switched by tap or swipe.
- View mode — list | grid | real mushaf (default list) — moves to Settings;
  its icons leave the home bar, which keeps history and settings.
- Real mushaf view is continuous and reopens on the last page. List/grid reopen
  on the list with a history button. "One surah / one juz at a time" exists
  only under list/grid: real page layout showing only that surah's or juz's
  lines, with previous/next at the end.
- History: the last 20 reading positions (surah, ayah, page, time), newest
  first, stored locally; reading positions only.
- The per-surah progress icon and the Progress screen stay.

**Session**
- The player screen and the steps timeline are removed. The reading view gets
  a bottom bar: play/pause, previous/next step, stop, a repeat counter, and a
  button for session settings.
- The reciting ayah is highlighted and the page follows it; swiping away pauses
  following and shows a "back to the ayah" chip.
- Session settings include start surah+ayah and end surah+ayah (default: the
  same surah). Changed mid-session: speed and pauses apply at once; reciter,
  repeats, range or join mode ask "restart from the beginning" or "continue
  from the current ayah".
- Play with nothing selected: the whole surah (one-surah view), or from the
  first ayah on the page to the end of its surah (real mushaf).

**Settings and the rest**
- Settings grouped into cards; "Session settings" is its own page, and the same
  form is the in-session sheet.
- About the developer: Ahmed Elsersi, email, GitHub, LinkedIn, WhatsApp,
  Facebook, optional photo — all from `app.json`, empty ones hidden.
- About us and Our goal: from `app.json`, editable in the admin.
- Onboarding and How to use: in the app (they describe the app's own screens),
  Arabic and English.
- App version at the bottom of Settings. Update dialog with two levels per
  platform: *minimum* (blocking) and *latest* (dismissible, at most daily),
  fixed localized text plus an optional "what's new" note. Play link known;
  the iOS link is a field in the admin until the App Store ID exists.

## Stages

| # | stage | status |
|---|---|---|
| 1 | Colours | done, approved (Quran text stays dark green) — `ui/1-colours` |
| 2 | Frames: mushaf page, one-surah view, surah-name cartouche | done — `ui/2-frames` |
| 2b | Thicker frame, scrolling page, labels in the borders, no app bar, tap-to-show bar | done — `ui/2b-frame-thicker`, awaiting the owner's look |
| 3 | Home: ajzaa tab, view mode in Settings, history, last position | done — `ui/3-home`, awaiting the owner's look. A juz opens the mushaf at its first page; "one juz at a time" as its own view is stage 4 |
| 4 | Reading + session merged; cross-surah sessions; player screen removed | done — `ui/4-reading-session` (three commits: engine, sections, session), awaiting the owner's look |
| 5 | Settings cards, Session settings page, About / Goal / Developer / How to use, onboarding | done — `ui/5-settings-about`, awaiting the owner's look |
| 6 | `app.json`, version + update dialog, admin editor | |

## Stage 4 — what was decided while building it

- **The reader and player screens are gone.** One reading view (`MushafScreen`)
  serves the whole mushaf, one surah and one juz; the session lives in it.
- **Long press on an ayah** offers: listen from here to the end of the surah,
  memorize this ayah alone, make it the start of the range, make it the end.
  A chosen range is tinted on the page and can be given back to the page.
- **While a session plays, only the ayah being recited is tinted.** Tinting the
  whole range washed the page end to end and said nothing; the bar says what
  is playing. A marked run is painted as one band along the line — under the
  words and the spaces between them — not as a box per word.
- **Pauses** changed mid-session re-queue the session at the play it was on,
  600 ms after the slider rests. It restarts the ayah being heard; asking the
  reader about a gap would be worse.
- **"Carry on from this ayah"** resumes at the first play of that ayah in the
  new plan — the start of its drill — or at the top if the new range no longer
  holds it.
- **The opening basmala** now follows CLAUDE.md to the letter: only a session
  that starts at ayah 1 opens with it. The code had always played it whatever
  the start ayah, which went unnoticed while sessions defaulted to the whole
  surah; "play" now defaults to the first ayah *on the page*.
- **The skip glyphs are swapped in Arabic.** The framework does not mirror
  them, so "previous", which sits on the right, would have pointed left.
- **Dropped with the player screen:** the step timeline (as decided) and the
  "restart this step" button — "previous step" at the first repeat does the
  same. The per-surah *progress* icon stays on the home rows, not in the bar.
- **Remembered ranges** (`RangeBehaviour.lastUsed`, in Settings) still work:
  a surah opened whole gets its last range back as a *chosen* range, once, and
  starting a session inside one surah writes its range down. A range across
  two surahs is not remembered — the setting is per surah.
- **`AyahText.flowing`** has no caller left (the one-surah view is page layout
  now). Kept, with its tests and the U+06DD note, until stage 5 shows whether
  anything wants it.

## Stage 5 — what was decided while building it

- **Settings are five cards:** appearance, reciter, audio and storage, session,
  about. The session's values are a page of their own, built from the very
  widget the reading view's session sheet uses, so the two cannot drift.
- **The Arabic font-size slider is gone from Settings.** Since stage 4 every
  ayah is drawn in the mushaf's page layout, where a line is as large as the
  page is wide — there is nothing left for the slider to change, and a control
  that does nothing is worse than none. The stored value is kept. If a text
  size is wanted back it needs a view that is not page layout; that is a
  product decision, not a slider.
- **`app.json` is bundled for now** (`assets/data/app.json`): About us, Our
  goal, the developer. Stage 6 publishes it beside the manifest and lets the
  admin tool edit it; the screens already read it through `AppInfoService`
  and will not change. The developer's photo is in the file but not drawn
  yet — fetching it is a network call, and that waits for the rule-3
  amendment stage 6 brings.
- **The developer's card** ships with the name as given, the email, and the
  GitHub account the CDN already names. LinkedIn, WhatsApp and Facebook are
  blank and therefore hidden, to be filled in from the admin tool.
- **The introduction** is four leaves of icon and words — no ayah on a slide.
  Shown once; an install updating from before it existed sees it too, which
  is deliberate, since that update is also when the player screen went away.
  How to use can bring it up again.
- **The splash waits for the stored settings** (at most a second) before it
  hands over. The settings cubit is created lazily and the splash is the
  first thing to read it, so without the wait every first launch went
  straight past the introduction. Caught by the first test written for it.

