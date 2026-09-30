# GLOBAL PROJECT CONTRACT

> This file is permanent project law. Any change to it is a product decision, not a
> refactor. It started as Part A of the Milestone 1 build prompt; it now records the
> app as it is — online and offline, every surah readable, audio from bundled assets,
> downloads or streaming.

## A.1 Product definition

A Quran memorization (hifz) app built around **talqeen-style spaced repetition of audio**:
the app plays one ayah N times, then the next ayah N times, then joins them and plays the
pair N times, and continues that pattern until the selected range is memorized.

- **Reading** works for all 114 surahs, fully offline, from the bundled `quran.db`, in the
  mushaf's own page layout — the whole mushaf cover to cover, or one surah or one juz of
  it at a time.
- **A session plays over the text being read.** There is no player screen: the reading
  view carries a bar with the session's controls, marks the ayah being recited, and
  follows it from page to page. A session may run from one surah on into the next.
- **Audio** works online and offline. A surah's recitation comes, in order of preference,
  from bundled assets, from a downloaded pack, or streamed from the CDN. A surah that no
  reciter has recorded yet is still fully readable; only memorization sessions need audio.
- Every later surah recording and every later reciter must be addable **without writing
  a single line of new Dart code** — assets, a manifest entry, or both.

## A.2 Non-negotiable rules

1. **Quranic text is never generated, and never altered.** Ayah text comes from
   `quran.db` and reaches the renderer **byte-for-byte**: no tatweel stripping, no mark
   reordering, no Unicode normalization form conversion, no whitespace "fixing", nothing.
   In this text a tatweel (U+0640) is often the carrier a hamza or small yeh sits on;
   removing it reattaches the mark to another letter, which is a change to the mushaf.
   Stripping or normalization exists **only** in test comparison helpers
   (`skeletonForComparison()` in `test/text_comparison.dart`) and is never called from a
   widget, repository, or loader. If text is missing or looks malformed, **STOP and
   report** — do not fill the gap. If marks render oddly, the answer is a font change,
   never a text change.
2. **No surah-specific or reciter-specific code.** No `if (surah == 1)`, no hardcoded ayah
   counts, no hardcoded reciter IDs, no switch on surah number anywhere. Surahs come from
   `quran.db`, reciters from `reciters.json` and the audio manifest; both are pure data.
3. **Network: public HTTPS GETs only.** The app may fetch the audio manifest, ayah audio
   and audio packs from the CDN; ayah audio from the host a manifest reciter's `audioPath`
   names in full (A.5, *a reciter without packs*); `app.json` from the same Pages site as
   the manifest, and the one portrait it may name; and nothing else. No backend, no
   accounts, no Firebase, no analytics, no crash reporting. `app.json` is the **only**
   remote config, and it is deliberately narrow: what the app says about itself, and which
   versions the stores are on (A.5). It is a static file anyone can read — nothing is
   sent, nothing identifies the install, and no behaviour of the app is switched by it
   beyond the update prompt. Every network failure degrades quietly to what is available
   offline — never an error dialog for a failed fetch. Knowing whether an *audio* file is
   local or remote lives in exactly one place: `AudioResolver`.
4. **Arabic-first, RTL-first.** Default locale is `ar`. `EdgeInsetsDirectional`
   everywhere — never raw `EdgeInsets` with left/right assumptions. Layout, icons,
   sliders, and progress indicators must be RTL-correct. The mushaf turns pages the way a
   printed mushaf does, whatever the UI locale.
5. **No new packages** beyond the approved list in A.4. If a requirement seems to need
   one, raise it as a numbered blocker instead of adding it.
6. **Audio is read-only.** Never trim, re-encode, normalize, or programmatically modify
   recitation audio files. `quran.db` ships read-only and is replaced wholesale when its
   schema version changes; download and progress state never go into it.
7. **Respectful presentation.** Ayah text is never truncated, ellipsized, marquee'd, or
   overlaid with promotional UI. No ads anywhere in the app.

## A.3 Architecture

Clean-architecture-lite, feature-scoped:

