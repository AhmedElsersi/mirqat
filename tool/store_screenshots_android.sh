#!/usr/bin/env bash
# Photographs the store-listing scenes on an Android emulator — the Play
# counterpart of tool/store_screenshots.sh, driving the same walk
# (tool/store_screenshots.dart).
#
#     tool/store_screenshots_android.sh <adb serial> <output dir> [ar|en]
#
#     tool/store_screenshots_android.sh emulator-5554 store/google/phone
#
# Start the emulator first. Play wants 9:16 for its promotional slots and
# refuses a long side more than twice the short one, which a 20:9 phone
# (1080 x 2400) breaks; the phone set is taken on a 1080 x 1920 AVD.
# The app is uninstalled first: the walk starts at the introduction, which only
# a fresh install shows. The session scene streams from the CDN, so it needs a
# network.
set -euo pipefail

SERIAL="${1:?adb serial, e.g. emulator-5554}"
OUT="${2:?output directory}"
LOCALE="${3:-ar}"
PACKAGE="com.mirqat.app"
ADB=(adb -s "$SERIAL")

cd "$(dirname "$0")/.."
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

"${ADB[@]}" wait-for-device
until [ "$("${ADB[@]}" shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do
  sleep 1
done
"${ADB[@]}" uninstall "$PACKAGE" >/dev/null 2>&1 || true

# Demo mode: a fixed clock, a full battery, full bars, no notifications.
demo() { "${ADB[@]}" shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
"${ADB[@]}" shell settings put global sysui_demo_allowed 1
demo enter
demo clock -e hhmm 0941
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4 -e fully true
demo network -e mobile hide
demo notifications -e visible false
"${ADB[@]}" shell cmd uimode night no >/dev/null

LOG="$(mktemp -t store_shots)"
flutter run -d "$SERIAL" -t tool/store_screenshots.dart \
  --dart-define=SHOT_LOCALE="$LOCALE" >"$LOG" 2>&1 &
RUN=$!
trap 'kill $RUN 2>/dev/null || true; demo exit || true' EXIT

# Play refuses a screenshot with an alpha channel, and screencap writes one.
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

# Android prefixes a print with "I/flutter (pid): ".
shots() { grep -o 'flutter.*SHOT:.*' "$LOG" | sed -E 's/.*SHOT://' || true; }

seen=0
while kill -0 $RUN 2>/dev/null; do
  total="$(shots | wc -l | tr -d ' ')"
  while [ "$seen" -lt "$total" ]; do
    seen=$((seen + 1))
    name="$(shots | sed -n "${seen}p")"
    case "$name" in
      done) flatten; echo "done: $(ls "$OUT" | wc -l | tr -d ' ') screenshots in $OUT"; exit 0 ;;
      failed*) echo "$name" >&2; grep -A12 'SHOT:failed' "$LOG" >&2; exit 1 ;;
      *) "${ADB[@]}" exec-out screencap -p >"$OUT/$name.png"
         echo "captured $name" ;;
    esac
  done
  sleep 0.3
done
echo "flutter run ended before the walk finished; see $LOG" >&2
exit 1
