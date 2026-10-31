#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cmake -S Driver -B .build/driver -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_SYSROOT="$(xcrun --show-sdk-path)" ${SMIXX_ARCHS:+-DCMAKE_OSX_ARCHITECTURES="$SMIXX_ARCHS"}
cmake --build .build/driver -j 4
ctest --test-dir .build/driver --output-on-failure
bundle=".build/driver/SmixxAudio.driver"
mkdir -p "$bundle/Contents/Resources/libASPL"
cp Driver/ThirdParty/libASPL/LICENSE* Driver/ThirdParty/libASPL/AUTHORS.md Driver/ThirdParty/libASPL/REVISION "$bundle/Contents/Resources/libASPL/"
codesign --force --sign "${SMIXX_SIGN_ID:--}" "$bundle"
codesign --verify --strict "$bundle"
mkdir -p dist
ditto "$bundle" dist/SmixxAudio.driver
