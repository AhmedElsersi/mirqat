# مِرْقاة — Brand Guide

App: Quran memorization by cumulative repetition. Arabic-first, offline, Egypt-launched.
Assets: `brand/*.svg`

---

## 1. The name

# مِرْقاة · Mirqāt

**Meaning:** a rung of a ladder; a means of ascent. Root ر-ق-ي (*to rise*).

**Why this word.** The app's method is literally a ladder. Ayah 1. Ayah 2. Then
1+2. Then ayah 3. Then 1+2+3. Every connect step is a rung you stand on before
reaching for the next one — you never climb past what already holds your weight.
The name describes the *mechanic*, not a generic virtue, which is what separates
a brand from a slogan with a logo attached.

It also carries scholarly weight without borrowing it cheaply: *Mirqāt
al-Mafātīh* is Mullā ʿAlī al-Qārī's commentary on *Mishkāt al-Maṣābīh*. The word
reads as serious and classical to an Arabic ear.

**Deliberately not a Quranic word.** A brand name ends up on stickers, invoices,
refund emails and error screens. Naming the app after a word lifted from a verse
puts scripture in all of those places. مرقاة is classical Arabic with religious
scholarly association but no verse attached — dignity without that exposure.

**Romanisation:** `Mirqat` in stores and code (no diacritics — App Store search
and bundle IDs handle them badly). `Mirqāt` in prose where typography allows.

### Names checked and rejected

| Candidate | Why not |
|---|---|
| **تثبيت** Tathbeet | Best *concept* (لِنُثَبِّتَ بِهِ فُؤَادَكَ is about revealing gradually to firm the heart), but تثبيت is the standard Arabic UI word for **"install"**. Store search would drown it in install-help results, and it reads as a system string, not a name. |
| **راسخ** Rasikh | Occupied four times over — a hifz error-tracker, a write-and-repeat memorization app, "Rasekh" hifz tracker, plus a Kuwaiti construction platform. Crowded past rescue. |
| **ترتيل** Tarteel | Taken by the best-known AI Quran app. Non-starter. |
| **ترديد** Tardeed | Accurate (repeating after a reciter) but flat — names the chore, not the outcome. |
| **وصل** Wasl | Lovely tajwīd resonance (wasl vs. waqf, and ٱ alef wasla in the text), but heavily used commercially across the Gulf. |
| **حفظ / تحفيظ** | Generic. Dozens of apps. Unsearchable. |

⚠️ **Not verified:** trademark registration (Egyptian Trademark Office / GOEIC),
domain availability, and current App Store / Play listings beyond the search
above. Check all three before you print anything or file.

## 2. Slogan

> ### ٱرْقَ آيةً آية
> **Ascend, one ayah at a time.**

ٱرْقَ is the imperative of the same root as مرقاة — the slogan and the name
reinforce each other, and together they teach the name's meaning without a
paragraph of explanation. It states the method (one ayah at a time) and the
promise (ascent) in three words.

**Store subtitle (30-char budget):**
- AR: `حفظ بالتكرار والوصل — بلا إنترنت`
- EN: `Memorize by repetition — offline`

## 3. Logo

Four rungs climbing to the upper **left** — forward, for an Arabic reader. Each
rung overlaps the one below so the steps visually chain rather than float: the
connect step made geometric. The top rung is gold — the ayah you're reaching for
now.

| File | Use |
|---|---|
| `mirqat-lockup-ar.svg` | Primary. Vocalised مِرْقاة — teaches the pronunciation (Mirqāt, not Marqāt). |
| `mirqat-lockup-ar-plain.svg` | Undiacritised. Cleaner at small sizes and in dense UI. |
| `mirqat-mark.svg` | Mark alone — nav bars, watermarks, splash. |
| `mirqat-icon.svg` | App icon. 512×512, 114 corner radius, no text. |
| `*-onDark.svg` | Vellum-on-ink variants for dark surfaces. |

Wordmark is **Amiri Regular, converted to outlines** — no font dependency, renders
identically everywhere.

