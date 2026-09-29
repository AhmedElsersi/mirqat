#!/usr/bin/env bash
# Puts everything release.yml needs into the repository's secrets, in one go.
#
# Reads what is on this machine — the Android upload keystore and its
# passwords, the App Store Connect API key — and takes the rest as arguments:
# the distribution certificate exported from Keychain Access as a .p12 (with
# the password given at export), the API key's issuer ID (App Store Connect →
# Users and Access → Integrations → App Store Connect API, at the top), and
# the Google Play service account's JSON. Nothing is printed; secrets go to
# GitHub through `gh secret set` and nowhere else.
#
#   tool/set_release_secrets.sh \
#     --p12 ~/Desktop/dist.p12 --p12-password '…' \
#     --issuer-id 12345678-aaaa-bbbb-cccc-123456789012 \
#     --play-json ~/Downloads/play-service-account.json
#
# Any of the four may be left out to keep what the repository already has.
set -euo pipefail
cd "$(dirname "$0")/.."

P12=""; P12_PASSWORD=""; ISSUER=""; PLAY_JSON=""
while (( $# > 0 )); do
  case "$1" in
    --p12) P12="$2"; shift 2 ;;
    --p12-password) P12_PASSWORD="$2"; shift 2 ;;
    --issuer-id) ISSUER="$2"; shift 2 ;;
    --play-json) PLAY_JSON="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null || { echo "gh is not installed (brew install gh; gh auth login)" >&2; exit 1; }

set_secret() { gh secret set "$1" --body "$2" >/dev/null && echo "set $1"; }
set_secret_file() { gh secret set "$1" < "$2" >/dev/null && echo "set $1 (from $2)"; }

# Android: the keystore and key.properties are already on this machine.
if [[ -f android/app/upload-keystore.jks && -f android/key.properties ]]; then
  set_secret ANDROID_KEYSTORE_BASE64 "$(base64 < android/app/upload-keystore.jks)"
  prop() { grep "^$1=" android/key.properties | cut -d= -f2-; }
  set_secret ANDROID_KEYSTORE_PASSWORD "$(prop storePassword)"
  set_secret ANDROID_KEY_PASSWORD "$(prop keyPassword)"
  set_secret ANDROID_KEY_ALIAS "$(prop keyAlias)"
else
  echo "skipping Android signing: android/app/upload-keystore.jks or android/key.properties is missing" >&2
fi
[[ -z "$PLAY_JSON" ]] || set_secret_file PLAY_SERVICE_ACCOUNT_JSON "$PLAY_JSON"

# Apple: the API key is under ~/.appstoreconnect; its id is the file's name.
KEY_FILE="$(ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1 || true)"
if [[ -n "$KEY_FILE" ]]; then
  KEY_ID="$(basename "$KEY_FILE" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"
  set_secret APPSTORE_KEY_ID "$KEY_ID"
  set_secret_file APPSTORE_PRIVATE_KEY "$KEY_FILE"
else
  echo "skipping the App Store Connect API key: none under ~/.appstoreconnect/private_keys" >&2
fi
[[ -z "$ISSUER" ]] || set_secret APPSTORE_ISSUER_ID "$ISSUER"
if [[ -n "$P12" ]]; then
  [[ -n "$P12_PASSWORD" ]] || { echo "--p12 needs --p12-password" >&2; exit 2; }
  set_secret IOS_DIST_CERT_P12_BASE64 "$(base64 < "$P12")"
  set_secret IOS_DIST_CERT_PASSWORD "$P12_PASSWORD"
fi

echo
echo "release.yml needs these; the ones not listed above are still to be set:"
echo "  ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD PLAY_SERVICE_ACCOUNT_JSON"
echo "  IOS_DIST_CERT_P12_BASE64 IOS_DIST_CERT_PASSWORD APPSTORE_KEY_ID APPSTORE_ISSUER_ID APPSTORE_PRIVATE_KEY"
echo "now set: $(gh secret list | awk '{print $1}' | tr '\n' ' ')"