```
lib/
  main.dart          the app
  main_admin.dart    the macOS-only admin tool (see A.7)
  admin/             config, services, cubit, screen — reachable from
                     main_admin.dart and from nothing else
  core/
    theme/           AppColors, AppTextStyles, AppTheme
    router/          GoRouter config + route names
    di/              GetIt registrations
    localization/    locale keys (ar.json, en.json under assets/translations)
    constants/       AppConstants, AssetPaths
    extensions/
    widgets/         AyahText — the only widget allowed to render Quranic text;
                     SettingsCard, the session form, the Islamic frame
  data/
    models/          Surah, Ayah, Word, MushafLine, Reciter, MemorizationProgress, ...
    datasources/     QuranDatabase, QuranLocalDataSource, QuranPagesLocalDataSource,
                     ProgressLocalDataSource, SettingsLocalDataSource,
                     DownloadsDatabase, DownloadsLocalDataSource,
                     ReadingHistoryLocalDataSource
    repositories/    QuranRepository, QuranPagesRepository, ProgressRepository,
                     SettingsRepository, DownloadsRepository,
                     ReadingHistoryRepository
  domain/
    entities/        PlanStep, PlaybackUnit, SessionPlan, SessionConfig
    engine/          RepetitionPlanBuilder  (pure Dart, zero Flutter imports)
  features/
    surah_list/      cubit + screen + widgets   (the home: surahs | ajzaa tabs)
    home/            cubit + widgets            (ajzaa index, last place read)
    history/         screen                     (the last twenty places read)
    mushaf/          cubit + screen + widgets   (the reading view: the mushaf, or
                                                 one surah / one juz of it)
    session/         cubit + widgets            (the session set up and played over
                                                 the reading view: bar, settings sheet)
    progress/        cubit + screen + widgets
    settings/        cubit + screens            (settings in cards; session settings
                                                 and saved recitations as pages)
    about/           cubit + screens            (how to use, our goal, about us,
                                                 the developer)
    onboarding/      screen                     (the introduction, first launch)
    update/          cubit + widget             (the update prompt, over the whole app)
  services/
    audio/           AudioResolver, AudioStorage, ManifestService, ReciterCatalog,
                     AudioAvailability, AyahDurationService, AudioPackService,
                     PackFetcher, MemorizationPlayerService, SessionPreambles,
                     PlaybackQueue, SessionMediaControls
    AppInfoService   `app.json`: about, goal, developer, update rules — cached, refreshed
    AppVersionService, update_policy   the running version, and what to say about it
    LinkOpener       hands an address to the device — mail, browser, WhatsApp
```

- **State management:** `flutter_bloc`, Cubit-per-screen. No global god-cubit.
- **DI:** `GetIt` — `lazySingleton` for repositories, data sources and services; `factory`
  for cubits.
- **Routing:** `GoRouter`, typed args via `state.extra`.
- **Sizing:** `flutter_screenutil` (`.w / .h / .r / .sp`) for all dimensions. Mushaf pages
  compute their own font size to fit and are the one exception: at the default text size
  a printed line exactly fills the page's width. The reader's text-size setting is a
  multiple of that. Smaller, the printed lines are kept and set smaller. Larger, no
  printed line fits, so `reflowPage` re-breaks the page's lines at the bigger size and the
  page scrolls — **where the lines break changes and nothing else does**: the same `Word`
  objects, in the same order, on the same page, a word and its ayah marker never parted
  (A.2 rule 1 is about the bytes, and they are untouched). **On a desktop the design is
  the window** (`core/desktop.dart`): nothing is scaled, the mushaf page is held to a
  printed page's width, lists to a column, the keyboard turns pages and a mouse drags.
- **Colors:** `Theme.of(context)` / `AppColors` tokens only — no raw `Colors.*` literals.
- **Strings:** `easy_localization`, both `ar.json` and `en.json` populated with accurate
  Arabic. No hardcoded user-facing strings.
- **Errors:** repository methods return `Either<Failure, T>` (`dartz`).
- **Lock-screen controls** are `SessionMediaControls`, an `audio_service` handler that
  owns no audio: it mirrors `MemorizationPlayerService` outward (surah, reciter, ayah
  number, portrait) and passes play, pause and the step skips back in. It is started from
  `AppBootstrap`, not from dependency registration, which stays free of platform calls so
  tests can run it. It shows **names only, never ayah text** — a lock screen truncates what
  it is given, and A.2 rule 7 forbids that.
