# Play Store listing & submission

Everything a release needs from the Play Console side, written so a future
release can be filled in straight from this file. Judgement calls the app's
owner should confirm before submitting are marked **verify**.

## Facts

| Field | Value |
|---|---|
| Package name (applicationId) | `com.mirqat.app` |
| Store listing name | اقرأ وارتق (all listing languages — the launcher wordmark, not translated; see `README.md`) |
| Category | Education **(verify — could also fit Books & Reference; Education was chosen for the structured, session-based memorization flow)** |
| Default language | Arabic (ar) |
| Listing languages | Arabic (ar, default), English (en) — matches `assets/translations/` |
| Free or paid | Free |
| In-app purchases | None |
| Ads | None |
| Landing page | <https://ahmedelsersi.github.io/iqra-wartaq/> — separate public repo ([AhmedElsersi/iqra-wartaq](https://github.com/AhmedElsersi/iqra-wartaq)), deployed via GitHub Pages/Actions so this app's own source stays out of it |
| Privacy policy URL | <https://ahmedelsersi.github.io/iqra-wartaq/privacy.html> |
| Account-deletion URL | Not applicable — the app has no accounts (see Data safety) |

## Store listing copy

Written from what the app actually does (`lib/features/*`, `assets/data/*`,
`assets/translations/*.json`), not placeholders.

### Arabic (default)

**App name** (≤30 chars, actual: 10)
> اقرأ وارتق

**Short description** (≤80 chars, actual: ~61)
> حفظ القرآن الكريم بالتكرار الصوتي بطريقة التلقين — بلا إنترنت

**Full description** (≤4000 chars, actual: well under)
```
اقرأ وارتق — سمت الحافظين

تطبيق لحفظ القرآن الكريم يعمل بالكامل دون إنترنت، مبني على طريقة "التلقين"
الصوتي في الحفظ: تُكرَّر الآية الأولى عددًا من المرات، ثم تُكرَّر الآية
التالية بنفس العدد، ثم توصَل الآيتان معًا وتُكرَّران، وهكذا يتوسّع النطاق
آية بعد آية حتى يكتمل حفظ المقطع المطلوب.

يضم التطبيق حاليًا سورة الفاتحة، والمجادلة، والإخلاص، والفلق، والناس، بصوت
القارئ أحمد خليل شاهين، مع الاستعاذة والبسملة، وكل الملفات الصوتية محمّلة
داخل التطبيق فلا حاجة لأي اتصال بالشبكة.

كل جلسة قابلة للتخصيص:
• نطاق الآيات المراد حفظها
• عدد التكرارات لكل خطوة
• طريقة الوصل بين الآيات: تراكمي، متصل، أو بلا وصل — لتدريب كل آية بمفردها
• تمرير كامل للنطاق في نهاية الجلسة
• الاستعاذة قبل البدء
• الفواصل الزمنية بين الآيات والتكرارات والخطوات
• سرعة التلاوة

يتابع التطبيق تقدّمك آية بآية: لم تبدأ، قيد الحفظ، أو محفوظة، مع عدد مرات
التكرار التراكمي لكل آية — كل ذلك محفوظ على جهازك فقط.

الإعدادات: اختيار القارئ، المظهر (تلقائي / فاتح / داكن)، حجم الخط العربي،
اللغة، طريقة عرض السور، وإعدادات افتراضية للجلسات الجديدة.

لا إعلانات، لا حسابات، لا اتصال بالإنترنت على الإطلاق.
```

### English

**App name** (≤30 chars, actual: 11)
> Iqra Wartaq

**Short description** (≤80 chars, actual: 73)
> Offline Quran memorization through talqeen-style spaced audio repetition.

**Full description** (≤4000 chars, actual: well under)
```
Iqra Wartaq — The Path of Those Who Memorize

A fully offline Quran memorization (hifz) app built around talqeen-style
spaced repetition of audio: the app plays one ayah a set number of times,
then the next ayah the same number of times, then joins the two and plays
the pair, and continues that pattern outward until the whole selected range
is memorized.

Currently includes Surat Al-Fatiha, Al-Mujadilah, Al-Ikhlas, Al-Falaq, and
An-Nas, recited by Ahmed Khalil Shaheen with isti'adhah and bismillah, all
bundled inside the app — no network connection is ever needed.

Every session is configurable:
• The ayah range to memorize
• How many times each step repeats
• Connect mode: cumulative, continuous, or none (drill each ayah alone)
• An optional full pass over the whole range at the end
• Isti'adhah before starting
• Gaps between ayahs, repetitions, and steps
• Playback speed

Progress is tracked per ayah — not started, in progress, or memorized — with
a running repetition count, saved only on your device.

Settings cover reciter choice, theme (system/light/dark), Arabic font size,
language, how surahs are displayed, and defaults for new sessions.

No ads, no accounts, no internet connection required — ever.
```

## Data safety

**Declaration: No data collected.**

"Collected" in Play's Data Safety form means user data is transmitted off
the device. This app never does that — there is no backend, no analytics
SDK, no crash reporter, and the release build carries no `INTERNET`
permission (CLAUDE.md A.2.3: offline only; confirmed by grep — zero network
calls anywhere in `lib/`). Everything the app writes is two local Hive
boxes (`memorization_progress`, `settings` — see
`lib/core/constants/app_constants.dart`), which never leave the device.

If a later milestone adds a real backend (e.g. Firestore for cross-device
sync), the framing changes: data sent to your own backend that only acts as
a processor on your behalf is **collected**, not automatically **shared**
(shared means handed to a separate company for its own purposes, like an ad
network or analytics vendor). Re-run this section from scratch at that
point — don't just relabel "collected" as "shared."

