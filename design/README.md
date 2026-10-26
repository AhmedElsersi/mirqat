# Mirqat — a design proposal

Open `design/index.html` in a browser to see every screen side by side, in light
and dark (the switch at the top). Each screen also opens on its own from
`design/screens/`. Fonts and icons load from Google Fonts and unpkg, so view it
online.

The proposal keeps the brand: the palette in `lib/core/theme/app_colors.dart`,
IBM Plex Sans Arabic for the UI, UthmanicHafs for the Quran, the calm voice and
the brand guide's no-streaks rule. What changes is the structure, the hierarchy
and a handful of components.

**Every word of Quran in the mockups comes from `assets/data/quran.db`,
byte for byte.** The templates in `design/src/` name an ayah, a span of words or
a whole page, and `design/build.py` fills them in. The pages are real mushaf
pages, laid out line by line from the `lines` table. Rebuild after editing a
template:

    python3 design/build.py

## The review

What the app does is strong: the method, the mushaf page with its frame, the
session played over the text, offline audio, the honest copy. The problems are
in how its features are reached. Most of them came from features being added one
at a time, each to the nearest existing screen.

### Structure

1. **There is no primary navigation.** Home is the surah index. The day's work
   sits above it as up to three stacked cards (Today, Wird, Continue reading),
   and the list underneath gets what is left. On a small phone that is under
   half the screen. Search, history and settings are icons in the app bar.
2. **Settings holds the hifz tools.** The memorization plan, the review
   schedule, weak spots, the practice record, backup and the mutashabihat card
   all live in Settings, next to the theme and the audio quality. Six of this
   month's features can only be reached from there. They are things to *do*,
   not things to *set*.
3. **Two cards answer "what do I do today".** The Today card shows the plan's
   portion, what is due for review and the bedtime suggestion. The Wird card
   shows the ranges the reader set. They sit one above the other, and the reader
   has to work out which to follow.
4. **The session sheet is one long form.** The ways of working, the reciter,
   the range, offline audio, repeats, joining, recall rounds, the link test,
   pauses, speed, the sleep timer, reciting to a listener and the memorization
   view all have the same weight. Most sessions only need the first row.
5. **The ayah menu is a list of eight or nine rows**, taller than most screens
   once a range is chosen. The actions used most often (listen, memorize, mark,
   stumble, share) are not easier to reach than the rest.

### Visual

6. **Surah rows are about three times taller than they need to be:** name,
   ayah count, a progress bar and a status line, on all 114 rows. The progress
   bar on a surah not yet started is noise.
7. **The middle dot «·» next to Arabic-Indic digits reads as a zero.**
   «البقرة · ٦٢» looks like «٦٢٠» in IBM Plex Arabic. In the app it comes
   before a number in `session_setup.summary` («{} خطوات · {} تلاوة · {}»),
   `review.today` («مراجعة اليوم · {}») and `plan.today_short`, and in the
   lines joined with `' · '` in `session_bar.dart`, `ayah_actions_sheet.dart`
   (the surah line and the «تشبه» list, both of which end in ayah numbers) and
   `downloads_screen.dart`. Use the Arabic comma «،» wherever a number follows.
8. **Settings shows choices as radio lists and long paragraphs.** Three radio
   rows for the theme, and the text-size note runs to four lines. Segmented
   controls and one-line hints carry the same information.
9. **Every card has the same weight.** Nothing on the home screen is clearly
   the primary action, so starting today's session is never one obvious tap.

### The screens behind the tabs

The first pass looked at the four destinations and the reading view. These
findings are about everything they open — the twenty-odd screens that are
reached from them.

10. **The hifz tools are flat lists with hidden actions.** Reviews, weak spots
    and the mutashabihat are `ListTile`s with two icon buttons at the end, so
    "start this review" and "remove it from the schedule" carry the same
    weight. Nothing on a review row says which of the three rungs it is on.
11. **A surah's progress says its status in words, 286 times.** Every ayah tile
    holds the ayah number, the status word *and* the repeat count in a 120 px
    box; the colour already says the status, and three ayahs fit across a
    phone.
12. **The plan is sixty rows with today's portion among them.** Everything
    already finished stays on screen for good, and the day's portion — the one
    reason to open the screen — is a card halfway down.
13. **History repeats the date on every row**, and search results repeat their
    own rule; both lists say the same thing twenty times over.
