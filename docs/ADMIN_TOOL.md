# The admin tool

A macOS-only workbench that turns one whole-surah recording into one clip per
ayah and publishes it to the CDN. It never ships in the phone app.

## Start it

```
./run_admin.sh
```

It reads the R2 keys from `admin.env` (gitignored) and needs `ffmpeg` on the
PATH (`brew install ffmpeg`). With a key missing it refuses to start and says
which. Add `GITHUB_TOKEN` and `GITHUB_REPO` to `admin.env` and it also pushes
`manifest.json` for you; without them it writes `build/manifest.json` and tells
you to publish it yourself.

## Publishing a surah

1. **Reciter** — pick one, or **Add reciter…** (id, Arabic and English name,
   optional riwayah and portrait). A reciter added here appears in the app with
   no new release.
2. **Surah** — all 114, straight from `quran.db`.
3. **Choose recording…** — the whole-surah mp3.
4. **What the recording holds:**
   - **Audio has basmala** — on by default. Untick it when the file starts at
     ayah 1. No `000` clip is made and the manifest records `hasBasmala: false`.
     Only applies to surahs whose basmala is separate from ayah 1.
   - **Audio has isti'adhah** — off by default. Tick it when the file opens with
     the isti'adhah: it is cut off and never published.
5. **Split.**
6. Read the result (below), fix what is marked, then **Publish to R2**.

## What Split does

1. Finds the pauses in the recording with ffmpeg, from strict to lenient, and
   stops at the first setting where no stretch of the recording is left without
   a pause and there are comfortably more pauses than cuts needed.
2. Works out how long each ayah *should* take from its text in `quran.db`:
   letters, plus extra for held vowels and for the opening letters
   (`الٓمٓ`, `كٓهيعٓصٓ`), which are recited as names.
3. Chooses, among the pauses, the set of cuts that makes every segment the right
   length for its own words. Every cut lands in a real pause; none is invented.
4. Checks each clip against its text and marks the ones that do not fit.

The **Silence threshold** and **Minimum silence** fields only steer the first,
plain split; the alignment picks its own settings. **Align to text** re-runs
step 3 after you have edited segments.

## Reading the result

- The header shows segments found against segments expected, e.g.
  `4 segments · expected 4 (basmala + 3 ayahs)`.
- Under it: **Every clip fits its text**, or **N clips do not fit their text**.
- Each row shows the file name it will get, the ayah text, the start and end
  times and the length. A row in red with *length does not fit the text* is
  under 45% or over 2.2x of what its words call for — almost always a cut in the
  wrong place, or two ayahs recited in one breath.
- Per row, four actions:
  - **Play** — plays that segment straight from the recording (press again to
    stop). Nothing is encoded to listen, so an edit is heard at once.
  - **Edit start and end** — see below.
  - **Split at the quietest point** — cuts the segment in two at a pause.
  - **Drop this segment**.

## Fixing a cut by ear

**Edit start and end** opens a small editor for one segment:

- **Start** and **End** can be typed — `mm:ss.mmm`, or plain seconds — and
  applied with Enter, or nudged by **−0.5 −0.1 +0.1 +0.5** seconds.
- Under each field is a checkbox, **ticked by default**:
  - *Ticked* — **Also moves the end of the segment before** / **the start of
    the segment after**. The two segments stay joined, so there is never a gap
    or an overlap to tidy up. Use it when the cut between two ayahs is simply
    in the wrong place.
  - *Unticked* — **Only this segment**. The neighbour stays where it is, and
    whatever is left between the two is **cut out and goes into no clip**. Use
    it for something that belongs to neither ayah: a cough, a repeated phrase,
    an isti'adhah before the basmala. The editor and the list both show how
    many seconds are being cut out.
- An unjoined edge can leave a gap but never an overlap — it stops at its
  neighbour, because two clips sharing the same second would each recite words
  that belong to one of them. To go *past* a neighbour, tick the box again. No
  edit can squeeze a segment under 0.2 s.
- **Align to text** re-cuts everything from the pauses, so it discards hand
  edits, gaps included.
- Four things to listen to: **First 3 s** (does it begin on the ayah's first
  word?), **Last 3 s** (does it end on its last?), **Across the end** (three
  seconds either side of the cut — how a boundary a word early or late actually
  sounds) and **Whole segment**.
- Under the fields it says whether the clip now fits its text, and the list
  behind re-checks as you go.

This is the edit that does not need a pause. Where a reciter runs the basmala
into ayah 1, or one ayah into the next, the splitter has nothing to find and
the row is marked red: open it, listen **across the end**, nudge until the cut
falls between the two ayahs, then publish with the overwrite box ticked. To
drop a preamble from the front of the first segment, move its **Start**.

## Publishing

- A count that does not match is blocked until you type an **override reason**,
  which is written to the log next to the upload.
- A surah that is already published is refused unless you tick **Overwrite
  paths that already hold audio**. A surah's clips always have the same names,
  so overwriting replaces it whole — nothing is deleted and nothing is left
  behind. Bump the reciter's `version` in the manifest afterwards so phones
  re-download their packs.
- It exports every clip, uploads them, builds and uploads the pack, and merges
  the surah into the manifest.

## Many surahs at once — the command line

The same cutting service, without the screen:

