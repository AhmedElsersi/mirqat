# App Store Connect — listing for اقرأ وارتق (Iqra Wartaq)

Everything App Store Connect asks for, ready to paste. Written from what the
app does today (`lib/`, `assets/translations/`, `assets/data/app.json`), not
from the Play listing, which predates streaming and the mushaf.
`tool/check_store_listing.py` checks every length limit below; run it after
any edit. Items only the account holder can answer are marked **verify**.

## Facts

| Field | Value |
|---|---|
| Bundle ID | `com.mirqat.app` |
| SKU | `mirqat-ios-1` (any unique string; never shown) |
| Primary language | Arabic |
| Localizations | Arabic (`ar-SA`), English (`en-US`) — listing text only; the app itself is in Arabic |
| Primary category | Education |
| Secondary category | Reference |
| Price | Free — no in-app purchases, no ads |
| Availability | All countries and regions **except China mainland** — Chinese law requires a permit for religious content, and we hold none |
| Devices | iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`) |
| Copyright | © 2026 Ahmed Elsersi |
| Support URL | <https://ahmedelsersi.github.io/iqra-wartaq/> |
| Marketing URL | <https://ahmedelsersi.github.io/iqra-wartaq/> |
| Privacy Policy URL | <https://ahmedelsersi.github.io/iqra-wartaq/privacy.html> — corrected and republished 2026-09-20; `PRIVACY_POLICY.md` is its source text |

## Arabic (`ar-SA`) — primary

<!-- field: name ar 30 -->
**Name** (≤ 30)
```
اقرأ وارتق
```

<!-- field: subtitle ar 30 -->
**Subtitle** (≤ 30)
```
حفظ القرآن بالتلقين والتكرار
```

<!-- field: promo ar 170 -->
**Promotional text** (≤ 170 — can be changed without a new build)
```
احفظ القرآن كما يُلقَّن في الحلقات: تسمع الآية وتكرّرها، ثم التي تليها، ثم تصلهما معًا. المصحف كاملًا للقراءة دون إنترنت، بلا إعلانات وبلا حسابات.
```

<!-- field: keywords ar 100 -->
**Keywords** (≤ 100, comma-separated, no spaces after commas)
```
قرآن,حفظ,تحفيظ,مصحف,تلقين,تكرار,تلاوة,حافظ,مراجعة,جزء,سورة,تجويد,ختمة,ورد,حلقة
```

<!-- field: description ar 4000 -->
**Description** (≤ 4000)
```
اقرأ وارتق — سمت الحافظين

تطبيق لحفظ القرآن الكريم بطريقة التلقين المعروفة في حِلَق التحفيظ: تسمع الآية وتكرّرها، ثم الآية التي تليها، ثم تصلهما معًا — درجةً درجة، حتى يثبت المقطع كله.

المصحف بين يديك
• المصحف كاملًا بصفحاته المعروفة، ٦٠٤ صفحات، للقراءة دون إنترنت.
• اقرأ المصحف متصلًا، أو سورةً سورة، أو جزءًا جزءًا.
• يتذكّر التطبيق آخر صفحة قرأتها ويعيدك إليها، ويحتفظ بسجل لآخر المواضع.
• حجم الخط قابل للتكبير، وللصفحة مظهر فاتح وآخر داكن.

الجلسة فوق النص
• لا شاشة منفصلة للتشغيل: اضغط على الصفحة فتظهر أدوات الجلسة، وتُظلَّل الآية التي تُتلى وتتبعها الصفحة.
• اضغط مطولًا على آية لتبدأ منها، أو لتحفظها وحدها، أو لتجعلها بداية النطاق أو نهايته.
• يمكن أن يبدأ النطاق في سورة وينتهي في سورة لاحقة.

كل جلسة كما تريدها
• عدد التكرارات لكل خطوة.
• طريقة الوصل: تراكمي (آية، ثم آيتان، ثم ثلاث…)، أو متصل (المقطع كاملًا ثم يُعاد)، أو بدون وصل.
• مراجعة كاملة للنطاق في نهاية الجلسة.
• الوقفات بين الآيات والتكرارات والخطوات، وسرعة التلاوة.
• غيّر الإعدادات أثناء الجلسة، واختر: ابدأ من جديد، أو أكمل من الآية الحالية.