14. **Four screens are a title and a paragraph.** Our goal, About us, the
    developer and whose idea this was are four routes under Settings, each one
    an icon over some prose that comes from the same `app.json`.
15. **Settings' own screens explain before they show.** The font screen leads
    with three radio rows and a four-line note, with the preview below the
    fold; backup leads with a five-line paragraph; saved recitations put the
    total size *after* the list.

### Keep

The mushaf frame and cartouche; the colour tokens and their contrast tests; the
session bar floating over the page (not a player screen); highlighting only the
ayah being recited, as one band; RTL throughout; and the voice. There are no
streaks, no guilt and no superlatives anywhere in this proposal.

## The proposal

### Four destinations (a bottom navigation bar)

| Tab | Holds | Answers |
|---|---|---|
| **اليوم** Today | Today's wird (new, recent, old), what is due for review, the bedtime/morning suggestion, continue reading, the plan's progress | What do I do now? |
| **المصحف** Mushaf | Search field, continue reading, surahs / ajzaa / ahzab, history | Where do I want to read? |
| **حفظي** My hifz | What has been memorized (a 30-juz map), the review tiers, the plan, weak spots, mutashabihat and the drill, reciting to a listener, the practice record, backup | How is my hifz, and what strengthens it? |
| **الإعدادات** Settings | Appearance, mushaf font, memorization view, reciter and audio, downloads, session defaults, about | How should the app behave? |

The reading view stays full-screen, with no tab bar. The current "open straight
onto the last page" option becomes "the first screen: Today or the Mushaf".

### Screens

| # | Screen | What changed |
|---|---|---|
| 01 | Today | The Today and Wird cards merge into one page. Today's **new** portion is the one prominent card, with a single "Start" button. The two reviews sit side by side underneath, then what is due, then the bedtime suggestion, then where the reader stopped. |
| 02 | Mushaf | Search becomes a field rather than an icon. Continue reading folds into the index. Each surah row has one line of meta plus a small progress ring, and a weak-spot count only where there is one. |
| 03 | Reading + session | The page is unchanged. The bar adds a **row of steps** (which rung of the ladder, out of how many) and moves "three more times" to a chip. |
| 04 | Recall | A recall round shows the ayah's place, with its ink withheld, and a calm progress line. "Reveal" and "I stumble here" are in reach. There is no score and no countdown. |
| 05 | Session sheet | The ways of working come first: one tap and done. Then the range as two rows, then repeats and recall side by side, then the joining mode with a one-line explanation. The reciter, pauses, speed and sleep timer fold into one row. A live summary (steps, plays, minutes) sits above "Start". |
| 06 | Ayah menu | A header naming the ayah, its surah, its juz and its page. The six frequent actions form a 3×2 grid. Similar ayahs and the range sit below. |
| 07 | My hifz | A 30-juz map of what is memorized, the three review tiers with counts, the plan's progress, and the tools for strengthening hifz, each one tap away. |
| 08 | Mutashabihat drill | A real phrase from `mutashabihat.json` (21:26 «وَقَالُواْ ٱتَّخَذَ ٱلرَّحۡمَٰنُ وَلَدٗاۗ»), with the rest of the ayah veiled in place. The choices are cards. |
| 09 | Wird editor | Each part can be switched on or off, with its range as two fields, plus a "next portion" shortcut that moves the new range on by its own length. |
| 10 | Settings | Settings only, with segmented controls and one-line hints. |
| 11 | Introduction | The method drawn as the logo draws it: rungs climbing to the upper left, the top one gold. |
| 12 | Search | The box is the screen's own, not an icon in the bar. A surah is one row; each ayah hit is a card, whole, with its place under it. The matched word is **not** marked: the match is made against a derived column, and the ayah's bytes are left alone (A.2 rule 1). |
| 13 | History | The places are gathered under the day they belong to, so the date is said once; the page number leads the row. |
| 14 | Surah progress | The surah's state once, at the top, with a ring. Then one cell per ayah — number and tint, a dot where it has been drilled — so forty ayahs fit on one screen. |
| 15 | Review schedule | The three rungs are the filter; «الآن» comes before «لاحقًا»; each row has one start button and a quiet «⋯» for the rest. The ladder says how far a passage has climbed. |
| 16 | Plan — followed | Today's portion is the one prominent card with one button. What is finished folds behind a row; the delete moves into «⋯». |
| 17 | Plan — new | The range as two rows, days as a stepper with ready numbers, and what the choice amounts to in one line above the button. |
| 18 | Weak spots | Most-stumbled first; «تكرار هذه الآية» is a button, not an icon; the mark is taken off by a quiet ×. |
| 19 | Practice record | Four numbers said once. No streak, no badge, and nothing about a day that passed (BRAND_GUIDE §6). |
| 20 | Mutashabihat | The phrase first and largest, the surah filter a chip rather than a dropdown row, and the drill reachable from the card itself. |
| 21 | One phrase | Each ayah whole with the shared words tinted, grouped by surah; the drill — the reason the screen is open — becomes a button. |
| 22 | Saved recitations | The total at the top. A reciter's bulk actions sit on the reciter's own row; a stale surah carries its tag and a re-download beside it. |
| 23 | The whole mushaf | What is downloading now is the subject of the screen, with the run's progress and the surah's; the other reciters are rows under it. |
| 24 | Mushaf font | The preview first, the four-line note reduced to one, the size slider marked at the default, and the page fonts in their own card. |
| 25 | Session defaults | The session sheet's own order, so the two are learned once. The default range becomes a segmented control. |
| 26 | Backup | What a copy holds as four tags instead of a paragraph; the path as a latin line read from the left; the merge's result as one calm row. |
| 27 | About | The four prose routes become one page: the app and its version, the goal, who we are, whose idea it was, the developer and the ways to reach them. The words still come from `app.json`. |
| 28 | Update available | An optional update speaks once, over the app, and takes «لاحقًا» for an answer. |
| 29 | Maintenance | One thing on the screen, one button, and when to expect the app back. A required update is this page with a store button. |

