#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="dist/Smixx Desktop.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SmixxDesktop "$app/Contents/MacOS/SmixxDesktop"
cp scripts/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
printf 'Built: %s/%s\n' "$PWD" "$app"
