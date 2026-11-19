#!/usr/bin/env bash
# Runs integration_test/features_test.dart on the Android emulator, plus the
# two checks a test inside the app can't do on its own:
# - share text into the app from outside (like Netflix or a browser would);
# - "Hide in recent apps" really sets FLAG_SECURE on the app's window.
set -uo pipefail
adb shell settings put global hide_error_dialogs 1 || true
# A freshly booted emulator can report "booted" before it can install apps
# (an install then hangs). Wait until the package manager answers.
for _ in $(seq 1 90); do
  adb shell pm path android 2>/dev/null | grep -q package: && break
  sleep 2
done
adb logcat -c

(
  adb logcat -v brief -s flutter:I | while IFS= read -r line; do
    if [[ "$line" == *"FEATURES|share-ready"* ]]; then
      sleep 2
      adb shell am start -a android.intent.action.SEND -t text/plain \
        --es android.intent.extra.TEXT "'Shared From Another App (2001)'" \
        -n app.watchedledger/.MainActivity
      echo "Shared text into the app."
      break
    fi
  done
) &
sharer=$!

# Never hang the whole job: a stuck install or app gets 30 minutes.
timeout 1800 flutter drive --keep-app-running \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/features_test.dart \
  -d emulator-5554
status=$?
kill "$sharer" 2>/dev/null || true

if [ $status -eq 0 ]; then
  sleep 2
  if adb shell dumpsys window windows | awk '
      /Window #/ { inapp = /app\.watchedledger/ }
      inapp && /SECURE/ { found = 1 }
      END { exit !found }'; then
    echo "Hide in recent apps: FLAG_SECURE is set on the app's window."
  else
    echo "::error::Hide in recent apps is on, but the app's window is not FLAG_SECURE."
    adb shell dumpsys window windows | grep -B2 -A12 watchedledger | head -60
    status=1
  fi
fi
adb uninstall app.watchedledger >/dev/null 2>&1 || true
exit $status