### Components

- **The ladder mark** (`.ladder`): four short rungs, climbing to the upper left
  as in the logo. Done rungs are emerald, the current one gold. It is the app's
  own progress symbol, used for review tiers and a passage's place on the
  ladder, instead of generic bars or a flame.
- **Steps** (`.steps`): the session's rungs as segments in the player bar.
- **Juz map** (`.juz-strip`): thirty cells tinted by how much of each juz is
  memorized. It is a map, not a score.
- **Number diamonds** (`.num`) for surah and ayah numbers, echoing the ayah
  markers. **Rings** for each surah's progress.
- **Segmented controls** for the theme and the joining mode; a **quick-action
  grid** in sheets.
- **Gold stays an accent:** the current rung, progress fill, the highlight band
  and the reading mark. It is never a surface and never text on cream.

## Fitting it to the code

- **No new packages.** `NavigationBar` and `SegmentedButton` are Material 3.
  GoRouter's `StatefulShellRoute.indexedStack` gives each tab its own stack;
  `MushafScreen` stays a full-screen route above the shell.
- **Today** is `TodayCard` and `WirdCard` merged into one screen. The cubits
  stay as they are (`ReviewCubit`, `SettingsCubit`, the plan). **My hifz**
  collects existing screens (review, plan, weak spots, mutashabihat, stats,
  backup) behind one overview. Nothing about the data changes.
- **The session sheet** keeps `SessionCubit` as is. Only the order changes,
  and the advanced fields move behind one row.
- **The screens behind the tabs are the same cubits and the same data.** Nothing
  new is fetched, stored or computed: 12–29 reorder what their screens already
  build. The ones that cost more than a rewrite of `build()` are 14 (a cell
  grid in place of the tile grid), 15 (sections and a tier filter over
  `ReviewCubit`'s list), 21 (the comparison card gains a tinted span) and 27
  (four routes answered by one screen; the old routes stay for deep links).
  25 keeps `SessionTuningControls` exactly as it is — the session sheet and the
  defaults screen must never drift apart.
- **The separator fix** (finding 7) is a change to the translations alone, and
  worth making whether or not the rest is adopted.
- **CLAUDE.md is respected throughout:** ayah text is never truncated (the ayah
  menu names the ayah instead of quoting part of it), Quranic text appears only
  in the Quran face, and `EdgeInsetsDirectional` and RTL mirroring are assumed
  everywhere.

## Files

    design/
      index.html        the gallery (light/dark)
      README.md         this review
      build.py          fills templates from quran.db
                        ({{ayah}} {{words}} {{marked}} {{page}} {{cells}}
                         {{surah}} {{ayahs}} {{n}})
      src/*.html        the screen templates
      screens/*.html    built screens (do not edit; rebuild)
      styles/app.css    tokens and components
      styles/screen.js  theme switch, icons, mushaf line fitting
