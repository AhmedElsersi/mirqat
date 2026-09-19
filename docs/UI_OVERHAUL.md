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
| 2 | Frames: mushaf page, one-surah view, surah-name cartouche | |
| 3 | Home: ajzaa tab, view mode in Settings, history, last position | |
| 4 | Reading + session merged; cross-surah sessions; player screen removed | |
| 5 | Settings cards, Session settings page, About / Goal / Developer / How to use, onboarding | |
| 6 | `app.json`, version + update dialog, admin editor | |
