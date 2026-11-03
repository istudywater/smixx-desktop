#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
clang -std=c11 -O2 -I Sources/MixerDSP/include Tests/Audio/EffectsTests.c Sources/MixerDSP/MixerDSP.c Sources/MixerDSP/SMEffects.c -framework CoreAudio -framework AudioToolbox -o .build/effects-tests
.build/effects-tests
