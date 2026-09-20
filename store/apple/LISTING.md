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
| Availability | All countries and regions |
| Devices | iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`) |
| Copyright | © 2026 Ahmed Elsersi |
| Support URL | <https://ahmedelsersi.github.io/iqra-wartaq/> |
| Marketing URL | <https://ahmedelsersi.github.io/iqra-wartaq/> |
| Privacy Policy URL | <https://ahmedelsersi.github.io/iqra-wartaq/privacy.html> — **must be updated first, see `PRIVACY_POLICY.md`** |

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

## Content rights — **verify**

App Store Connect asks: *"Does your app contain, show, or access third-party
content?"* — **Yes**: the recitations are Sheikh Ahmed Khalil Shaheen's. Answer
*"Yes, and I have the rights"* **only if you hold his permission to distribute
them**, and keep that permission where you can produce it if Apple asks. The
Quranic text and page layout come from the Quranic Universal Library (QUL)
sources in `data/sources/`; check their terms are met.

## App Review information

| Field | Value |
|---|---|
| Sign-in required | **No** |
| Contact first / last name | Ahmed Elsersi |
| Contact email | ahmed.elsersi3@gmail.com |
| Contact phone | **verify — required by Apple, not in the repo** |

**Notes for the reviewer** (paste as is):

```
No account or sign-in exists; every screen is reachable straight away.

To see the main feature: on the home page tap any surah, tap the page once to
bring up the bar at the bottom, then tap Start (ابدأ). The recitation streams
over HTTPS from our CDN, so the device needs a connection for audio; reading
the Quran text works fully offline.

Background modes:
- audio: a memorization session runs for many minutes with the phone locked
  and is controlled from the lock screen.
- fetch: used by the downloader so that a surah being saved for offline
  listening can finish in the background.

The app asks for no permissions. The Photo Library usage strings are present
only because a downloader plugin references those classes; the permission
requests are compiled out and the prompt can never appear.

The interface is in Arabic, laid out right to left.
```

## Before submitting — a checklist

- [ ] Accept the updated Program License Agreement; create the Apple
      Distribution certificate (see `docs/STORE_RELEASE.md`).
- [ ] **Publish the corrected privacy policy** (`PRIVACY_POLICY.md`). The page
      that is live says the app never uses the internet; the app now streams.
- [ ] Register `com.mirqat.app` and create the app record.
- [ ] Paste this listing; upload both screenshot sets under Arabic.
- [ ] Answer content rights, age rating, App Privacy as above.
- [ ] `flutter build ipa --release`, upload with Transporter, pick the build.
- [ ] When there is an App Store page: put its URL in the admin tool's
      **app.json → Updates → iOS → Store page**, or the iOS update prompt
      stays off.
