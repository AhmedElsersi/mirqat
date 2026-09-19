# Releasing to the App Store and Google Play

What is already set up in the project, how to produce the builds, and the
steps only the account holder can do. `test/store_release_config_test.dart`
guards everything under "Already in the project".

Bundle / application id: `com.mirqat.app` · display name: اقرأ وارتق ·
version comes from `pubspec.yaml` (`version: 1.0.0+1` → 1.0.0, build 1).
**Raise the build number (`+2`, `+3`, …) for every upload**; both stores refuse
a build number they have seen.

## Already in the project

### iOS

| what | why |
|---|---|
| `UIBackgroundModes`: `audio` | A session keeps reciting when the phone locks. Without it iOS suspends the app a few seconds after the screen goes dark. The playback audio category itself comes from `just_audio` (via `audio_session`), so the ring/silent switch does not mute a session. |
| `UIBackgroundModes`: `fetch` | `background_downloader` needs it for pack downloads to finish in the background. |
| `ITSAppUsesNonExemptEncryption` = `false` | The app only uses HTTPS, which is exempt. Answers the export-compliance question once instead of at every upload. |
| `PrivacyInfo.xcprivacy` in the Runner target | No tracking, nothing collected. Plugins and Flutter ship their own manifests for the APIs they call. |
| Podfile `BYPASS_PERMISSION_*` flags | Compiles out `background_downloader`'s notification and Photo Library permission *requests*: neither prompt can ever appear. |
| `NSPhotoLibrary*UsageDescription` (ar + en) | The plugin still *names* the Photos classes, and Apple's upload scan demands a purpose string for that (ITMS-90683). The strings say the app does not use the photo library; with the requests compiled out, nobody is ever shown them. |
| No App Transport Security exception | Tested and not needed: ATS does not apply to IP addresses, so `just_audio`'s caching proxy on `127.0.0.1` streams without one. `flutter run -t tool/stream_probe.dart` re-checks this on a device. |
| Audio directory excluded from iCloud backup | Apple rejects apps that back up re-downloadable content (CLAUDE.md A.5). |
| App icon without alpha, launch screen, Arabic + English `InfoPlist.strings` | Checked: the 1024 icon has no alpha channel; `flutter build ipa` validation passes. |

No microphone, camera, location, contacts, tracking or notification permission
is requested, and none is needed.

### Android

| what | why |
|---|---|
| Permissions: `INTERNET`, `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | The last three are for the lock-screen controls (`audio_service`). All four are granted at install — **none shows the user a prompt**, and media-session notifications are exempt from the notification permission. In Play Console's *App content → Foreground service* declaration, choose **Media playback**. |
| `AudioService` + `MediaButtonReceiver` in the manifest; `MainActivity` extends `AudioServiceActivity` | The media session behind the lock-screen controls, sharing the app's Flutter engine. |
| Release signing from `android/key.properties` + `upload-keystore.jks` | Both gitignored. **Back them up somewhere safe** — losing the upload key means asking Google to reset it. |
| `targetSdk` 36, `minSdk` 24 | From the Flutter SDK; meets Play's target API requirement. |
| `network_security_config.xml` | Cleartext only to `127.0.0.1`/`localhost` (the caching proxy); everything else is HTTPS. |
| `backup_rules.xml` + `data_extraction_rules.xml` | Downloaded audio and portraits stay out of Auto Backup, which fails outright past 25 MB and would take the memorization progress with it. |

## Building

```
flutter build appbundle --release      # → build/app/outputs/bundle/release/app-release.aab
flutter build ipa --release            # → build/ios/ipa/*.ipa   (needs the Apple steps below)
```

Check the Android bundle is signed with the upload key, not the debug key:

```
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep Owner
```

## Only the account holder can do these

### Apple (the archive builds; the export is blocked on these)

`flutter build ipa` currently stops at export with *"PLA Update available"* and
*"No signing certificate iOS Distribution found"*:

1. Sign in at <https://developer.apple.com/account> as the **Account Holder**
   and accept the updated Program License Agreement. Until that is done Xcode
   cannot create certificates or profiles.
2. Xcode → Settings → Accounts → add the Apple ID of team `Q2BFMPYYX7` →
   *Manage Certificates* → **+ Apple Distribution**.
3. Register the app: App Store Connect → Apps → **+ New App** → bundle id
   `com.mirqat.app` (create the identifier first under Certificates,
   Identifiers & Profiles if it is not offered).
4. `flutter build ipa --release`, then upload `build/ios/ipa/*.ipa` with the
   **Transporter** app (or `open build/ios/archive/Runner.xcarchive` and
   *Distribute App* in Xcode).

Then in App Store Connect:

- **App Privacy** → *Data Not Collected*.
- **Privacy Policy URL** — required for every app, even one that collects
  nothing. A short page saying so is enough.
- **Age rating** questionnaire; category **Reference** or **Education**.
- **Content rights**: the app streams recitations. Apple asks whether you have
  the rights to third-party content — you need the reciters' permission (or
  recordings you own) to answer yes.
- **Screenshots**: iPhone 6.9" is required. The app is universal, so **iPad 13"
  screenshots are required too**. If you would rather not maintain an iPad
  listing, set the target to iPhone-only in Xcode (Runner → General →
  Supported Destinations); it still runs on iPad, in an iPhone-sized window.
- **Review notes**: no login is needed; say that audio streams from your CDN
  and that a surah can be downloaded for offline use.

### Google Play

See `docs/PLAY_LISTING.md` for the listing. Upload the `.aab` to a Play Console
internal-testing track first; Play App Signing re-signs it with Google's key.
The **Data safety** form answer is *no data collected or shared*.

## Known limits of this release

- **iPad uses the phone layout**, stretched. It renders cleanly and passes
  review; it is not a tablet design.
- **The lock screen has no scrubber.** A position inside one clip means nothing
  across a queue of repeats, so previous and next move by *step* instead.
