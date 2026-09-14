#!/usr/bin/env bash
# Increments only the +N (build number / versionCode) half of pubspec.yaml's
# `version:` line, leaving the marketing version (versionName) untouched.
#
# Uses awk + a temp file rather than `sed -i`: GNU sed's -i takes a bare flag,
# BSD/macOS sed's -i requires a (possibly empty) suffix argument, and a script
# that runs both in CI (GNU) and on a contributor's Mac (BSD) cannot satisfy
# both with one invocation.
set -euo pipefail

cd "$(dirname "$0")/.."

PUBSPEC="pubspec.yaml"

CURRENT_LINE="$(grep -E '^version:' "$PUBSPEC" || true)"
if [[ -z "$CURRENT_LINE" ]]; then
  echo "error: no 'version:' line found in $PUBSPEC" >&2
  exit 1
fi

if [[ ! "$CURRENT_LINE" =~ \+([0-9]+)[[:space:]]*$ ]]; then
  echo "error: version line has no numeric +N build number: $CURRENT_LINE" >&2
  echo "Expected e.g. 'version: 1.0.0+1'." >&2
  exit 1
fi

PREVIOUS_BUILD="${BASH_REMATCH[1]}"
NEXT_BUILD=$((PREVIOUS_BUILD + 1))

TMP_FILE="$(mktemp "${PUBSPEC}.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

awk -v prev="$PREVIOUS_BUILD" -v newbuild="$NEXT_BUILD" '
  /^version:/ {
    sub("\\+" prev "[[:space:]]*$", "+" newbuild)
  }
  { print }
' "$PUBSPEC" > "$TMP_FILE"

mv "$TMP_FILE" "$PUBSPEC"
trap - EXIT

NEW_LINE="$(grep -E '^version:' "$PUBSPEC")"
echo "previous build: $PREVIOUS_BUILD" >&2
echo "new build:      $NEXT_BUILD" >&2
echo "$NEW_LINE" >&2

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "previous=$PREVIOUS_BUILD"
    echo "version=$NEXT_BUILD"
  } >> "$GITHUB_OUTPUT"
fi
