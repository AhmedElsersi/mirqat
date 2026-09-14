# اقرأ وارتق — Iqra Wartaq

> سمت الحافظين

An offline Quran memorization (hifz) app built around talqeen-style
spaced repetition of audio.

The Dart package is still named `mirqat` and the application id is still
`com.mirqat.app`: only the *display* name changed. Renaming either would
orphan every existing install and every `package:mirqat/...` import, so
they are deliberately left as they are.

## Release checklist

Before tagging a release:

1. **Deploy the public pages first, and open both URLs yourself.** Play
   rejects a listing whose privacy-policy link 404s, and won't re-check it
   for you until the next review — confirm both the privacy policy and (if
   used) the account-deletion page are live before touching the Play
   Console. See `docs/PLAY_LISTING.md` for the URLs.
2. First release only: build and upload by hand (a service account can't
   create the app or accept Play's developer agreement) — see
   `docs/PLAY_LISTING.md` § "The first upload must be done by hand."
3. Every release after that: `git tag vX.Y.Z && git push origin vX.Y.Z`
   triggers `.github/workflows/release.yml`.

Full submission process, store copy, and the Data Safety declaration are in
[`docs/PLAY_LISTING.md`](docs/PLAY_LISTING.md).

## CI/CD

- `.github/workflows/ci.yml` — analyze + test on every push to `main` and
  every PR.
- `.github/workflows/bump-build-number.yml` — auto-increments the `+N` half
  of `pubspec.yaml`'s `version:` on push to `main`.
- `.github/workflows/release.yml` — on a `v*` tag (or manual dispatch):
  builds a signed app bundle and uploads it to Play's `production` track.

### Required repository secrets

| Secret | Used by | What it is |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | `release.yml` | The upload keystore (`android/app/upload-keystore.jks`) from `tool/make_upload_key.sh`, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | `release.yml` | That keystore's store password |
| `ANDROID_KEY_ALIAS` | `release.yml` | The key alias inside the keystore (`upload` by default) |
| `ANDROID_KEY_PASSWORD` | `release.yml` | That key's password |
| `PLAY_SERVICE_ACCOUNT_JSON` | `release.yml` | Google Cloud service-account JSON with Play Console release access — see `docs/PLAY_LISTING.md` for how to generate it |
| `GOOGLE_SERVICES_JSON` | `release.yml` (optional, currently unused) | Base64-encoded Firebase `google-services.json`, only if a later milestone adds Firebase — Milestone 1 has none |

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
