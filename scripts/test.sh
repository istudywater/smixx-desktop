#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# CLT ships Swift Testing but some versions omit its Foundation overlay.
# Full Xcode installations use their normal SwiftPM test configuration.
developer_dir="$(xcode-select -p)"
if [[ "$developer_dir" == *CommandLineTools* ]]; then
  frameworks="$developer_dir/Library/Developer/Frameworks"
  swift test --disable-xctest --enable-swift-testing \
    -Xswiftc "-F$frameworks" \
    -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
    -Xlinker "-F$frameworks" -Xlinker -rpath -Xlinker "$frameworks" "$@"
else
  swift test --disable-xctest --enable-swift-testing "$@"
fi