| Data type | What it is in this app | Purpose | Declare? |
|---|---|---|---|
| App activity → App interactions | Which surah/ayah range a session covers, repetition counts, mark-as-memorized status | App functionality | **No** — stored locally only, never transmitted |
| App info and performance | None | — | No |
| Personal info | None — no accounts, no name/email/phone collected anywhere | — | No |
| Financial info | None — no IAP, no payments | — | No |
| Location | None — no location permission requested | — | No |
| Photos or videos | None — the app ships its own bundled audio/images; it never reads user media | — | No |
| Audio files | None collected — bundled recitation audio ships with the app, it is not user data | — | No |
| Files and docs | None | — | No |
| Device or other IDs | None — no ad ID, no analytics ID, no device fingerprinting | — | No |
| Web browsing | None | — | No |

**Encryption in transit:** not applicable — there is no transit; the app
makes zero network requests.

**Data deletion:** not applicable in the "request deletion" sense — there is
no account and no server-side copy. Uninstalling the app deletes both local
Hive boxes immediately. **(verify:** if you'd rather offer an in-app "clear
my progress" action for Milestone 2, that's a product decision, not a Play
requirement — the app is compliant without it.)

## App content

- **Content rating:** Everyone / no mature content — no violence, sexual
  content, profanity, drugs, gambling, or user-generated content anywhere in
  the app. The only content is Quranic text and recitation audio.
  **(verify** the exact rating-questionnaire answers in Play Console; the
  questionnaire is scored by Google's rating bodies (IARC), not filled from
  this file directly.)
- **Target age group: verify.** This isn't built as a children's app and
  isn't in the Designed for Families program; if that's the intent, say so
  and I'll adjust the manifest/store answers — enrolling has real
  requirements (ad SDK restrictions, a different content policy) beyond
  what's built here.
- **App access:** the app requires no sign-in. Every screen — surah list,
  reader, player, progress, settings — is reachable with no credentials and
  no gating of any kind. Declare **"All functionality is available without
  special access."** This is worth stating explicitly because a login wall
  with no reviewer credentials supplied is the single most common reason a
  first Play submission gets rejected — it doesn't apply to this app today,
  but keep this section in mind if a login/sync feature is ever added later.

## Release process

### 1. Generate the upload key (once, locally)

```
tool/make_upload_key.sh
```

Refuses to run if `android/app/upload-keystore.jks` already exists. Prompts
for the certificate `-dname` (CN/OU/O/L/C) and a password (min 6 chars,
never passed as a CLI arg or left in shell history). Back up both the
resulting `.jks` file and its password somewhere durable and outside this
repo — losing either makes it impossible to ship another update to
`com.mirqat.app` through this upload key.

### 2. Repository secrets `release.yml` reads

Set each with `gh secret set NAME` and no `--body` flag, so `gh` prompts you
interactively for the value — this keeps the secret out of your shell
history entirely. Don't add a trailing `#` comment on these lines either:
interactive zsh doesn't set `interactive_comments`, so `gh` sees the `#...`
as a second argument and fails with `accepts at most 1 arg(s)`.

```
gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
gh secret set PLAY_SERVICE_ACCOUNT_JSON
```

`ANDROID_KEYSTORE_BASE64` is the keystore file itself, base64-encoded:

```
base64 -i android/app/upload-keystore.jks | pbcopy
```
then paste the copied text at the `gh secret set` prompt.

`GOOGLE_SERVICES_JSON` (also base64-encoded) is optional and only needed if
a later milestone adds Firebase — Milestone 1 has none, so skip it for now.

### 3. Where the Play service-account JSON actually comes from

Not from Play Console directly:

1. **Google Cloud Console** (the project backing your Play Console account)
   → enable the **Google Play Android Developer API**.
2. **IAM & Admin → Service Accounts → Create Service Account.**
3. Open it → **Keys → Add key → Create new key → JSON.** This file is what
   goes into `PLAY_SERVICE_ACCOUNT_JSON`.
4. Back in **Play Console → Users and permissions**, invite that service
   account's email and grant it access to this app, ticking **Release to
   production, exclude devices, and use Play App Signing**. (The old
   "Release manager" permission preset no longer exists — you tick the
   individual permissions.)

### 4. The first upload must be done by hand

A service account can neither create a new app listing nor accept Play's
Developer Distribution Agreement — both require a human in the Console. So
for a package that doesn't exist on Play yet, `release.yml`'s upload step
has nothing to attach to and will fail. Sequence for the very first release:

1. Build locally with the real upload key:
   ```
   flutter build appbundle --release
   ```
2. Create the app in Play Console by hand, fill in the listing from this
   file, and upload that `.aab` to the **production** track yourself.
3. Enroll in **Play App Signing** when prompted (Play then re-signs your
   upload with its own key for distribution — your upload key only needs to
   keep proving it's you).

Every release after that is just:
```
git tag v1.0.1 && git push origin v1.0.1
```
which triggers `.github/workflows/release.yml`.

### 5. Versioning

`versionCode` is the `+N` half of `pubspec.yaml`'s `version:` line. Play
rejects a `versionCode` it has already seen for this package — including on
a re-upload after a rejection — so it can never be reused or rolled back.
`.github/workflows/bump-build-number.yml` increments it on every push to
`main`, which is what keeps `main` always ahead of whatever was last
uploaded; `tool/bump_build_number.sh` is the script it runs.

## Screenshots

Not generated — see `store/README.md` for exactly which five screens to
capture and why.
