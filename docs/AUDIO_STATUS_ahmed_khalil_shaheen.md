# Audio status — ahmed_khalil_shaheen

Where every surah of this reciter stands. Updated whenever a surah is re-cut,
reviewed or withdrawn; the goal is for everything to sit under **Clean**.

Last updated: 2026-09-19 — manifest version 4; all 114 surahs clean

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
| Clean and live | 114 |
| Needs a hand cut in the admin tool | 0 |
| **Total** | **114** |

## Clean and live (114)

All of them, 1 to 114.

Most were cut by the splitter alone. Three had no pause where a cut belonged — the
recording runs one ayah, or the basmala, straight into the next — and were finished by ear
in the admin tool with the play buttons and the boundary editor: **24** (the basmala), **18**
(ayah 85) and **107** (ayah 4).

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
- 2026-09-19 — surahs 18 and 107 cut by hand in the admin tool and published over the old
  clips; the admin pushed the manifest itself. Audited live: clean. Manifest version 3 -> 4.
  **All 114 clean.**