- **The repetition engine** (`domain/engine`, `domain/entities`) does not change for audio
  work; audio sources are looked up around it, never inside it. It addresses ayahs by
  surah *and* number (`AyahRef`), so a range may start in one surah and end in a later
  one: the joining is over the range, not over a surah, and a range only runs forward.
  The ayah counts it needs are handed in from the catalog, one per surah it touches.
- **The reading view is `MushafScreen`**, with an optional `SectionRequest` — one surah or
  one juz. A section is its pages with only its lines on them; where it starts and ends
  is asked of `quran.db` when it opens. A line a juz shares with its neighbour is shown
  whole, the neighbour's words drawn fainter. Twenty-one surahs are printed with their
  heading as the last line of the page *before* their first ayah; read on its own, such a
  surah opens on its first ayah with the heading carried over.
- **`SessionCubit` belongs to the reading screen** and knows nothing of pages: the screen
  tells it what the page suggests a session would cover, and listens for the ayah being
  recited. Settings changed under a running session are applied at once where that moves
  nothing (speed, pauses); anything that changes what is recited waits for the reader to
  say *start again* or *carry on from this ayah*.

## A.4 Approved package list

| Concern | Package | Note |
|---|---|---|
| State | `flutter_bloc` | |
| DI | `get_it` | |
| Routing | `go_router` | |
| Sizing | `flutter_screenutil` | |
| i18n | `easy_localization` | |
| Audio | `just_audio` | Assets, local files, and `LockCachingAudioSource` streaming |
| Audio on Windows | `just_audio_windows` | just_audio's Windows implementation; registers itself, imported by nothing |
| Media session | `audio_service` | Lock-screen and headset controls; on Android, the media-playback foreground service that keeps a long session alive. Owns no audio — see `SessionMediaControls`. Not started on Windows, which it does not support |
| Local storage | `hive_ce` + `hive_ce_flutter` | **Not** the original `hive` |
| Quran data | `sqflite` + `sqflite_common` | `sqflite_common` is sqflite's pure-Dart API, so loaders stay Flutter-free |
| Quran data on Windows | `sqflite_common_ffi` | sqflite has no Windows implementation; `AppBootstrap` installs this engine there. Also what tests run sqlite on |
| Paths | `path_provider`, `path` | |
| Network | `http` | Public GETs only (A.2 rule 3) |
| Version | `package_info_plus` | The running app's own version: the line at the foot of Settings, and what the update rules are compared with |
| Links | `url_launcher` | Opens the developer's email and profiles, and the store page, in another app. Not a network call of the app's own |
| Downloads | `background_downloader` | Per-surah packs |
| Packs | `archive`, `crypto` | Unzip; sha256 verification |
| FP types | `dartz` | |
| Value equality | `equatable` | |
| Build only | `flutter_launcher_icons`, `flutter_native_splash` | |

Nothing else without an explicit blocker.

## A.5 Data contracts

### `assets/data/quran.db` — the text and surah catalog

Read-only SQLite, built by `tool/build_quran_data.py` from the QUL sources in
`data/sources/`. Schema version in `meta.schema_version`, mirrored by
`AppConstants.quranDatabaseSchemaVersion`; bump both on any schema change.

```
surahs(id, name_ar, name_translit, ayah_count, revelation, start_page, basmala_mode)
ayahs (id, surah, ayah, text, page, juz, hizb, sajda, sajda_type, first_word_id, last_word_id)
words (id, surah, ayah, position, text, is_marker, page, line)
lines (page, line, line_type, is_centered, surah_number, first_word_id, last_word_id)
meta  (key, value)
```

- `basmala_mode` ∈ `first_ayah` (Al-Fatiha: the basmala **is** ayah 1) | `separate` (the
  basmala precedes ayah 1 and is not part of it) | `none` (At-Tawba).
- `line_type` ∈ `surah_name` | `basmallah` | `ayah`. A line's words are the ids
  `first_word_id..last_word_id`, in id order. `is_marker = 1` words are ayah-number
  glyphs: drawn, never part of ayah text, never tappable.
- `name_translit` is the English label. There is no English translation field.
- There is no `surahs.json`. The surah list is all 114 rows of `surahs`, ordered by id,
  and knows nothing about audio.