التلاوة
• القرآن كاملًا، ١١٤ سورة، بصوت الشيخ أحمد خليل شاهين.
• تُبَثّ التلاوة عبر الإنترنت، ويمكنك تنزيل أي سورة للاستماع دون اتصال.
• تستمر التلاوة والشاشة مقفلة، مع أزرار التحكم على شاشة القفل.

تقدّمك
• يتابع التطبيق ما كرّرته من كل آية وما حفظته من كل سورة.
• كل ذلك محفوظ على جهازك وحده.

بلا إعلانات، وبلا حسابات، ولا يجمع التطبيق أي بيانات عنك.
```

<!-- field: whatsnew ar 4000 -->
**What's New in This Version**
```
الإصدار الأول على آب ستور.
```

## English (`en-US`)

<!-- field: name en 30 -->
**Name** (≤ 30)
```
Iqra Wartaq
```

<!-- field: subtitle en 30 -->
**Subtitle** (≤ 30)
```
Memorize Quran by repetition
```

<!-- field: promo en 170 -->
**Promotional text** (≤ 170)
```
Memorize the Quran the way a halaqa teaches it: hear an ayah, repeat it, then the next, then both joined. The whole mushaf to read offline. No ads, no accounts.
```

<!-- field: keywords en 100 -->
**Keywords** (≤ 100)
```
quran,hifz,memorize,memorization,mushaf,tajweed,recitation,repeat,islam,muslim,juz,surah,koran,hafiz
```

<!-- field: description en 4000 -->
**Description** (≤ 4000)
```
Iqra Wartaq — the way of those who memorize

A Quran memorization (hifz) app built on talqeen, the method of the halaqa: hear an ayah and repeat it, then the next ayah, then both joined together — one rung at a time, until the whole passage holds.

The mushaf in your hands
• The whole mushaf in its familiar 604 pages, readable with no connection.
• Read it cover to cover, or one surah or one juz at a time.
• The app remembers the last page you read and takes you back to it, and keeps a history of your recent places.
• The text can be made larger, and the page has a light and a dark appearance.

The session plays over the text
• There is no separate player screen: tap the page and the session controls come up; the ayah being recited is marked, and the page follows it.
• Long-press an ayah to start from it, to memorize it alone, or to make it the start or the end of your range.
• A range may start in one surah and end in a later one.

Every session, your way
• How many times each step repeats.
• How ayahs are joined: cumulative (one ayah, then two, then three…), continuous (the whole passage, then again), or not at all.
• An optional full pass over the range at the end.
• The pauses between ayahs, repeats and steps, and the speed of recitation.
• Change the settings mid-session and choose: start again, or carry on from the current ayah.

Recitation
• The whole Quran, all 114 surahs, recited by Sheikh Ahmed Khalil Shaheen.
• Recitation streams over the internet, and any surah can be downloaded to listen offline.
• It keeps playing with the screen locked, with controls on the lock screen.

Your progress
• The app keeps track of how often you have repeated each ayah and what you have memorized of each surah.
• All of it stays on your device.

