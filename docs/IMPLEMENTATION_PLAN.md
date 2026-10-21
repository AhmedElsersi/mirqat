# Implementation plan — the ideas of `NEW_IDEAS.md`, in order

Each phase is built, tested against the whole app, and committed on its own
before the next begins. Every phase keeps the contract in `CLAUDE.md`:
no new package, no network beyond A.2 rule 3, ayah text only through
`AyahText` and never altered, `EdgeInsetsDirectional`, both translations,
`Either<Failure, T>` from repositories, cubits as GetIt factories.

**Definition of done for every phase**

1. `flutter analyze` reports no issues.
2. Every test outside `test/ui/` passes, including the phase's own new tests.
3. `test/ui/` fails in exactly the set it failed in before the phase
   (eight tests, in `app_ui_test.dart` and `mushaf_screen_test.dart`, failed
   before this plan began — known, separate, not touched here). A new failure
   there is a regression and blocks the commit.
4. Stored data written by an older build still reads: every new field in a
   Hive map has a default, and a malformed record costs that record, never
   the box.

Order is by value and by dependency: stumble marks come before the scheduler
because the scheduler reads them.

**Status**

| Phase | State | Commit |
|---|---|---|
| 1a — what comes next? | done | `3a3f249` |
| 1b — memorization view | done | `3c05ad8` |
| 2 — stumble marks, weak spots | done | `1dd3af2` |
| (asked for) mushaf font page | done | `80e0018` |
| 3 — review ladder, grading, today | done | `8c5f8ee` |
| 4 — sleep timer, listen, three more | done | `06c89fc` |
| 5 — mutashabihat | built; data awaits a QUL download (see NEW_IDEAS §4) | `951792d` |
| 6a — hifz plan | done | `bacfb05` (its "behind schedule" line removed in 6b) |
| 6b — quiet stats | done | this commit |

---

## Phase 1 — Finish recall (§1)

Recall rounds shipped in `786003d`. Two pieces remain.

### 1a. "What comes next?" — the chaining drill

*Why:* recall breaks between ayahs more often than inside one. This tests
the links.

*Design.* `SessionConfig.chainRecall` (bool, default false). When on, and the
range has more than one ayah, the plan closes with a `ChainStep` per
consecutive pair: the cue ayah is played, then a recall gap, then the next
ayah as the answer. It applies to every connect mode, continuous included —
it is a pass over the range, not a per-ayah drill step.

The queue must know *which* play is preceded by a gap. Today it tests
`stepType == recall`; that becomes a property of the unit,
`PlaybackUnit.asked` — true for every recall-step play and for the second
play of a chain step. `PlaybackQueueBuilder` and
`SessionPlan.estimatedDuration` read `asked`, so there is one rule in two
places that cannot disagree.

*Edges.* A one-ayah range adds no chain steps. A range crossing surahs
chains across the boundary (the last ayah of one surah cues the first of the
next — that link is recited, so it is tested). `_shapeOf` includes the flag,
so toggling it mid-session asks *start again / carry on*.

*Tests.* Plan shape for 1..3; single ayah adds nothing; cross-surah link;
`asked` set on exactly the right units; queue lays gaps before asked units
only; estimate counts them.

### 1b. Progressive fading — a memorization view while reading

*Why:* "cover the page a little more each pass" — the oldest self-test.

*Design.* `AppSettings.memorizationView` ∈ `off | firstWords | markersOnly`
(stored by name, unknown reads as `off`). On the mushaf page:

- `firstWords`: every recited word is veiled except the first word of each
  ayah (`Word.position == 1`) — the cue.
- `markersOnly`: every recited word is veiled; ayah markers stay.

Veiling is the same mechanism recall uses: ink withheld in place, the band
showing where the words lie. Basmala lines, surah headers and held-back
words are never veiled. A **tap on a veiled word peeks** — its whole ayah is
revealed until the next tap elsewhere; while the view is off a tap still
toggles the bar, as now.

Chosen from the session sheet (a three-way segmented control) and from the
reading card in Settings; written through `SettingsCubit`, read with
`context.select` on the page so only pages rebuild.

*Tests.* Settings round-trip and unknown value; page-view widget test:
which words are veiled at each level, peek reveals one ayah, markers never
veiled.

---

## Phase 2 — Stumble marks (§3)

*Why:* cheap, and it makes the scheduler smarter the day it exists.