### `assets/data/reciters.json` — bundled reciters

```json
[
  {
    "id": "ahmed_khalil_shaheen",
    "nameAr": "أحمد خليل شاهين",
    "nameEn": "Ahmed Khalil Shaheen",
    "audioMode": "per_ayah_files",
    "basePath": "assets/audio/ahmed_khalil_shaheen",
    "bundled": true,
    "availableSurahs": [1, 58, 112, 113, 114],
    "hasIstiadhah": true,
    "hasBismillah": true,
    "imagePath": "assets/images/reciters/ahmed_khalil_shaheen.jpeg"
  }
]
```

`audioMode` ∈ `per_ayah_files` | `single_file_with_timings`; both stay implemented.

### Audio manifest — remote reciters

Fetched from `kManifestUrl` —
`https://ahmedelsersi.github.io/iqra-cdn/manifest.json`, overridable with
`--dart-define=MANIFEST_URL=…` — cached to disk, falling back to the disk cache and then to
the bundled `assets/data/manifest.json`, which is kept a copy of the published file.

The manifest lives on a GitHub Pages site holding nothing else; the audio itself lives
wherever the manifest's own `baseUrl` points (today an R2 public bucket). That indirection
is the point: the bucket can move without an app update. A `baseUrl` with no trailing slash
is resolved as though it had one.

Both the manifest and the packs are built by `tool/build_manifest.py` from a tree of ayah
files — it reads ayah counts and basmala modes out of `quran.db`, so a hand-written
manifest is never the source of those numbers. Packs are deterministic: rebuilding an
unchanged surah produces the same bytes and the same digest.

```json
{ "schemaVersion": 1, "baseUrl": "https://…", "mirrors": [],
  "reciters": [ { "id", "nameAr", "nameEn", "riwayah", "bitrate", "version",
                  "audioPath", "packPath", "imagePath?", "totalBytes",
                  "attribution?": { "ar", "en" },
                  "surahs": [ { "n", "ayahs", "bytes", "sha256",
                                "hasBasmala?",
                                "qualities?": { "128": { "bytes", "sha256" } }
                              } ] } ] }
```

**A reciter is added here, not in a release.** `ReciterCatalog` merges the manifest's
reciters into `reciters.json` on every launch, and `imagePath` — `images/<id>.jpg`,
resolved against `baseUrl` — is their portrait. `ReciterImageCache` fetches it once and
keeps it beside the audio, so it survives offline; a reciter with no portrait shows their
initial rather than a hole. `reciters.json` is now only for reciters whose *preambles*
ship, and no portrait ships at all.

`audioPath` is a template: `audio/{id}/{bitrate}/{s3}{a3}.mp3`, with surah and ayah
zero-padded to 3 digits. It may also be a full `https://` address with the same
placeholders, for a reciter served from a host of their own — the app resolves it as it
resolves any path, and an absolute one resolves to itself.

**The basmala of a `separate` surah is its own file inside that surah, ayah `000`** —
`audio/shaheen/64/002000.mp3` — and is played once before ayah 1 when a session starts at
ayah 1. A session that picks a surah up part-way opens with no
basmala. A session that runs on into a later surah plays that surah's basmala once, ahead
of the first time its ayah 1 is heard — a preamble in the queue, never a unit, so it is not
drilled, joined or counted.

`hasBasmala` is optional and has three states. `false` means the surah has no `000` file
and none is ever requested — the only way to skip a *streamed* basmala silently, since a
remote file's absence cannot be discovered without playing it. The surah is still opened
with the basmala, **borrowed** from the reciter's own recording of the ayah that *is* the
basmala — ayah 1 of the surah whose `basmala_mode` is `first_ayah`, which the catalog
names and `ReciterCatalog` hands to the reciter as `basmalaAyahSurah` — whenever the
reciter has that surah. Same words, same voice; a preamble, never a unit. A download of
such a surah fetches that ayah alongside, into its own surah's place, so it opens offline
too. `true` means the file is
there, and a pack missing it is refused as incomplete. Absent means the manifest does not
say, and the layout above is assumed. A missing *local* basmala is always skipped silently,
never a failure.

