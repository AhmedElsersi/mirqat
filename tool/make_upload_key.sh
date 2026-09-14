#!/usr/bin/env bash
# Run-once generator for the Play Store upload keystore.
#
# This key signs every release you ever upload to Play. Losing it, or letting
# it expire, means you can never publish an update to this application id
# again under Play App Signing's upload-key rotation flow without going
# through Google's identity-verification key-reset process. There is no
# "regenerate and move on" here, so the script is deliberately conservative:
# it refuses to touch an existing keystore, and it never lets the password
# pass through argv or an env dump.
set -euo pipefail

cd "$(dirname "$0")/.."

KEYSTORE_PATH="android/app/upload-keystore.jks"
PROPERTIES_PATH="android/key.properties"
KEY_ALIAS="${KEY_ALIAS:-upload}"

if [[ -f "$KEYSTORE_PATH" ]]; then
  echo "error: $KEYSTORE_PATH already exists." >&2
  echo "Signing an app already on Play with a different key locks you out of" >&2
  echo "shipping updates to it. If you really mean to replace it, move the" >&2
  echo "existing file aside yourself first (e.g. to a password manager or an" >&2
  echo "offline backup) — this script will not overwrite or delete it for you." >&2
  exit 1
fi

if [[ -f "$PROPERTIES_PATH" ]]; then
  echo "error: $PROPERTIES_PATH already exists and would be overwritten." >&2
  echo "Move it aside first if you intend to regenerate it." >&2
  exit 1
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "error: keytool not found. It ships with the JDK — install one (e.g. via" >&2
  echo "Android Studio, or 'brew install openjdk') and ensure it's on PATH." >&2
  exit 1
fi

echo "Upload keystore identity (the certificate's -dname). Business decisions —" >&2
echo "answer for your own organization/publisher identity, not placeholders." >&2
read -r -p "CN (name, e.g. your legal/publisher name): " DN_CN
read -r -p "OU (organizational unit, e.g. Mobile): " DN_OU
read -r -p "O  (organization/company name): " DN_O
read -r -p "L  (city/locality): " DN_L
read -r -p "C  (2-letter country code, e.g. EG): " DN_C

if [[ -z "$DN_CN" || -z "$DN_O" || -z "$DN_L" || -z "$DN_C" ]]; then
  echo "error: CN, O, L, and C are required." >&2
  exit 1
fi
DNAME="CN=${DN_CN}, OU=${DN_OU}, O=${DN_O}, L=${DN_L}, C=${DN_C}"

# read -rs (silent, no echo) keeps the password off the terminal; passing it
# to keytool via -storepass:env/-keypass:env (an env var name, not the value)
# keeps it out of both shell history and `ps` output, which would otherwise
# show argv to any other user on the machine.
read -rs -p "Upload key password (min 6 chars, used for both store and key): " KEYSTORE_PASSWORD
echo >&2
read -rs -p "Confirm password: " KEYSTORE_PASSWORD_CONFIRM
echo >&2

if [[ "$KEYSTORE_PASSWORD" != "$KEYSTORE_PASSWORD_CONFIRM" ]]; then
  echo "error: passwords did not match." >&2
  exit 1
fi
if [[ "${#KEYSTORE_PASSWORD}" -lt 6 ]]; then
  echo "error: keytool requires passwords of at least 6 characters." >&2
  exit 1
fi

export KEYSTORE_PASSWORD

mkdir -p "$(dirname "$KEYSTORE_PATH")"

# -validity 10000 (days) is ~27 years from today, comfortably past Play's own
# floor: an upload key must be valid past 22 Oct 2033, and an expired key can
# never sign another update.
keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -alias "$KEY_ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass:env KEYSTORE_PASSWORD \
  -keypass:env KEYSTORE_PASSWORD \
  -dname "$DNAME"

# umask 077 before writing so no other local account can read the password,
# even for the instant between creation and a later chmod.
(
  umask 077
  # storeFile is a bare filename: Gradle resolves key.properties-relative
  # paths against android/app/, which is where the keystore actually lives.
  # CI's release workflow writes this same file the same way, so both paths
  # agree on where the jks sits.
  cat > "$PROPERTIES_PATH" <<PROPS
storePassword=${KEYSTORE_PASSWORD}
keyPassword=${KEYSTORE_PASSWORD}
keyAlias=${KEY_ALIAS}
storeFile=upload-keystore.jks
PROPS
)

unset KEYSTORE_PASSWORD KEYSTORE_PASSWORD_CONFIRM

echo "Wrote $KEYSTORE_PATH and $PROPERTIES_PATH." >&2
echo "Keep both out of git (already covered by .gitignore) and back the" >&2
echo "keystore + password up somewhere durable — losing either one is fatal" >&2
echo "to shipping future updates under this applicationId." >&2
