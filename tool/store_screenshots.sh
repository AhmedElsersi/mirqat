#!/usr/bin/env bash
# Photographs the store-listing scenes on an iOS simulator.
#
#     tool/store_screenshots.sh "<simulator name>" <output dir> [ar|en]
#
#     tool/store_screenshots.sh "iPhone 17 Pro Max"     store/apple/iphone
#     tool/store_screenshots.sh "iPad Pro 13-inch (M5)" store/apple/ipad
#
# It runs tool/store_screenshots.dart — the real app, driven by real taps — and
# takes a screenshot each time that program says a scene is ready. The app is
# uninstalled first: the walk starts at the introduction, which only a fresh
# install shows. The session scene streams from the CDN, so it needs a network.
set -euo pipefail

DEVICE="${1:?simulator name}"
OUT="${2:?output directory}"
LOCALE="${3:-ar}"
BUNDLE_ID="com.mirqat.app"

cd "$(dirname "$0")/.."
mkdir -p "$OUT"
# Absolute: simctl resolves a relative path somewhere else, and fails.
OUT="$(cd "$OUT" && pwd)"

UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "No available simulator named \"$DEVICE\"." >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
# The clock Apple's own screenshots show, a full battery, full bars.
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl ui "$UDID" appearance light

LOG="$(mktemp -t store_shots)"
flutter run -d "$UDID" -t tool/store_screenshots.dart \
  --dart-define=SHOT_LOCALE="$LOCALE" >"$LOG" 2>&1 &
RUN=$!
trap 'kill $RUN 2>/dev/null || true; xcrun simctl status_bar "$UDID" clear || true' EXIT

# App Store Connect refuses a screenshot with an alpha channel, and the
# simulator writes one. Flattened in place; the pixels are opaque already.
flatten() {
  python3 - "$OUT" <<'FLATTEN'
import glob, sys
from PIL import Image
for path in glob.glob(sys.argv[1] + "/*.png"):
    image = Image.open(path)
    if image.mode != "RGB":
        image.convert("RGB").save(path, optimize=True)
FLATTEN
}

seen=0
while kill -0 $RUN 2>/dev/null; do
  total="$(grep -c '^flutter: SHOT:' "$LOG" || true)"
  while [ "$seen" -lt "$total" ]; do
    seen=$((seen + 1))
    line="$(grep '^flutter: SHOT:' "$LOG" | sed -n "${seen}p")"
    name="${line#flutter: SHOT:}"
    case "$name" in
      done) flatten; echo "done: $(ls "$OUT" | wc -l | tr -d ' ') screenshots in $OUT"; exit 0 ;;
      failed*) echo "$name" >&2; grep -A12 'SHOT:failed' "$LOG" >&2; exit 1 ;;
      *) xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
         echo "captured $name" ;;
    esac
  done
  sleep 0.3
done
echo "flutter run ended before the walk finished; see $LOG" >&2
exit 1