`bitrate` is the reciter's own, and `qualities` is optional: a surah published at more
than one bitrate carries one entry per extra bitrate, each with its own size and digest,
because a different encode is a different file. The app's audio-quality selector
(32/64/128) asks for one of those; a reciter who does not publish it is served at theirs,
and a surah already on the device plays from disk whatever the selector now says.

`bytes` is the size of the pack zip, and it is checked **before** the digest and before
anything is unzipped: a truncated download is the common failure and length is the cheap
way to catch it.

**A reciter without packs.** An entry with no `packPath` is a reciter whose audio is
served ayah by ayah from a host that builds no zips — one added from a file of links,
the way the admin tool adds a reciter whose recordings someone else already cut and
hosts. Their surahs stream exactly as any other's. A *download* of one is one request
per ayah, straight into the directory a pack would have unzipped to, so the resolver,
delete and the stale check never know the difference. There is no `bytes` or `sha256`
to check, so each file is held to the cheap truth a pack's entries are held to — not
empty, and an mp3 by its first bytes — and a file that fails it is deleted and counted
missing; what did arrive stays and plays from disk, the rest streams, and the surah is
recorded only when every ayah is there. Such an entry **states `hasBasmala`** for every
`separate` surah: the host was not built to the layout above, and the manifest is the
only thing that can say whether a `000` exists there. It is written by the admin tool
from the file of links, never by hand. `attribution` is where such a reciter credits the
library the audio is served through: shown under the reciter's name wherever it is
listed, in the reader's language, and empty for a reciter with nothing to credit.

A manifest reciter whose id matches a bundled reciter extends it: bundled surahs play from
assets, the rest from the manifest.

### Audio asset layout

**No surah audio ships.** Every surah of every reciter comes from the CDN —
streamed, or downloaded as a pack. What stays in the bundle is 137 KB of
reciter-level preambles, so a session can open with the isti'adhah and the
basmala before a byte is fetched:

```
assets/audio/<reciter_id>/bismillah.mp3     (reciter-level)
assets/audio/<reciter_id>/istiadhah.mp3
```

A bundled reciter is therefore one with `availableSurahs: []`: it ships its
preambles and its portrait, and the manifest supplies its recitation. The
layouts below remain implemented, because a future build may ship a surah
again — a starter surah, or a reciter whose licence forbids a CDN:

```
assets/audio/<reciter_id>/<surah3>/<ayah3>.mp3      per_ayah_files
assets/audio/<reciter_id>/<surah3>.mp3              single_file_with_timings
assets/data/timings/<reciter_id>/<surah3>.json
```

`test/assets_integrity_test.dart` fails if surah audio or a timings directory
reappears in the bundle without that being a decision someone made: 11 MB of
clips is what this weighed before, and it is the difference between a 25 MB
install and a 36 MB one.

Downloaded packs unzip to the application support directory at
`audio/<reciter_id>/<bitrate>/<surah3><ayah3>.mp3`, basmala as ayah `000`. Application
support, never Caches: iOS may purge Caches mid-session, which would take a surah out from
under a running session. On iOS the audio directory carries the do-not-back-up flag —
Apple rejects apps that back re-downloadable content up to iCloud.

A pack holds one file per ayah, plus `<surah3>000.mp3` where the surah's `basmala_mode` is
`separate`. A file count that disagrees with `ayah_count` is **logged, not refused**: the
manifest's sha256 has already verified these are the published bytes, and what is missing
simply streams.

### `downloads.db` — what is on the device

The app's own writable SQLite file, in the application support directory beside the audio:

```
downloads(reciter_id, surah, bitrate, version, state, bytes, ayahs, updated_at)
```

`state` ∈ `complete` | `stale` | `failed`. Never `quran.db`, which ships read-only and is
replaced wholesale on a schema bump (A.2 rule 6). `bitrate` is not optional bookkeeping: a
pack lives under `audio/<id>/<bitrate>/` and the quality selected now is not necessarily
the one a surah was fetched at. A reciter whose manifest `version` has moved on has its
rows marked `stale` — the audio keeps playing, a superseded take beats silence, and the
settings screen offers a re-download of that reciter alone.

The files remain the truth: `AudioResolver` asks the filesystem on every lookup, so
deleting a surah falls back to streaming with no restart.

### `app.json` — what the app says about itself, and which versions are welcome