No ads, no accounts, and the app collects nothing about you.
```

<!-- field: whatsnew en 4000 -->
**What's New in This Version**
```
First release on the App Store.
```

## Screenshots

Taken from the running app on the simulators by `tool/store_screenshots.sh`
— real pages, a real session streaming from the CDN — never mock-ups.

| Set | Simulator | Pixels | Folder |
|---|---|---|---|
| iPhone 6.9″ (required; App Store Connect scales it down for smaller iPhones) | iPhone 17 Pro Max | 1320 × 2868 | `iphone/` |
| iPad 13″ (required, because the app runs on iPad) | iPad Pro 13-inch (M5) | 2064 × 2752 | `ipad/` |

**One set, in Arabic, for both listing languages.** The app always opens in
Arabic and has no language switch, so an English screenshot would show a
screen no user can reach. Upload these under the Arabic localization; the
English one falls back to them by itself. (The English strings exist in
`assets/translations/en.json`; if a language setting is ever added, run the
script with `en` as its third argument and add that set then.)

Upload in file-name order. The first three are what shows in search results.

| # | File | What it shows |
|---|---|---|
| 1 | `01-reading.png` | A surah opening in the mushaf's own page layout, framed. |
| 2 | `02-session.png` | A session playing over the text: the ayah marked, the controls, the repeat counter. |
| 3 | `03-home.png` | The home page: the surahs, their progress, and "continue reading". |
| 4 | `04-session-settings.png` | The session's settings: reciter, range across surahs, repeats, joining. |
| 5 | `05-ajzaa.png` | The thirty ajzaa, as a grid. |
| 6 | `06-method.png` | The introduction's leaf on the method. |
| 7 | `07-settings.png` | Settings, in cards. |

Regenerate:

```
tool/store_screenshots.sh "iPhone 17 Pro Max"     store/apple/iphone
tool/store_screenshots.sh "iPad Pro 13-inch (M5)" store/apple/ipad
```

## App Privacy ("nutrition label")

**Data Not Collected.**

Apple counts data as *collected* when it is sent off the device in a way that
lets the developer, or a partner, keep it beyond serving the request. This app
sends nothing: no accounts, no analytics, no crash reporting, no advertising
identifier. Its only network traffic is public `GET`s for static files — the
audio manifest, `app.json`, recitation audio and one optional portrait — from
GitHub Pages and a Cloudflare R2 bucket. Progress, settings and reading history
live in the app's own storage and never leave the device.

Tracking: **No.** `PrivacyInfo.xcprivacy` in the Runner target says the same.

## Age rating

Every question: **None / No.** No violence, sexual content, profanity, drugs,
gambling, contests, horror, medical information, user-generated content,
messaging, web browsing or advertising. Expected rating: **4+**.
"Made for Kids": **No** — it is for everyone, not designed for children.

## Export compliance

`ITSAppUsesNonExemptEncryption = false` is already in `Info.plist`: the app
uses only HTTPS, which is exempt, so App Store Connect does not ask at upload.

## Content rights — **blocked until the reciter answers**

App Store Connect asks: *"Does your app contain, show, or access third-party
content?"* — **Yes**: the recitation is Sheikh Ahmed Khalil Shaheen's. The
follow-up asks you to confirm you hold all necessary rights, and **you do not**.

The files were downloaded from **surahquran.com**, whose terms of use
(`surahquran.com/terms.html`) say downloads are for
«الاستخدام الشخصي غير التجاري» — personal, non-commercial use — and that
«يحظر أي استخدام آخر للموقع دون إذن كتابي مسبق منا»: any other use is forbidden
without their prior written permission. Re-hosting the clips on our own CDN and
shipping them in a store app is not personal use. (The originals also carry
`www.islamway.net` metadata from 2019, recorded in `docs/ASSETS_README.md` —
the recording has been passed between several sites, and none of them made it.)

surahquran.com cannot cure this either: they aggregate 250+ reciters and did
not record this one. The rights are the Sheikh's, or his producer's, so **ask
him**, and keep the dated reply as a PDF. A short Arabic message is enough; a
one-line grant is documentation.

Do not tick the rights confirmation until it arrives. The review notes above
are written so they state no licence in the meantime — they say who recited it,
that he is credited, that the app does not monetize it, that permission has
been requested, and that any recitation is removed on request.

If the permission does not come, the recitation has to be replaced before this
ships: a set whose terms are written down (the King Fahd Complex publishes its
own recitations at qurancomplex.gov.sa/quran-audios, which would also match the
KFGQPC text already bundled), or a commissioned reciter. Either is a re-cut
with `tool/publish_surah.dart` and the admin tool, not a rewrite.

## App Review information

| Field | Value |
|---|---|
| Sign-in required | **No** |
| Contact first / last name | Ahmed Elsersi |
| Contact email | ahmed.elsersi3@gmail.com |
| Contact phone | **verify — required by Apple, not in the repo** |

**Notes for the reviewer** — paste into **App Review Information → Notes**
and send the same text as the Resolution Center reply. Apple asked for both
in the 2026-09 information request; `docs/APP_REVIEW_NOTES.md` explains what
each numbered answer is for and what to change once the reciter replies.

<!-- field: reviewnotes en 4000 -->
**Review notes** (≤ 4000)
```
No account, no login, no in-app purchase, no ads, no user-generated content. Every screen is reachable from launch with no credentials, so there is no account creation or deletion flow.

