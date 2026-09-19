# Audio status — ahmed_khalil_shaheen

Where every surah of this reciter stands. Updated whenever a surah is re-cut,
reviewed or withdrawn; the goal is for everything to sit under **Clean**.

Last updated: 2026-09-19 — manifest version 3; surah 24 hand-cut and clean

## How a surah is judged

`tool/audit_audio.py` times every clip and compares it with how long its words should
take at that surah's own pace. It reads either the published packs (`--live`) or a
directory of exported clips (`--dir`), with the same arithmetic the admin tool uses
(`lib/admin/services/segment_audit.dart`), so "clean" means one thing everywhere.
A surah is **clean** when every ayah in `quran.db` has a clip, nothing else is there,
and no clip is under 45% or over 2.2x of what its text calls for. It is a measurement,
not a listening test — a clip can be the right length and still begin a syllable late.

To re-check everything:  `python3 tool/audit_audio.py --live`

## Summary

| state | surahs |
|---|---|
| Clean and live | 112 |
| Needs a hand cut in the admin tool | 2 |
| **Total** | **114** |

## Clean and live (112)

1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 108, 109, 110, 111, 112, 113, 114

## Needs a hand cut (2)

The recording has no pause where the cut belongs, so no pause-based method finds it.
Open the surah in the admin tool and press Split: the rows that do not fit their text
are marked. Use **Edit start and end** on a marked row, listen **across the end**, and
nudge the boundary until it falls between the two ayahs (see `docs/ADMIN_TOOL.md`,
"Fixing a cut by ear"). Publish with **Overwrite paths that already hold audio** ticked,
then bump the reciter's `version` in the manifest.

- **18 الكهف** — ayah 85 is 12.4s against ~3.4s. A replacement recording was tried and is worse — «ثم أتبع سببا» is recited straight into the ayah after it at 84, 89 and 92 — so the original cut stays live.
- **107 الماعون** — ayah 4 is 1.15s against ~4.5s. In the replacement recording ayah 6 is 1.64s and ayah 7 is 7.33s: 6 runs into 7 with no pause.

## How a fix goes live

1. `dart run tool/publish_surah.dart --align --export-only <surahs>` — cut, nothing uploaded
2. `python3 tool/audit_audio.py --dir build/recut <surahs>` — must say CLEAN
3. `dart run tool/publish_surah.dart --recut --replace --publish-from build/recut <surahs>`
   — uploads those very files over the old ones; refuses a surah that is not clean
4. bump the reciter's `version` in the manifest and push it, so phones refresh their packs
5. `python3 tool/audit_audio.py --live <surahs>` — only then does it move to Clean here

## History

- 2026-09-19 — first classification, from the publish logs: 82 clean, 26 review, 5 rebuild, 1 no data.
  It was wrong: the log statistics only caught clips under 1.5s and segments over 2.5x.
- 2026-09-19 — every live clip measured against its own text: 50 clean, 63 faulty, 1 no data.
- 2026-09-19 — cutting moved into one service shared by the admin screen and the CLI
  (`SurahSplitter`): candidates chosen by coverage, alignment by segment length, letter
  names and held vowels weighted from the text, every clip checked against its words.
  "Audio has basmala" and "Audio has isti'adhah" added as recording options.
- 2026-09-19 — 15 recordings replaced by the owner (3, 5, 7, 8, 14, 18, 20, 24, 31, 33, 34,
  47, 48, 83, 107). 62 surahs exported and audited as real files, then uploaded from those
  files in place of the old cuts: 50 from the original recordings, 12 from the new ones,
  including a complete surah 33. Manifest version 1 -> 2.
- 2026-09-19 — all 114 audited live: **111 clean**, 3 need a hand cut (18, 24, 107).
- 2026-09-19 — surah 24's basmala cut by hand in the admin tool (play + boundary editor),
  published over the old clips, audited live: clean. Manifest version 2 -> 3. **112 clean.**