**Rules**
- Clear space on all sides = one rung height (13 units at the mark's own scale).
- Never re-colour the rungs outside the palette; never gradient them.
- Never set the wordmark in a different typeface — use the SVG.
- **Never put Quranic text in the logo or icon.** Icons land on home screens
  beside games, in ad slots, on shipping boxes. Keep scripture out of the mark.
- No crescent, no dome, no minaret, no mushaf illustration. Every competitor uses
  them; that's the reason to skip them, and they carry national or political
  readings the app doesn't want.
- Minimum icon size verified at **48 px** — all four rungs and the gold accent
  stay distinguishable.

## 4. Colour

Drawn from manuscript illumination (*tadhhīb*) — lapis, gold leaf, vellum — not
from the default mosque-green every Quran app already owns.

| Token | Hex | Use |
|---|---|---|
| `ink` | `#16233F` | Primary brand, icon ground, headings on light |
| `gold` | `#C8A54B` | Accent only — active ayah, current rung, progress fill |
| `vellum` | `#F7F3EA` | Light surface — warm, easier than white for long reading |
| `ink-deep` | `#0E1626` | Dark-mode surface |
| `sabr` | `#2E7D6B` | Muted teal. Completion states **only** |
| `muted` | `#6B7385` | Secondary text, disabled |

Dark mode is not optional — a large share of hifz happens before Fajr and after
Isha. Design it first, not as an inversion afterthought.

**Gold is an accent, never a surface.** Large gold fields read as gaudy, which is
the opposite of the register this app needs.

## 5. Typography

| Role | Face | Notes |
|---|---|---|
| Arabic UI | **IBM Plex Sans Arabic** | Open source, real weight range, excellent screen rendering |
| Latin UI | **IBM Plex Sans** | Designed as a companion — one family across both scripts |
| Quran text | **UthmanicHafs V22** | The companion font of `quran.db`'s script export |
| Wordmark | Amiri Regular (outlined) | Logo only |

**The one non-negotiable rule:** the mushaf font is never used for UI, and the UI
font is never used for Quranic text. Setting a button label in the Uthmanic face
looks like a mistake; setting an ayah in Plex Arabic is worse than a mistake.

Fallback if Plex Arabic is unavailable: Cairo (ubiquitous in Egypt, free).

## 6. Voice

Calm, plain, unhurried. The subject carries the weight; the copy shouldn't add
any.

**Do**
- «تمّ» / "Done." — state what happened, then stop
- Neutral counts: «٣ من ٥ تكرارات»
- Arabic numerals as the locale expects (٣ in AR, 3 in EN)

**Don't**
- No emoji anywhere near an ayah
- No streaks, no fire icons, no leaderboards, no "you're on a roll!"
- **No guilt mechanics.** Never «لقد انقطعت!» or a red broken-streak badge.
  Someone who missed four days is not a lapsed user to re-engage — pressuring
  return to worship through loss-aversion is a dark pattern that happens to be
  pointed at someone's relationship with the Quran. Show the plan; let them
  resume.
- No superlatives on completion. «أحسنت» is enough; "AMAZING! 🎉" is not.

## 7. Store listing

**AR title:** `مرقاة — حفظ القرآن بالتكرار`
**EN title:** `Mirqat — Quran Memorization`

**AR description opening:**
> مرقاة يحفّظك القرآن كما يُلقَّن في حِلَق التحفيظ: تسمع الآية وتكرّرها، ثم الآية
> التي تليها، ثم تصلهما معًا — درجةً درجة، حتى تثبت. تلاوة الشيخ أحمد خليل شاهين،
> بلا إنترنت، وبلا إعلانات.

**EN description opening:**
> Mirqat teaches the way a halaqa does: hear an ayah and repeat it, then the next
> ayah, then both joined together — one rung at a time, until it holds. Recited by
> Sheikh Ahmed Khalil Shaheen. Fully offline. No ads.

Both open on the *method*, because the method is the differentiator. Every
competitor claims "memorize the Quran easily."

**Bundle ID:** `com.mirqat.app` — short, matches the name, no vendor prefix to
regret later.

## 8. Launch honesty

v1 ships Al-Fatiha and one reciter. Say so plainly in the listing rather than
letting a reviewer discover it:

> النسخة الأولى: سورة الفاتحة. السور التالية تُضاف تباعًا.

A one-surah app described accurately gets patient reviews. A one-surah app
described as "the Quran" gets one-star reviews that never wash off.