*Design.*
- Model: `MemorizationProgress.stumbles` (int, default 0) and
  `lastStumbleAt`. Kept in the existing progress box — one record per ayah
  already exists, and a second box would split one ayah's state in two.
- Repository: `markStumble(surah, ayah)`, `clearStumble(surah, ayah)`,
  `stumbledAyahs()` (every record with `stumbles > 0`, ordered by most
  recent).
- Ayah menu: *I stumble here* / *Clear the stumble mark*.
- In a session, a stumbled ayah inside the range gets **extra repetitions**:
  the plan builder takes an optional `Set<AyahRef> reinforce` and adds
  `reinforceExtra` (2) to that ayah's learn-step repeats. The engine stays
  pure: the set is handed in, like the ayah counts.
- On the page a stumbled ayah carries a faint dotted underline — not a tint,
  so it never competes with the session highlight or the reading mark — and
  only while `showStumbles` (default on) is set.
- **Weak spots** screen: every stumbled ayah, grouped by surah, each opening
  the mushaf at it, with *drill these* starting a session over the ayah
  alone, and *clear*.

*Edges.* Clearing a surah's progress clears its stumbles too. A stumble on
an ayah never memorized still counts — it is where the reader slips.

*Tests.* Model round-trip (old records read 0); repository marks, clears,
lists in order; plan builder adds exactly the extra repeats to exactly the
reinforced ayahs and nothing in continuous mode beyond what it already does;
weak-spots cubit.

---

## Phase 3 — Review scheduler, self-grading and the Today card (§2, §1)

*Why:* turns sessions into a method — sabaq, sabqi, manzil — without the
reader keeping a notebook.

*Design.*
- **Domain (pure Dart).** `ReviewScheduler` with a ladder of intervals in
  days, `[1, 3, 7, 14, 30, 90]`. A `ReviewCard` per memorized *range*
  (start ref, end ref, step on the ladder, due date, last grade, created).
  `grade(card, Grade.solid | shaky | forgot, now)`:
  solid → next step; shaky → same step, due again after that step's
  interval; forgot → step 0, due tomorrow. Tier derives from age:
  `sabaq` (created < 7 days), `sabqi` (< 30), `manzil` (older).
- **Storage.** Its own Hive box, `review_cards`, maps keyed by card id —
  a card is a range, not an ayah, so it does not belong in the progress box.
- **Self-grading.** When a session plays out, or is stopped after at least
  one full pass of every ayah, the bar offers *How did it go?* — three
  buttons. A grade creates the card for that range if none exists, or grades
  the existing one. Skippable; never a dialog that blocks.
- **Today card** on the home screen, above *continue reading*: the cards due
  today, by tier — new (sabaq), recent (sabqi), old (manzil) — each opening
  the mushaf at the range with the session chosen and its preset applied
  (sabaq: the reader's defaults; sabqi: half the repeats and one recall
  round; manzil: one repeat, one recall round, continuous). Nothing due → the
  card is not drawn.
- **Review screen**: every card, by tier and due date, with delete.

*Edges.* Clock moving backwards: due dates compare by calendar day in local
time, never by elapsed duration. Two cards over the same range: grading
finds the exact range; an overlapping one stays separate. A range later
deleted from the catalog (impossible today, but data): a card whose refs do
not resolve is skipped, not shown.

*Tests.* Scheduler ladder arithmetic and day boundaries; card storage
round-trip and malformed record; due-today selection; grade from the session
cubit creates then grades; Today card selection logic.

---

## Phase 4 — Listening that serves memorization (§5)

- **Listen-only loop.** A fourth connect mode would change a persisted enum;
  instead `SessionConfig.listenLoops` is not added — the existing
  `continuous` mode with repeats *is* the loop. What is missing is the
  shortcut: *Listen to this range* on the ayah menu and the sheet, which sets
  continuous, one repeat per pass, recall off, and the pass count.
- **Sleep timer.** `SessionCubit.setSleepTimer(Duration? | endOfPass)`:
  a `Timer` that pauses (never stops — the place is kept) and clears itself;
  *end of pass* pauses at the next `isLastUnitOfStep`. Shown in the bar as a
  small countdown chip. Cancelled by stop, by a new session, by close.
- **One more time.** Long-press on the bar's ayah title: *this ayah ×3 more*.
  Implemented as a re-queue at the current unit with an inserted one-off
  `LearnStep` — the same path pause changes use — so the engine does not
  grow a mutation API.