```
dart run tool/publish_surah.dart --align --export-only --source-dir <dir> 24 39
python3 tool/audit_audio.py --dir build/recut 24 39        # must say CLEAN
dart run tool/publish_surah.dart --recut --replace --publish-from build/recut 24 39
python3 tool/audit_audio.py --live 24 39                   # confirm on the CDN
```

`--no-basmala` and `--has-istiadhah` are the two checkboxes. `--publish-from`
uploads the files that were audited rather than cutting again, and refuses a
surah that is not clean.

## app.json — about, developer, updates

The button at the top right of the tool, **app.json — about, developer,
updates**, opens an editor for the one other file the app reads from the Pages
site. It needs the same `GITHUB_TOKEN` and `GITHUB_REPO` as publishing the
manifest, and nothing else.

It opens on **what is live now** (or, before the first publish, on the copy
bundled with the app, and says which). Four sections:

- **About us** and **Our goal** — English and Arabic side by side.
- **The developer** — name, photo, and five ways of reaching them. A link left
  blank is not shown in the app. Links are read the way people type them: an
  email without `mailto:`, a WhatsApp number with spaces and a plus, a profile
  without `https://`. **Photo…** uploads the picture to the bucket under a name
  made from its own bytes, so a new photo is a new address and nothing already
  published is ever overwritten.
- **Updates** — for each store, a **minimum** version, a **latest** version and
  the **store page**; and an optional "what is new" in both languages.
  - Below the *minimum*, the app shows a page asking to be updated and does
    nothing else.
  - Below the *latest*, it mentions the update over a dimmed app, with
    "later", and not again for a day.
  - Blank means no rule. Until there is an App Store page, leave iOS blank.

What is wrong is listed at the foot in red and **Publish** stays off until it is
fixed: a page with one language missing, a link a phone cannot open, a version
that is not a version, a minimum newer than the latest, a rule with no `https`
store page.

**Raising a minimum has to be typed.** It is the one edit that locks people out
of the app, and a slip of a digit — `10.0.0` for `1.0.0` — locks out everyone.
The tool says which minimum is being raised and to what, and Publish stays off
until that version is typed into **Confirm**. Lowering or clearing a minimum
only ever lets more people in, and needs nothing.

After publishing, the app picks the file up on its next launch (Pages can take a
minute to serve it). Started through `./run_admin.sh`, the tool also writes the
same JSON into this checkout's `assets/data/app.json` — **commit that file**, so
that a fresh install, offline, starts from the same words. (**Copy JSON** puts
it on the clipboard, for a tool started some other way.)

## A reciter from a file of links

The other way a reciter comes in. Some recitations are already cut, ayah by
ayah, and hosted by someone else — QUL (Quran.com's library) exports one as a
JSON file with an audio address per ayah. With the owner's agreement, the app
can stream and download straight from that host: nothing is cut here, nothing
but a portrait goes into the bucket, and the split flow above is untouched. The
button **Reciter from a file of links** at the top right opens it. It needs
`GITHUB_TOKEN` and `GITHUB_REPO`, like publishing the manifest.

1. **Choose file…** — the export. The tool reduces every address in it to one
   template (`https://host/…/{s3}{a3}.mp3`); a file whose addresses do not all
   fit one is refused, and the ones that broke the pattern are named. The
   ayahs listed for each surah are laid against `quran.db`: a surah with an
   ayah missing or one too many is shown in the table and **not offered**, and
   so is a surah the file does not have at all. Counts come from `quran.db`,
   never from the file.
2. **The reciter** — an id (lower-case, digits, underscores), the names in both
   languages, the riwayah, an attribution in both languages (shown under the
   name in the app: the library the audio is served through, or whoever asked
   to be credited), a version, the bitrate, and optionally a portrait,
   which goes to the bucket under a name made from its own bytes. An id already
   in the manifest as a linked reciter fills these in, for re-publishing after
   the host changed; an id that belongs to a reciter published *with packs* is
   refused, because a linked entry would take their packs away.
3. **Probe host** — asks the host for the first ayah of every complete surah,
   and for the `000` of every surah whose basmala is a file of its own. The
   second answer is written into the manifest as `hasBasmala`: the host was not
   built to our layout, and this is the only way the app can know not to ask
   for a basmala that is not there. One clip is fetched whole and timed with
   ffmpeg to measure the bitrate; type it if that fails. A surah the host does
   not have is not offered.
4. **Publish** — merges the entry into the manifest **as it is live** (the
   bucket's address is kept as it is) and commits it to the Pages site. The
   entry has no `packPath`: the app streams it as any other reciter, and
   downloads it one ayah at a time into the same place a pack would unzip to
   (CLAUDE.md A.5, *a reciter without packs*). Started through
   `./run_admin.sh`, the tool also writes the manifest into this checkout's
   `assets/data/manifest.json` — commit it.

What the app cannot check for such a reciter is said plainly: there is no
digest, so a downloaded file is only held to being a non-empty mp3; the quality
selector has nothing to choose from; and the audio stays on a host that is not
ours. If it moves, the fix is this screen again, not a release.

## What it cannot do

- **It does not judge the recitation**, only lengths: a clip can be the right
  length and still start a syllable late. The red rows tell you where to
  listen; your ear decides.
- **It never deletes from the bucket.** A wrong cut is replaced in place.
