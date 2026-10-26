#!/usr/bin/env bash
# Films the promo videos' scenes on an iOS simulator: the real app, walked by
# tool/store_screenshots.dart in its video mode, one clip per scene.
#
#     tool/promo_video.sh "iPhone 17 Pro Max" promo/raw [ar|en]
#
# Each `REC:<name>` the walk prints starts a recording into <out>/<name>.mp4,
# and `REC:stop` ends it. tool/promo_compose.py then cuts the clips into the
# finished videos. Like the screenshots, it starts from a fresh install.
set -euo pipefail

DEVICE="${1:?simulator name}"
OUT="${2:?output directory}"
LOCALE="${3:-ar}"
BUNDLE_ID="com.mirqat.app"

cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

UDID="$(xcrun simctl list devices available | grep -F "$DEVICE (" | head -1 \
  | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
[ -n "$UDID" ] || { echo "No available simulator named \"$DEVICE\"." >&2; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState discharging \
  --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork wifi
xcrun simctl ui "$UDID" appearance light

LOG="$(mktemp -t promo_video)"
flutter run -d "$UDID" -t tool/store_screenshots.dart \
  --dart-define=SHOT_LOCALE="$LOCALE" --dart-define=SHOT_MODE=video >"$LOG" 2>&1 &
RUN=$!
REC=""
stop_rec() {
  if [ -n "$REC" ]; then
    kill -INT "$REC" 2>/dev/null || true
    wait "$REC" 2>/dev/null || true
    REC=""
  fi
}
trap 'stop_rec; kill $RUN 2>/dev/null || true; xcrun simctl status_bar "$UDID" clear || true' EXIT

seen=0
while kill -0 $RUN 2>/dev/null; do
  total="$(grep -c '^flutter: REC:' "$LOG" || true)"
  while [ "$seen" -lt "$total" ]; do
    seen=$((seen + 1))
    line="$(grep '^flutter: REC:' "$LOG" | sed -n "${seen}p")"
    name="${line#flutter: REC:}"
    case "$name" in
      done) stop_rec; echo "done: $(ls "$OUT" | wc -l | tr -d ' ') clips in $OUT"; exit 0 ;;
      failed*) stop_rec; echo "$name" >&2; grep -A12 'SHOT:failed' "$LOG" >&2; exit 1 ;;
      stop) stop_rec; echo "stopped" ;;
      *) stop_rec
         xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$name.mp4" \
           >/dev/null 2>&1 &
         REC=$!
         echo "recording $name" ;;
    esac
  done
  sleep 0.2
done
echo "flutter run ended before the walk finished; see $LOG" >&2
exit 1
