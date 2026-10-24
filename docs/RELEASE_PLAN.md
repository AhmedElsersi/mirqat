# Release plan — the October batch, in three waves

Everything in `docs/NEW_IDEAS.md` is built on `dev`. It does not all go out at once.
Each wave tells one story, and the riskiest data, the mutashabihat, goes out last.
Features of a later wave stay in the code, compiled and tested. Only the ways **into**
them are commented out, each block tagged so it can be found and restored:

```
// RELEASE-1.4(<feature>)          start of a commented-out block
// END RELEASE-1.4(<feature>)      its end
... // RELEASE-1.4: remove         a stand-in line to delete when the block comes back
// ignore: unused_element          kept only while the thing it covers is unreachable
```

`grep -rn "RELEASE-1.4" lib test` lists every spot for the next wave, and
`grep -rn "RELEASE-1.5" lib test` the one after.

## 1.3: now (reading and the session, made stronger)

| Feature | Commit |
|---|---|
| Four-tab home (Today, Mushaf, My hifz, Settings) and the redesign | `8611aba` … `4dfbe54` |
| QPC V2 face and the mushaf font page | `0dcc2ab`, `80e0018` |
| Memorization view: cover the page, tap to reveal | `3c05ad8` |
| Recall rounds and the chain drill ("what comes next?") | `786003d`, `3a3f249` |
| Stumble marks, weak spots, weak spots on the surah list | `1dd3af2`, `eea3f0f` |
| Presets: built-in, Listen, the reader's own | `fda6c1e`, `ef8e353`, `71889cf` |
| Sleep timer, "three more", resume an interrupted session | `06c89fc`, `292d69e` |
| Ayah menu: surah line, juz span | `35e0296`, `d3cf3cc` |
| Today's wird: new, recent, old | `387209e` |
| Backup and restore (Android send/pick too) | `c477ea0`, `77e3515` |
| Share a whole page as an image | `86609e9` |

**What the reader sees.** Today has the wird and *continue reading*. My hifz has the
juz map, weak spots and the backup button. The introduction has five slides, and How to
use leaves out tasmee', review, plan and similar ayahs.

## 1.4: next (the review system)

| Feature | Slug | Entry points commented out |
|---|---|---|
| Review ladder: grading after a session, the due list, the three rungs | `review-ladder` | session bar grade prompt; Today *due* section; My hifz review section; backup "review schedule" tag; onboarding review slide; How to use step |
| Bedtime and morning | `bookends` | Settings switch; Today bookend card |
| Hifz plan | `hifz-plan` | Today plan card and "Memorization plan" button; My hifz plan card; backup "plan" tag; How to use step |
| Quiet stats | `stats` | My hifz row |
| Tasmee': reciting to a listener | `tasmee` | Session sheet button; My hifz row; How to use step |

**Two texts were swapped for this release.** `onboarding.test_body_solo` stands in for
`onboarding.test_body`, which mentions the listener. `today.empty_body_no_plan` stands in
for `today.empty_body`, which offers a plan. When 1.4 ships, restore the originals and
delete the two `*_solo` and `*_no_plan` keys from `ar.json`, `en.json` and `locale_keys.dart`.

## 1.5: later (mutashabihat)

| Feature | Slug | Entry points commented out |
|---|---|---|
| Similar ayahs in the ayah menu, the side-by-side screen, the browse list, the drill | `mutashabihat` | the ayah menu's list (`mushaf_screen.dart`, replaced by an empty list); My hifz row; onboarding slide; How to use step |

Before it ships, have someone qualified read through the 807 phrases, and confirm the one
QUL range that was corrected (48:10, words 23–25). See `NEW_IDEAS.md` §4.

## What keeps running behind a hidden feature

These are deliberate. None of them is visible.

- **Practice log**: 1.3 keeps recording it, so stats in 1.4 open with real history.
- **Review cards**: none are created, because grading is the only way in. The due list,
  bookends and plan therefore have nothing to show even if reached.
- **Routes**: every route stays registered, and a screen opened by name still works.
  Only the buttons are gone.
- **Mutashabihat index**: My hifz still counts its phrases for the hidden row. It is a
  cheap, read-only query.
- **Backup**: it still exports and merges reviews and the plan. The merge note ("the
  latest for each review") and the result line ("reviews: 0") mention reviews. Both are
  accurate, and were left as they are.

## Shipping a wave

1. `grep -rn "RELEASE-1.4" lib test assets`. For each hit, uncomment the block, delete
   the lines marked `RELEASE-1.4: remove` and their `ignore:` lines, and restore any
   commented imports.
2. In `test/`, remove `skip: true /* RELEASE-1.4… */` from the eight held-back tests
   (`today_view_test`, `session_cubit_test`, `settings_and_progress_ui_test`).
3. Restore the swapped texts (see 1.4 above).
4. Run `flutter analyze` and then `flutter test --timeout 120s`. Both must be clean.
5. Bump the version and follow `docs/STORE_RELEASE.md`. Merge to `main` only once the
   wave is done.

## Before 1.3 itself

- [ ] Merge `main` into `dev`. `main` is at 1.2.1+32 while `dev` still says 1.2.0+29.
  Then set 1.3.0 with the next build number.
- [ ] Confirm the QPC V2 page fonts are live on R2 under `fonts/qpc-v2/`. The face falls
  back quietly, but it would ship looking unfinished.
- [ ] Check on a device: a first launch (five slides), Today with nothing set, My hifz
  with no weak spots, a backup round trip.
- [ ] Update the store listing (`docs/PLAY_LISTING.md`) so it names only the 1.3 features.