Fetched from `kAppInfoUrl` — `https://ahmedelsersi.github.io/iqra-cdn/app.json`, beside
the manifest, overridable with `--dart-define=APP_INFO_URL=…` — and handled exactly as the
manifest is: answered at once from the copy cached on the device, or from the bundled
`assets/data/app.json` when there is none, and refreshed in the background. A fetched file
that says nothing — not JSON, not an object, an empty object — is **not taken up**: a
hosting error page must not be able to blank a screen or lift an update rule.

```json
{ "schemaVersion": 1,
  "about": { "ar", "en" }, "goal": { "ar", "en" },
  "developer": { "name": { "ar", "en" }, "photo", "email",
                 "github", "linkedin", "whatsapp", "facebook" },
  "update": { "android": { "min", "minBuild?", "latest", "latestBuild?", "force", "storeUrl" },
              "ios":     { "min", "minBuild?", "latest", "latestBuild?", "force", "storeUrl" },
              "notes":   { "ar", "en" }, "remindAfterDays" },
  "maintenance": { "enabled", "title": { "ar", "en" }, "message": { "ar", "en" },
                   "platforms": [], "until" } }
```

About us, Our goal and the developer's card are read from here through
`AppInfoService`, so their words can change without a release. It is read
**forgivingly**: a field that is missing or of the wrong type reads as empty, a link left
blank is simply not shown, and nothing written in this file can take a screen down. Links
are typed by hand, so they are read the way people type them — an email without `mailto:`,
a WhatsApp number with spaces and a plus, a profile without `https://`. `photo` is an
address, or a path relative to the file itself.

**The update rules are per store, and a release is a version and a build.** `min` and
`latest` are versions as the store writes them; `minBuild` and `latestBuild` are optional
and only tell two uploads of one version apart — versions decide first, and a build decides
only when the versions are equal and both sides name one. Below the minimum the app shows a
page asking to be updated and nothing else; below the latest it mentions the update over a
dimmed app, with "later", and not again for `remindAfterDays` (one, unless said). `force`
makes the latest mandatory: below it is treated as below the minimum, with no "later" — the
switch for a release that cannot wait, without moving the minimum. The wording is fixed and
localized; `notes` adds an optional word on what is new. `decideUpdate` resolves **every
doubt towards saying nothing**, because the other direction locks people out: a rule with no
`storeUrl` is ignored, a version that cannot be read — on either side — is no rule at all
whatever build it names, and a build *ahead* of the store (a tester's, a reviewer's) is
left alone. A required update cannot be put off; an optional one that was put off stays
away for the rest of the run, unless a required one arrives.

**`maintenance` is the closed sign.** While `enabled`, the app shows `title` and `message`
(or its own wording where they are blank) with a *try again* button, and nothing else —
ahead of any update prompt. `platforms` narrows it to `android` and/or `ios`; empty means
every platform, desktop builds included. `until`, when given, takes the sign down by itself
at that time and is shown as when to expect the app back, so a switch nobody remembered
cannot keep people out for good. *Try again* re-fetches `app.json`, so a sign taken down is
gone without a restart. Putting the sign up, like raising a minimum or forcing a release, is
confirmed by typing in the admin tool.

**How to use and the introduction are not in this file.** They describe this build's own
screens and gestures, so they live in the translations and change in the same commit as
the screens they describe.

**The settings are one map with several writers** — the settings screen, a session saving
its values as defaults, the update prompt noting when it last spoke, the reader marking
where they stopped (the *reading mark*: one ayah, set from the ayah's own menu, tinted on
the page in the bookmark's colour, and a tall translucent ribbon hung down the opening edge of
its page — the one thing drawn over the page, by the reader's leave: a setting hides it. On the home page it *is* "continue reading" while it is
set — `lastPlace`: the mark wins over the history the app keeps by itself, and without one
the card is the first ayah of the last page read, as before). `SettingsRepository`
broadcasts every save and `SettingsCubit` takes it up, and a writer that is not the
settings cubit reads the stored map afresh before changing its one field. Without both, the
next save writes a stale copy over what the others changed.

### `assets/audio/silence_400ms.wav`
A single short silent clip, used as a gap spacer inside the playback queue.

## A.6 `AudioResolver`

