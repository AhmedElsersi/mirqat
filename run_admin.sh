#!/usr/bin/env bash
# Launches the macOS-only admin tool with the R2 credentials from admin.env.
#
# admin.env is gitignored and holds live keys. Nothing in lib/ has a fallback
# for any of these, so a missing key stops the tool at launch rather than
# halfway through an upload.
#
#   ./run_admin.sh              # debug run on macOS
#   ./run_admin.sh --release    # anything after the script name goes to flutter
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f admin.env ]]; then
  echo "admin.env is missing. Copy admin.dev.example to admin.env and fill it" >&2
  echo "in from the Cloudflare R2 dashboard. Never commit it." >&2
  exit 1
fi

# `set -a` exports everything admin.env defines, so the loop below can read it
# without repeating the names here.
set -a
# shellcheck disable=SC1091
source admin.env
set +a

missing=()
for key in R2_ACCOUNT_ID R2_ACCESS_KEY R2_SECRET_KEY R2_BUCKET R2_ENDPOINT \
           R2_PUBLIC_BASE AUDIO_BITRATE; do
  if [[ -z "${!key:-}" ]]; then
    missing+=("$key")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "admin.env is missing: ${missing[*]}" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is not on PATH. The splitter shells out to the system binary" >&2
  echo "(ffmpeg_kit_flutter was archived in 2026 and is not an option)." >&2
  echo "    brew install ffmpeg" >&2
  exit 1
fi

# Optional: with these the tool publishes manifest.json to the Pages site
# itself, so adding a reciter or a surah needs no app release and no manual
# commit. Without them it writes the file and tells you where.
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_MANIFEST_PATH="${GITHUB_MANIFEST_PATH:-manifest.json}"

# Where this checkout is, so that what the tool publishes — app.json — is also
# written into the app's bundled copy and the two never drift.
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

exec flutter run -d macos -t lib/main_admin.dart "$@" \
  --dart-define=PROJECT_DIR="$PROJECT_DIR" \
  --dart-define=GITHUB_TOKEN="$GITHUB_TOKEN" \
  --dart-define=GITHUB_REPO="$GITHUB_REPO" \
  --dart-define=GITHUB_MANIFEST_PATH="$GITHUB_MANIFEST_PATH" \
  --dart-define=R2_ACCOUNT_ID="$R2_ACCOUNT_ID" \
  --dart-define=R2_ACCESS_KEY="$R2_ACCESS_KEY" \
  --dart-define=R2_SECRET_KEY="$R2_SECRET_KEY" \
  --dart-define=R2_BUCKET="$R2_BUCKET" \
  --dart-define=R2_ENDPOINT="$R2_ENDPOINT" \
  --dart-define=R2_PUBLIC_BASE="$R2_PUBLIC_BASE" \
  --dart-define=AUDIO_BITRATE="$AUDIO_BITRATE"