1. SCREEN RECORDING: attached. Recorded on a physical iPhone running the latest iOS, beginning with the app launch and showing the typical flow.

2. PURPOSE AND AUDIENCE: Iqra Wartaq is a free Quran memorization (hifz) app, for anyone memorizing the Quran and for teachers and students in memorization circles (halaqat). Memorizing by audio repetition - the classical "talqeen" method - normally needs a teacher reciting with you. The app does it: one verse N times, then the next verse N times, then the two joined and repeated, widening the range verse by verse until the passage holds. The reader chooses the range, the repetitions, the joining mode, the pauses and the speed. The complete Quran is also readable offline in the printed mushaf page layout, and progress is tracked verse by verse on the device.

3. SETUP AND MAIN FEATURES: no credentials, no sample files, no configuration. The interface is Arabic, laid out right to left.
- Read: home -> "Surahs" or "Juz" tab -> tap any entry -> the mushaf opens there. Swipe to turn pages.
- Memorize: tap the page once to bring up the bar at the bottom, choose the verse range, repetitions and joining mode, then tap Start. The verse being recited is marked and the page follows it.
- Offline audio: Settings -> Saved recitations -> choose a surah -> download. Anything not downloaded streams instead.
- Progress: every verse shows as not started, in progress or memorized, on the device only.

4. EXTERNAL SERVICES: two, both read-only public HTTPS GETs to static hosting owned by the developer. The app sends nothing to either.
- GitHub Pages (ahmedelsersi.github.io/iqra-cdn): a static manifest.json listing the available recordings, and an app.json holding the app's About text and update information.
- Cloudflare R2 (public bucket): the recitation audio, streamed or downloaded per surah.
There is no backend, no authentication, no payment processor, no AI service, no analytics and no crash reporting. The app collects no data, as declared in App Privacy. The Quranic text is bundled as a read-only database and is never fetched or altered.

5. REGIONAL DIFFERENCES: none. The app behaves identically in every region and on every network. Nothing is geo-restricted, priced or gated by country. The text and the recitation are the same everywhere.

6. THIRD-PARTY MATERIAL: the Quranic text is the KFGQPC Hafs Uthmani Unicode text and font, published by the King Fahd Glorious Quran Printing Complex (qurancomplex.gov.sa) for free use in applications without modification, and shipped unchanged. The Quran itself is public-domain scripture; no translation or commentary is included. The recitation is by Sheikh Ahmed Khalil Shaheen, who is named in the app beside it. The app is free, carries no advertising or in-app purchases, and does not monetize the recording. We have written to the reciter to obtain his permission in writing, and we remove any recitation immediately on request from the reciter or the rights holder. The app is not in a regulated industry: it is a free reference and education app with no medical, financial or health function.

TECHNICAL NOTES: recitation audio streams from the CDN above the first time it is played, so please keep the device online during a session; a downloaded surah then plays with no network, and reading never needs one. Background modes: "audio", because a session runs for many minutes with the phone locked and is controlled from the lock screen; "fetch", so a surah being saved can finish downloading in the background. The app requests no permissions: the Photo Library usage strings exist only because a downloader plugin references those classes, and the requests are compiled out, so no prompt can appear.
```

## Before submitting — a checklist

- [ ] Accept the updated Program License Agreement; create the Apple
      Distribution certificate (see `docs/STORE_RELEASE.md`).
- [x] Publish the corrected privacy policy (done 2026-09-20; the old page said
      the app never uses the internet).
- [ ] Register `com.mirqat.app` and create the app record.
- [ ] Paste this listing; upload both screenshot sets under Arabic.
- [ ] Answer content rights, age rating, App Privacy as above.
- [ ] Remove China mainland from Pricing and Availability; leave the
      permit line in the Notes box blank.
- [ ] Paste the review notes above into App Review Information → Notes,
      attach the screen recording, and send the same text in Resolution
      Center.
- [ ] Ask the reciter for written permission before ticking content rights.
- [ ] `flutter build ipa --release`, upload with Transporter, pick the build.
- [ ] When there is an App Store page: put its URL in the admin tool's
      **app.json → Updates → iOS → Store page**, or the iOS update prompt
      stays off.
