# Smixx Desktop

A native macOS mixer for music educators and video-call users, part of The Smixx Project. Five interchangeable vertical channel strips feed four independently configurable output mixes, with a separate vertical master strip on the right. Smixx Mobile is a separate iPad instrument-hosting product.

**Local prototype, not a validated meeting router yet.** This build uses Apple frameworks and includes no third-party packages, BlackHole code, audio driver, or driver installer. It can capture supported hardware/app audio and write existing Core Audio outputs. It does not create a microphone device that Teams can select. End-to-end Teams and OBS integration remains unverified and requires an external audio transport or a future native integration.

## Build and run

Requires macOS 14.2 or later and Swift 6 tooling (Xcode or Command Line Tools). The local build was compiled on Apple Silicon; Intel and the minimum macOS version have not been tested.

```sh
./scripts/build-app.sh
open "dist/Smixx Desktop.app"
```

Open `Package.swift` in Xcode to browse and build the package. Use the bundled app from `build-app.sh` for audio-permission testing: it includes microphone and system-audio usage descriptions and a stable bundle identifier. The app is ad-hoc signed for local development, not notarized or intended for distribution.

```sh
./scripts/test.sh
.build/debug/SmixxDesktop --devices
```

The test script includes a workaround for incomplete Swift Testing support in some Command Line Tools installations. It does not install or modify developer tools.

## First session

1. Open Setup → Outputs and choose physical headphones or an audio interface for the Headphones mix. The prototype uses output channels 1–2.
2. Select any supported source in any of the five dropdowns. Hardware choices include individual mono channels and adjacent stereo pairs. Applications appear when Core Audio exposes their audio processes.
3. Select Headphones in the destination selector. All five Send checkboxes start on in each new mix; turn off any sources you want excluded. Existing configurations keep their saved Send settings. Source replacement starts globally muted; unmute the source and the headphone output deliberately, with low levels first.
4. `M` and `S` affect the source in every mix. A send checkbox affects only the selected mix. Mute overrides solo; a muted solo selection is pending. Multiple source/output solos are supported.
5. Expand for global input gain, custom source names, output solo, and mix linking. A follower shares its leader’s sends but retains its own output/master controls.

**Application capture modes:** “capture copy” leaves ordinary application playback intact. “route playback” asks for confirmation and suppresses that original playback while Smixx reads the app tap, so headphone monitoring can pass only through Smixx. This uses Apple's Core Audio tap mute behavior. Selecting route playback initially mutes the source: configure its sends and unmute it to hear it. Quit Smixx to stop the tap and restore ordinary playback. Compatibility and restoration must be checked per app, particularly apps with helper audio processes.

The app requests macOS capture permissions only after you select a source. Denied permission/device errors appear in Diagnostics. Silence is not treated as disconnection. “Endpoint receiving” means output callbacks are running, not that a meeting participant hears audio or OBS is recording.

Closing the mixer keeps audio running. Reopen it from the menu-bar waveform icon. Quit explicitly to stop. Settings are saved atomically in `~/Library/Application Support/SmixxDesktop/configuration.json`; mutes restore before routes, temporary solos do not restore. An invalid settings file is preserved until the user chooses to back it up and reset.

## Current boundaries

- All five source slots and all four mixes are implemented; there are no microphone-reserved slots.
- Physical inputs and application process taps use native Core Audio. App taps require macOS 14.2+ and capture permission.
- Outputs must be distinct, existing stereo-capable endpoints. No automatic system-device changes, virtual-device creation, driver installation, or arbitrary output-pair selection.
- Device formats must be 32-bit float PCM. Unsupported formats are reported instead of reconfiguring the user's devices.
- No AUv3 hosting, MIDI, effects, recording, call control, or meeting detection.
- Prototype clock buffering/resampling, live capture compatibility, physical monitoring latency, sleep/wake, long-session stability, Teams and OBS workflows still need hardware validation. Automated DSP tests do not establish those results.

See [architecture](docs/ARCHITECTURE.md), [verification record](docs/VERIFICATION.md), and the detailed [product specification](docs/desktop-mixer-spec.md). The latest native-only first-build decision supersedes the earlier preferred-BlackHole transport direction; meeting/recording integration remains a later verification gate.
