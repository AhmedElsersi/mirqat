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

## Releasing from GitHub

**Every push to `main` is a release.** `.github/workflows/release.yml` runs
analyze and test again, builds the Android bundle and uploads it to Play, and
archives the iOS app and uploads it to App Store Connect — the same commit,
with the build number it carries in `pubspec.yaml`. `bump-build-number.yml`
then moves `main` on by one, so the next push is a new build on both stores.
Pushes that only touch `docs/`, `store/` or Markdown do not release. A `v*`
tag and the *Run workflow* button still work.

**Work goes to `dev` first.** `ci.yml` runs on every push to `dev` and on
pull requests; merge into `main` when it is ready to ship. Nothing is
uploaded from `dev`.

The workflow needs these repository secrets; `tool/set_release_secrets.sh`
sets them all in one command, reading what is on this machine and taking the
rest as arguments:

| Secret | What | Where from |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | the upload keystore | `android/app/upload-keystore.jks`, base64 |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | its passwords | `android/key.properties` |
| `PLAY_SERVICE_ACCOUNT_JSON` | a Play Console service account with release rights | Play Console → Users and permissions; Google Cloud → its JSON key |
| `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD` | the distribution certificate with its private key | Keychain Access → *iPhone Distribution: Ahmed Elsersi* → Export → .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | the manually managed App Store profile **Mirqat App Store** for `com.mirqat.app` | Certificates, Identifiers & Profiles → Profiles; installed on this Mac, the script finds it by name. **Expires yearly** (currently 2027-09-23): make a new one there with the same name and certificate, open it, run the script again. Xcode's own managed profile will not do under manual signing |
| `APPSTORE_KEY_ID`, `APPSTORE_PRIVATE_KEY` | an App Store Connect API key (App Manager role) | `~/.appstoreconnect/private_keys/AuthKey_<id>.p8` |
| `APPSTORE_ISSUER_ID` | that key's issuer | App Store Connect → Users and Access → Integrations → App Store Connect API |

A job whose secrets are missing stops at its first step and names them.

The iOS job signs by hand with team `U2443AH4P4`, the certificate and the
profile above, and exports with `ios/ExportOptions.plist` (`app-store-connect`,
`destination: upload`). Not automatic signing: an API key is not always allowed
to create profiles ("Cloud signing permission error"), and a profile in hand
needs no permission. After a push,
the build appears in App Store Connect under TestFlight once Apple has
processed it; attaching it to a version and submitting for review stays a
manual step, as does promoting anything in Play beyond what the workflow does.

## Releasing by hand

### Apple

The team is `U2443AH4P4`, the distribution certificate is in the login
keychain, and Xcode is signed in. Then:

```
flutter build ipa --release
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ios/ExportOptions.plist -exportPath build/ios/export \
  -allowProvisioningUpdates
```

The second command uploads (that is what `destination: upload` means); the
`.ipa` under `build/ios/ipa` can instead be dropped into **Transporter**.

**Editing signing in Xcode's UI hardcodes the version into
`project.pbxproj`** — `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` and a
`FLUTTER_BUILD_NUMBER` build setting — and that overrides the version from
`pubspec.yaml`, so the upload carries the wrong build number and is refused.
After any such edit, check the Runner target still has
`CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)"`,
`MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)"`, and no `FLUTTER_BUILD_NUMBER =`
line.

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
