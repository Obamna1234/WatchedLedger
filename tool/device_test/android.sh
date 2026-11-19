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
# The old Android 24 emulator sometimes hangs for good during the install
# that `flutter drive` does. Build and install it ourselves instead, with the
# install verifier off, a time limit and a second try.
adb shell settings put global verifier_verify_adb_installs 0 || true
adb shell settings put global package_verifier_enable 0 || true
flutter build apk --debug --target=integration_test/features_test.dart || exit 1
apk=build/app/outputs/flutter-apk/app-debug.apk
installed=0
for attempt in 1 2 3; do
  if timeout 300 adb install -r -t "$apk"; then installed=1; break; fi
  echo "Install attempt $attempt did not finish; restarting adb and trying again."
  adb kill-server || true; adb start-server || true; adb wait-for-device
done
[ $installed -eq 1 ] || { echo "::error::Could not install the app on the emulator."; exit 1; }
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
  --use-application-binary="$apk" \
  -d emulator-5554
status=$?
kill "$sharer" 2>/dev/null || true

if [ $status -eq 0 ]; then
  sleep 2
  # Newer Android prints the flag by name (SECURE); Android 7 prints all the
  # flags as one number (fl=#81812100), where FLAG_SECURE is 0x2000.
  win="$(adb shell dumpsys window windows | awk '
      /Window #/ { inapp = /app\.watchedledger/ }
      inapp { print }')"
  hex="$(printf '%s\n' "$win" | grep -o 'fl=#[0-9a-fA-F]*' | head -1 | cut -c5-)"
  if printf '%s\n' "$win" | grep -q SECURE ||
     { [ -n "$hex" ] && [ $(( 16#$hex & 0x2000 )) -ne 0 ]; }; then
    echo "Hide in recent apps: FLAG_SECURE is set on the app's window."
  else
    echo "::error::Hide in recent apps is on, but the app's window is not FLAG_SECURE."
    adb shell dumpsys window windows | grep -B2 -A12 watchedledger | head -60
    status=1
  fi
fi
adb uninstall app.watchedledger >/dev/null 2>&1 || true
exit $status
