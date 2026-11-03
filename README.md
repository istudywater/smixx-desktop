> Six-source revision: headphones now hear the selected channel balance **before Send and bus M/S**. Source global mute remains shared. Use Teams route playback with Teams Send off in the meeting bus. The headphone fader and limiter are independent. Version 1/2 settings are backed up before migration; headphones start muted for balance review. See [revision verification](docs/SIX-SOURCE-VERIFICATION.md).

# Smixx Desktop

A native macOS mixer with six interchangeable source slots, **Smixx Bus 1–3**, and an independently selected headphone monitor. SwiftUI provides the mixer; Core Audio captures hardware and applications; Apple's native Audio Units provide EQ, compression, and peak limiting. The existing Smixx Audio driver provides three stereo application feeds.

This is a local prototype. Automated signal processing and driver-contract tests do not establish successful Teams calls or OBS recordings. See the [current specification](docs/desktop-mixer-spec.md), [architecture](docs/ARCHITECTURE.md), and [revision verification](docs/SIX-SOURCE-VERIFICATION.md).

## Build

Requires macOS 14.2+, Swift 6 tooling, and CMake for the driver. Builds/tests were run on Apple Silicon; Intel and minimum-OS verification remain pending.

```sh
scripts/test.sh
scripts/test-audio.sh
scripts/build-app.sh
scripts/build-driver.sh
scripts/build-installer.sh
```

The app and driver are ad-hoc signed for local development. `dist/Smixx-Prototype.pkg` is not notarized or intended for public distribution. Installation requires administrator access and restart. Merely opening the new app will not replace an installed four-device driver. Existing first-three device UIDs are retained.

Open `Package.swift` in Xcode to inspect the app. Run `.build/debug/SmixxDesktop --devices` for endpoint discovery. `--preview` runs a layout-only app with audio and configuration persistence disabled.

## Setup

1. In Setup → Outputs, assign bus endpoints. New setup uses Bus 1 for Teams' microphone, Bus 2 for OBS Audio Input Capture, and Bus 3 as a spare. Saved endpoint assignments survive migration.
2. Select a physical headphone device in the separate monitoring panel, choose the channel balance to hear, begin at a low listening volume, and unmute the monitor. Headphones work independently of outgoing bus endpoints.
3. Assign sources. Every new/replaced assignment starts with Send off in all buses and is audible in headphones. Enable intended Sends and unmute the outgoing bus. An existing global mute must also be cleared in source details.
4. Use `1 | 2 | 3` to edit a bus. The headphone selector in the header chooses what you hear independently. Source M/S affect only the edited bus; E opens shared source processing/details. The bus has M/E only.
5. Add Teams using route playback, keeping Teams Send off in Bus 1. Headphones hear Teams before Send; the other party hears only your intended sources. Use the headphone fader to adjust your listening volume without changing the call.

Capture copy retains ordinary app playback. Route playback explicitly suppresses it and requires confirmation; ensure the headphone balance has an audible level for that application. Smixx does not control Teams' speaker settings or OBS recording state. Avoid duplicate OBS microphone/desktop captures.

EQ and compression start bypassed; final bus peak limiters start enabled. Headphones have their own always-on limiter. E opens controls without changing bypass state. Numeric parameters, presets, reset, and bypass are available. No true-peak or simulated gain-reduction metering claims.

## Persistence and recovery

Closing the mixer keeps routing running. Quit explicitly to stop. Configuration is saved atomically at `~/Library/Application Support/SmixxDesktop/configuration.json`.

The first load of four-output settings writes an untouched, uniquely named v1 backup beside that file. The first three effective mixes become independent buses; disabled sends become bus mutes, and global mutes/levels/endpoints remain intact. The fourth mix is recoverable from the backup, whose exact path is shown in Diagnostics. Headphone monitoring starts unconfigured because an old independent headphone mix cannot be faithfully converted to a bus selector. Temporary solos clear on restart.

To recover the old four-mix setup, quit, preserve the new v3 configuration, and use the untouched backup with the prior four-output app/driver. Invalid settings are preserved and reported rather than overwritten.

## Limits

- Device PCM must be float32; output is stereo channels 1–2. Effects accept 32–192 kHz.
- Buses and monitor require distinct endpoints. Existing bounded resampling/drift handling is retained; physical latency and long-session stability need device testing.
- Capture permissions, application helper-process compatibility, reconnect, sleep/wake, and simultaneous live Teams/OBS remain hardware acceptance gates.
- No system-wide capture source, AUv3 hosting, MIDI, recorder, automatic leveling, call control, or direct social-network streaming.
- The Smixx driver retains its existing libASPL dependency and licensing notices; this revision adds no third-party dependency.
