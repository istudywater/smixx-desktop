#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S Driver -B .build/driver -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)"
cmake --build .build/driver --target SmixxTransportProbe -j 4
for role in producer observer; do
  bundle=".build/Smixx-$role.app"
  mkdir -p "$bundle/Contents/MacOS"
  cp .build/driver/SmixxTransportProbe "$bundle/Contents/MacOS/SmixxTransportProbe"
  if [[ "$role" == producer ]]; then bundle_id=org.smixx.transport-probe; else bundle_id=org.smixx.transport-observer; fi
  cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0"?><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleExecutable</key><string>SmixxTransportProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSMicrophoneUsageDescription</key><string>Read the Smixx virtual feeds to verify actual mixed audio delivery and silence.</string>
</dict></plist>
PLIST
  codesign --force --sign - "$bundle"
done
mkdir -p .build/transport-evidence
# Run only after installing the driver. This never installs/restarts anything.
# Optional first argument is a physical monitor UID; otherwise no speaker output.
.build/Smixx-observer.app/Contents/MacOS/SmixxTransportProbe --read .build/transport-evidence/readback > .build/transport-evidence/observer.log 2>&1 &
observer=$!
trap 'kill "$observer" 2>/dev/null || true' EXIT
sleep 1
.build/Smixx-producer.app/Contents/MacOS/SmixxTransportProbe --write "$@" > .build/transport-evidence/producer.log 2>&1
status=0
wait "$observer" || status=$?
cat .build/transport-evidence/producer.log .build/transport-evidence/observer.log
exit "$status"
