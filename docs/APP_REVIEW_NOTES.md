# App Review notes — Iqra Wartaq (اقرأ وارتق)

What to put in **App Store Connect → App Review Information → Notes**, and what
to reply in Resolution Center. Written for the 2026-09 "limited App Review
history / need more information" request, which is an information request, not a
bug report: nothing in the app has to change to answer it.

Keep this file in step with the app. Bundle id `com.mirqat.app`, team
`U2443AH4P4`, version from `pubspec.yaml`.

---

## The Notes field / Resolution Center reply

**The text itself lives in `store/apple/LISTING.md`**, under *App Review
information*, so it sits with the rest of the paste-ready listing and
`tool/check_store_listing.py` enforces the 4000-character limit on it like
every other field (it is currently 3981). This file explains it; that file is
what you paste.

Paste it in **both** places — App Store Connect → the version page → **App
Review Information → Notes**, and as the Resolution Center reply. Apple asked
for both. The recording goes in the **Attachment** slot in the same section.

That Notes box is the right one even though its help text talks about Chinese
permits for religious content: Apple put the hint there because permit numbers
are entered in the same box. It applies only if the app is sold in mainland
China — see below.

The six numbered answers map to Apple's six questions. The first line answers
three of their sub-requests at once (registration, deletion, user-generated
content, paid content) by saying none of them exist.

### Item 6 — the two versions

What is in `LISTING.md` today is the **no-permission** version: it states where
the recitation came from and that the app does not monetize it, and claims no
licence. Nothing in it is untrue.

When Sheikh Ahmed Khalil Shaheen (or Islamway, as the session's publisher)
grants permission in writing, replace the third sentence of answer 6 —

> The recitation is by Sheikh Ahmed Khalil Shaheen, published for free
> listening and download for religious purposes, and he is named in the app
> beside it.

— and the one after the monetization sentence, with:

> The recitation is by Sheikh Ahmed Khalil Shaheen and is used with his written
> permission, a copy of which is attached.

Then tick **Content Rights** in App Store Connect, and attach the permission
next to the screen recording. Watch the character count: `LISTING.md` is at
3981 of 4000, so trim a sentence if the replacement runs longer.

### The rights question, plainly

A Quran *recitation* is a sound recording with its own copyright — the
reciter's, or the producer who recorded the session. The Quranic *text* has
none. Freely downloadable is not freely redistributable, and here the source
says so itself: the clips came from **surahquran.com**, whose terms allow
downloads for personal, non-commercial use only and forbid any other use
without their written permission. Re-hosting them on our CDN and shipping them
in a store app is not personal use.
app. If it's ever challenged, "my teacher asked and the Sheikh said yes" is harder to stand on than one message that names the app and the
publisher.

The fix is one more message, and your teacher is the right person to send it since the Sheikh already knows him.

Have your teacher send this:

Two concrete consequences, not theory:

1. **App Store Connect → Content Rights** asks you to affirm you hold all
   necessary rights to third-party content. That cannot be ticked truthfully,
   and the source's terms are in writing.
2. **Takedown.** A complaint from the reciter or his producer removes the app.

The fix is cheap and it is the only one that works: **ask Sheikh Ahmed Khalil
Shaheen.** Reciters generally say yes to a free, ad-free hifz app that credits
them, and a dated WhatsApp or email reply granting permission is documentation
enough — keep it as a PDF with the date and the account it came from. Asking
surahquran.com is not a substitute: they aggregate 250+ reciters and recorded
none of them, so they have nothing to grant.

If no permission comes, the recitation must be replaced before release — a set
whose terms are written down (the King Fahd Complex publishes its own
recitations, which would match the KFGQPC text already bundled), or a
commissioned reciter, which is owned outright. Either is a re-cut through
`tool/publish_surah.dart` and the admin tool, not a rewrite.

Submit the reply to Apple now — it answers their six questions and claims no
licence. Hold the **resubmission** until the permission is in hand.

---

## Also do these in App Store Connect

| Where | What |
|---|---|
| App Review Information → Notes | Paste the reply above (Apple asked for it in the Notes field, not only in Resolution Center) |
| App Review Information → Sign-in required | **Off** — there is no account |
| App Review Information → Contact | A phone number and email that are actually reachable |
| Attachment | The screen recording (`.mp4`/`.mov`), plus the reciter permission PDF if you have it |
| App Privacy | *Data Not Collected* (already the intended answer) |
| Content Rights | Declare the third-party content and that you hold the rights — the recitations are what this question is about |
| Screenshots | Must show the app in use — the mushaf page and a running session, not the splash or the onboarding intro. iPhone 6.9" required; iPad 13" required too unless the target is set to iPhone-only |
| Age rating | Reference / Education, no objectionable content |
| Privacy Policy URL | https://ahmedelsersi.github.io/iqra-wartaq/privacy.html |
| Support URL | https://ahmedelsersi.github.io/iqra-wartaq/ |

## Mainland China

Chinese law requires a permit for apps with religious, news, book or magazine
content to be sold in mainland China, and App Store Connect asks for the permit
number in the same Notes box. We hold no such permit, so **remove China
mainland from Pricing and Availability** and leave the permit line blank. A
Quran app offered there without a permit is rejected or removed later; taking
the storefront out is the clean answer, and it changes nothing anywhere else.

## The screen recording

One take, on a physical iPhone on the current iOS, 2–4 minutes, screen
recording from Control Center. Start with the device home screen and tap the
app icon — Apple asks that it begin with the launch. Keep the device **online**
until the offline part.

1. Tap the icon. Let the introduction appear; page through it.
2. Home screen — show the *Surahs* tab, switch to *Juz*, scroll a little.
3. Open a short surah. Turn a page or two by swiping.
4. Tap the session button. Show the form: verse range, reciter, repetitions,
   joining mode. Start the session.
5. Let it run ~30 seconds with sound, so the repetition and the marked verse
   are both visible. Change the speed or a pause to show live control.
6. Lock the device for a few seconds: the lock-screen controls and the
   continuing audio. Unlock.
7. Stop the session. Open the progress screen.
8. Settings → Saved recitations → download one surah → show it completing.
9. Turn on Airplane Mode. Open the mushaf and play a session on the downloaded
   surah — it works with no network. Turn Airplane Mode off.
10. Settings → About / How to use, and the version line at the foot of
    Settings.

Say nothing about accounts, purchases or user content in the recording; there
are none, and the written reply already says so.
