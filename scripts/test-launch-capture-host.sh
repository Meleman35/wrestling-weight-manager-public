#!/bin/bash
set -euo pipefail
test_root="$(mktemp -d /tmp/remote-session-ui.XXXXXX)"
test_app="$test_root/RemoteSessionUITests.app"
mkdir -p "$test_app"
sdk_path="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun swiftc -D DEBUG -D REMOTE_SCALE_UI_TESTS -sdk "$sdk_path" \
  -target arm64-apple-ios17.6-simulator -swift-version 5 -warnings-as-errors \
  native-candidate/WrestlingManagerRemote*.swift \
  tests/launch-capture-host-ui.swift -o "$test_app/RemoteSessionUITests"
cat > "$test_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.launch-capture-host.ui-tests</string>
<key>CFBundleExecutable</key><string>RemoteSessionUITests</string>
<key>CFBundleName</key><string>Remote Session UI Tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.6</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict></plist>
PLIST
codesign --force --sign - "$test_app"
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
  SIMCTL_CHILD_REMOTE_NFC_SIMULATION="$simulated" xcrun simctl launch "$test_device" app.launch-capture-host.ui-tests
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