The one place that knows where audio lives and whether we are online. No other file
in `lib/` constructs an `AudioSource`.

Resolution is bound to a reciter and a surah first, because the asynchronous facts —
the storage root, the manifest, a timings file — have to be settled before a queue is
built. Everything after that is synchronous, so a queue of hundreds of entries does
not await once per ayah:

```
Future<SurahAudio>  forSurah({ reciter, surah })      // AudioResolver

AudioSource         sourceFor(int ayah)               // SurahAudio
AudioSource?        basmala()
AudioSource?        istiadhah()
AudioSource         spacer()
bool                isLocal(int ayah)
```

`sourceFor` answers in order: a bundled asset (`per_ayah_files` →
`AudioSource.asset`, `single_file_with_timings` → `ClippingAudioSource`) → a
downloaded local file (`AudioSource.file`) → the CDN (`LockCachingAudioSource`,
cached to the very path a pack download would have written, so an ayah streamed once
plays from disk after). Nothing resolvable at all is a `SessionConfigException`, never
queued silence. The player layer never knows which arm answered. Adding a reciter =
assets plus one `reciters.json` object, or one manifest entry.

`audioMode` describes a reciter's **bundled** layout only: manifest audio is per-ayah
files whatever mode their bundled surahs use.

`basmala` covers three sources of the same words — a bundled reciter's single
`bismillah.mp3`, which serves every surah; a manifest surah's own ayah `000`; or, where the
manifest says there is no `000`, the reciter's recording of the ayah that is the basmala
(A.5).
Whether a session *plays* it stays `SessionPreambles`' decision, keyed on the surah's
`bismillahMode`. `istiadhah` and `spacer` are bundled-only: neither belongs to a
surah, and a gap is never worth a request.

`isLocal` is for callers that would have to *load* a clip rather than play it — the
session summary's duration probe. A surah that would have to be streamed is left
unmeasured and the summary shows no duration; it is never filled in with a guess.

## A.7 The admin tool — macOS only

`lib/main_admin.dart` splits a whole-surah recording into ayahs, shows each segment
beside its text, and publishes the result to R2. It is a workbench, not a product.

**It can never reach a phone.** `lib/main.dart` imports nothing under `lib/admin/`, and
the rule is enforced by walking the real import graph in
`test/admin/admin_isolation_test.dart`, not by trusting the directory layout. The macOS
target exists only to host this tool; its entitlements say so.

**Credentials** come from `--dart-define` — `R2_ACCOUNT_ID`, `R2_ACCESS_KEY`,
`R2_SECRET_KEY`, `R2_BUCKET`, `R2_ENDPOINT`, `R2_PUBLIC_BASE`, `AUDIO_BITRATE` — passed by
`./run_admin.sh`, which sources the gitignored `admin.env`. **No key has a fallback
anywhere in code**, and a build missing one refuses to start, naming what is absent. A
literal that looks like a secret in `lib/` fails a test.

**The R2 token is read/write, never delete, and `R2Client` has no delete method** — its
absence is asserted. A published path is never overwritten *by accident*: the tool refuses
a key that already exists unless the operator asks for it (`Replace existing` on the
screen, `--replace` on the command line).

**A cut that turns out wrong is fixed by replacing the surah in place and bumping the
reciter's `version`.** A surah's clips always carry the same names — `{SSS}000` to
`{SSS}{NNN}`, plus the pack — so writing over them replaces the surah whole: one copy,
nothing orphaned, nothing deleted. The `version` bump is what marks existing installs
stale, so a phone holding the old cut downloads the new one. Publishing under a second,
versioned path was considered and turned down: it doubles the storage and leaves two
copies of a surah to keep straight. Replacement uploads come from audited files
(`--publish-from`), never from a fresh cut nobody has measured.

**The recording is chosen through the system file panel** — an `NSOpenPanel` behind the
`mirqat/admin_files` channel in `macos/Runner/MainFlutterWindow.swift`, not `file_picker`,
which is not on the approved list (A.4). Cancelling keeps the current choice; choosing a
different file, or a different surah, drops the split made from the last one, because
segments cut from one recording must never be published under another's numbers.

**ffmpeg is the system binary**, over `Process.run` (`ffmpeg_kit_flutter` was archived in
2026). A missing binary stops the tool at launch with `brew install ffmpeg`, in the script
and again in the app.

