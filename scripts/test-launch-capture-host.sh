#!/bin/bash
set -euo pipefail
test_root="$(mktemp -d /tmp/remote-session-ui.XXXXXX)"
# Xcode emits the simulator's embedded entitlements as well as its signature.
# Keep the real Keychain-backed queue in this test; never substitute a memory key.
python3 scripts/prepare-launch-capture-test.py "$test_root"
xcodebuild -project "$test_root/LaunchCaptureHost.xcodeproj" -target RemoteSessionUITests \
  -configuration Debug -sdk iphonesimulator -arch arm64 \
  SYMROOT="$test_root/build" CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build -quiet
test_app="$test_root/build/Debug-iphonesimulator/RemoteSessionUITests.app"
xcrun simctl list devices available --json > "$test_root/devices.json"
test_device="$(python3 - "$test_root/devices.json" <<'PY'
import json,sys
devices=json.load(open(sys.argv[1]))['devices']
for runtime, rows in devices.items():
    if 'iOS' in runtime:
        for row in rows:
            if 'iPad' in row['name']:
                print(row['udid']);sys.exit(0)
raise SystemExit('No iPad simulator available')
PY
)"
xcrun simctl boot "$test_device" || true
xcrun simctl bootstatus "$test_device" -b
xcrun simctl install "$test_device" "$test_app"
test_container="$(xcrun simctl get_app_container "$test_device" app.launch-capture-host.ui-tests data)"
for simulated in 0; do
  rm -f "$test_container/Documents/result.txt"
  if ! xcrun simctl launch "$test_device" app.launch-capture-host.ui-tests; then
    xcrun simctl spawn "$test_device" log show --last 2m --style compact \
      --predicate 'process == "runningboardd" OR process == "amfid"' | tail -80
    exit 1
  fi
  test_finished=0
  for attempt in $(seq 1 60); do
    if [ -f "$test_container/Documents/result.txt" ]; then
      cat "$test_container/Documents/result.txt"
      python3 - "$test_container/Documents/result.txt" <<'CHECK'
import sys
assert open(sys.argv[1]).read().startswith('PASS:'), 'Device UI regression failed'
CHECK
      test_finished=1
      break
    fi
    sleep 1
  done
  if [ "$test_finished" -ne 1 ]; then
    echo 'Timed out waiting for device UI regression results'
    exit 1
  fi
  xcrun simctl terminate "$test_device" app.launch-capture-host.ui-tests
done