*Tests.* Sleep timer pauses after the duration with a fake clock; end-of-pass
pauses at the right unit; cancelled on stop; the shortcut builds the
expected config; the extra repeats land at the current unit.

---

## Phase 5 — Mutashabihat (§4)

*Constraint.* The pairs are Quranic data. They are **never authored from
memory**: rule A.2.1's spirit is that the app never makes up anything about
the text. The phase builds the whole feature against a data file whose rows
come from a published source (QUL's *Mutashabihat* resource), imported by
`tool/` the way `quran.db` is.

*Design.* `assets/data/mutashabihat.json` —
`[{"group": [[s, a], [s, a], …]}]`, refs only, no text. `MutashabihatRepository`
loads it once. Ayah menu: *Similar ayahs (n)* when the ayah is in a group →
a comparison screen rendering each ayah through `AyahText`, fetched from
`quran.db` byte for byte, with play buttons that go through the normal
session path (a one-ayah, one-repeat session).

*If the source cannot be fetched or verified in this environment*, the code
ships with an **empty** file and the feature stays invisible (no group, no
menu entry), and the data import is recorded as a numbered blocker in
`docs/NEW_IDEAS.md`. An empty list is honest; an invented one is not.

*Tests.* Loader with a fixture; malformed rows skipped; refs out of range
skipped; menu entry appears only for grouped ayahs.

---

## Phase 6 — A hifz plan and quiet stats (§6)

- **Plan.** *Memorize from X to Y in N days* → daily portions split by
  *recitation weight* of the text (letters, from `text_search`'s length, a
  derived column — never the rendered text itself), stored as one record in
  settings. The Today card shows *today's new portion* first, opening it as a
  sabaq session; finishing it advances the plan.
- **Stats.** On the progress area: days practised (from the dates sessions
  ran), ayahs held (memorized count), minutes listened (accumulated from
  real played durations where measured). Totals only, shown plainly, no
  celebration — and no streak, nor anything marking a day missed or a plan
  "behind": BRAND_GUIDE §6, enforced by brand_voice_test. (A streak was in
  the first draft of this plan; that test caught it.)

*Tests.* Portion split covers the range exactly, never splits an ayah, never
an empty day unless the range is shorter than the days; totals across gaps
and across midnight.

---

## Phase 7 — Tasmee', hand-the-phone mode (§7)

*Design.* From the session sheet: *Recite to a listener*. The reading view
enters a mode where the reader's range is fully veiled for the reciter's
eyes but the **listener** — who holds the phone — sees the text: so the mode
shows the page plainly, and a tap on any word records a **stumble** at that
ayah (phase 2) with a brief confirmation, and a *mistakes: n* counter in the
bar. Ending the mode offers *drill the stumbled ayahs*. No audio plays.

*Tests.* Tap records a stumble on the right ayah; counter; ending offers the
drill with exactly those ayahs.

---

## Phase 8 — Export and import progress (§8)

*Design.* One JSON document — schema version, progress records, review
cards, plan, reading mark — written to the application documents directory
as `mirqat-progress-<date>.json`, its path shown so it can be copied off the
device. Import reads a file at a path from that same directory (listed for
the reader to choose), validates the schema version, and **merges**:
per ayah the larger repeat count and the later dates win; cards by id with
the later `lastReviewed` winning. Never a silent overwrite.

No share sheet (that is `share_plus`, a blocker) and no file picker (not
approved): the directory listing is the picker.

*Tests.* Round-trip export → import into an empty store reproduces it;
merge rules; a newer schema version is refused with a reason; a malformed
file changes nothing.

---

## Phase 9 — Smaller touches (§9)

- **Session presets with names** — *new / quick review / deep drill* —
  saved from the sheet; picked with one tap. Stored as a list in settings.
- **Resume an interrupted session** — the active plan's config and unit
  index written on every unit change (debounced) and offered on the bar when
  the same range is opened again within a day.
- **About this surah** — a line under the surah header menu: Makki/Madani,
  ayah count, juz span, all from `quran.db` already loaded.
- **Multiple reading marks** is *not* taken: one mark is a decision recorded
  in the contract (A.5, "the reading mark: one ayah"). The scheduler's tiers
  already hold the several places a hafiz keeps.

---

## Blockers (A.2 rule 5) — not built

1. Daily reminder notification — needs `flutter_local_notifications`.
2. Record-and-compare — needs a recording package and a microphone
   permission decision.
3. System share sheet for the export — needs `share_plus`.