**Every Quranic fact comes from `QuranRepository`** — the surah dropdown, the ayah text
beside each segment, and `basmala_mode`, which decides both how many segments to expect and
what segment 0 is:

| `basmala_mode` | segments        | segment 0 is                     |
|----------------|-----------------|----------------------------------|
| `separate`     | `ayah_count + 1`| the basmala, exported `{SSS}000` |
| `first_ayah`   | `ayah_count`    | ayah 1, with the basmala inside  |
| `none`         | `ayah_count`    | ayah 1, no basmala               |

A.2 rule 1 applies here too: the text shown beside a segment is `quran.db`'s bytes,
untouched.

That table is what the *surah* calls for. What a particular *recording* holds is the
operator's to say, with two checkboxes beside the surah:

- **Audio has basmala** (on by default, and only meaningful for a `separate` surah).
  Off, for a recording that starts straight at ayah 1: no basmala segment is expected, no
  `{SSS}000` is exported, and the manifest says `hasBasmala: false` so the app never asks
  the CDN for a file nobody made.
- **Audio has isti'adhah** (off by default). On, one more leading segment is expected. It
  is cut so that it stays out of the basmala, and it is **never published** — it belongs
  to no surah.

**One service cuts, for the screen and the command line alike**: `SurahSplitter`. Pauses
are candidates, chosen for *coverage* (no stretch of the recording left without one) rather
than for their number; the text chooses among them by the length each segment should be —
weighted by `recitationWeight`, which reads letter names (the muqatta'at) and held vowels
off the text itself, with no list of surahs anywhere (A.2 rule 2). A split with the right
count is still checked clip by clip, and the screen marks the rows whose length their text
cannot explain.

**A cut can be fixed by ear.** Each row plays its segment straight from the recording
(`SegmentPreview`, over `just_audio`'s `setFilePath`/`setClip` — no `AudioSource` is built
outside `AudioResolver`, A.6), and its start and end can be typed or nudged. By default
boundaries are shared: moving the end of one segment moves the start of the next, so a hand
edit never leaves a gap or an overlap. Unticking the box under a field moves that edge
alone and **cuts out** what is left between the two segments — for a cough, a repeated
phrase, an isti'adhah — and the screen says how many seconds are going into no clip. A gap
is allowed; an overlap never is. This is the one edit that needs no pause to land on, which is
what a reciter running one ayah into the next calls for.

**`tool/audit_audio.py` is the definition of clean** — every ayah present, nothing extra,
no clip under 45% or over 2.2x of what its words call for. It reads published packs
(`--live`) or exported clips (`--dir`), using the same arithmetic as the admin tool. A
re-cut is exported with `--export-only`, audited, and uploaded from those very files with
`--publish-from`, so what was measured is what goes live. Where every surah stands is kept
in `docs/AUDIO_STATUS_<reciter>.md`.

**It also edits `app.json`** (A.5) — About us, Our goal, the developer's card and the
update rules — and commits it to the Pages site beside the manifest, through the same
`PagesPublisher`. It starts from what is live, refuses a draft `validateAppInfo` finds
fault with, and uploads the developer's photo to the bucket under a name made from its own
bytes, so the no-overwrite rule is kept without an exception. **Raising a minimum version
is confirmed by typing that version**, for the same reason a short split is explained in
words: it is the one edit that locks people out of the app, and a checkbox would not stop a
slip of a digit.

**It also adds a reciter from a file of links** (A.5, *a reciter without packs*): a QUL
export of a recitation someone else cut and hosts is reduced to one `audioPath`
template — a file whose addresses do not all fit one is refused, naming them — laid
against `quran.db` for completeness, and the host is asked for each complete surah's first
ayah and for each `separate` surah's `000`, which is what the entry's `hasBasmala` says.
Nothing is cut and nothing but a portrait is uploaded; the entry is merged into the live
manifest and published the same way as the rest. `LinkedReciterCubit` and `LinkFile`.

**A split whose count does not match is never published silently.** The operator either
fixes the split or types a reason, which is recorded in the log beside the upload. A
checkbox would not do: a surah published one segment short files every later ayah under the
wrong number, and the app would teach that by repetition.
