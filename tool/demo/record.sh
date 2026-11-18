#!/usr/bin/env bash
# Runs inside the Android emulator job: drives the app with the demo test and
# records the screen from the "MARK|start" log line until the test ends.
set -uo pipefail
OUT=demo-out
mkdir -p "$OUT"
adb logcat -c

# The slow software emulator often shows "Pixel Launcher isn't responding".
# Hide system error dialogs so none land on the recording.
adb shell settings put global hide_error_dialogs 1 || true
adb shell settings put secure anr_show_background 0 || true
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null || true
# Show a dot wherever the test taps, so viewers can follow along.
adb shell settings put system show_touches 1 || true

# Software-rendered emulator: a smaller screen draws more frames per second.
adb shell wm size 720x1600
adb shell wm density 280

# Start recording when the test says the app is ready.
(
  adb logcat -v epoch -s flutter:I | while IFS= read -r line; do
    if [[ "$line" == *"MARK|start"* ]]; then
      adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null || true
      adb shell date +%s.%N > "$OUT/rec_t0.txt"
      adb shell screenrecord --size 720x1600 --bit-rate 6000000 --time-limit 180 /sdcard/demo.mp4 &
      echo "screen recording started"
      break
    fi
  done
) &

flutter drive --profile \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/demo_test.dart \
  --dart-define=DEMO_PACE="${DEMO_PACE:-1}" \
  -d emulator-5554
status=$?

adb shell pkill -INT screenrecord || true
sleep 5
adb pull /sdcard/demo.mp4 "$OUT/raw.mp4" || true
adb logcat -d -v epoch -s flutter:I > "$OUT/marks.log" || true
grep 'MARK|' "$OUT/marks.log" || true
ls -la "$OUT"
exit $status
