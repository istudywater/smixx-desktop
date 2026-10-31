# Smixx Desktop prototype architecture

Target: a working local macOS prototype by Sunday, November 1, 2026. This is a development target, not a claim that the real-call gate has passed.

Smixx Desktop serves music educators and video-call users. Smixx Mobile serves live musicians and keyboardists in its separate repository. Mobile's eight-channel AUv3 host is not the desktop architecture.

## Current first-build decision

The user superseded the preferred-BlackHole prototype direction: build with native Apple audio APIs and no BlackHole driver dependency or bundled code. Keep the existing native capture/output adapters and routing model. Physical output and app-capture functionality are the first-build scope. A virtual Teams microphone and independent OBS feed are not provided by this build.

Apple frameworks used: Core Audio for device/process discovery, process taps, callbacks and output; AVFoundation for microphone permission; SwiftUI/AppKit for the interface. The small C DSP layer implements the five-by-four mixing/buffering path. No third-party package is linked. Native framework use does not mean a virtual microphone exists automatically.

## Earlier transport investigation (deferred)

The earlier proposal was to use a separately installed, unmodified BlackHole driver as transport; that is not required for this first build. Smixx does not include a driver, fork or copy BlackHole, or install it. The existing repository contained only LICENSE before this implementation. The new engine already writes standard Core Audio output endpoints; retain that adapter for BlackHole rather than replacing it.

Deferred arrangement, not installed or validated:

| Path | Endpoint / channels | Consumer |
| --- | --- | --- |
| Meeting mix | BlackHole 2ch, output 1–2 | Teams microphone: BlackHole 2ch |
| Headphone mix | Physical headphone/interface output 1–2 | User |
| Recording mix | Separate BlackHole 16ch, output 1–2; other channels silent | OBS Audio Input Capture: BlackHole 16ch |
| Teams return | Core Audio process tap of Teams output | Smixx source slot, enabled in headphones and recording only |
| Fourth mix | Distinct user-selected output | User-configured |

This deliberately uses separate device UIDs; it does not assume Teams or OBS can choose arbitrary channel pairs from one multichannel device. OBS's treatment of a 16-channel input must be tested on the installed OBS version before declaring milestone two complete. If it fails, a different separately installed compatible endpoint is needed; do not fork a driver to solve it this weekend.

Do not assign either outgoing BlackHole endpoint as a Smixx source. Do not set macOS system output to either outgoing feed. Teams speakers must remain separate from its BlackHole microphone. App source dropdowns distinguish “capture copy” from “route playback.” Route playback explicitly uses Apple’s `mutedWhenTapped` behavior, suppressing the app’s original hardware playback while its tap is read. The user confirms this before activation; this is required for independent Teams-return monitoring without duplication. Copy mode leaves original playback intact and may double monitoring. Validate suppression and restoration on the actual Teams build. No macOS default-device change is made.

## Implementation boundaries

- `SmixxCore`: five interchangeable source slots, four independent mixes, global source gain/mute/solo, per-mix sends, output controls, one-level links, feedback checks, versioned atomic persistence.
- `AudioHardware`: discovery by stable UID, hardware mono/stereo channel capture, isolated application process taps on macOS 14.2+, output endpoint adapters. Private aggregate devices host app taps; they are capture adapters, not virtual drivers exposed to Teams.
- `MixerDSP`: preallocated single-producer/single-consumer rings for every source/output pair, stereo mixing, immediate mute, gain smoothing, peak meters, and bounded linear resampling with small clock-drift correction. No allocation, file access, discovery, or UI work in callbacks. This resampler is prototype infrastructure and requires latency, quality and drift validation; it is not yet a proven production engine.
- `MixerStore`: endpoint lifecycle, persisted state, meter polling, connection status. UI never infers an active call or OBS recording from signal activity.

Supported in code: physical Core Audio float32 PCM input channels (mono or adjacent stereo pair), application audio process taps, stereo output on channels 1–2 of distinct endpoints. Unsupported: AUv3 hosting, MIDI, internal recording, arbitrary output pair selection, direct Teams call control, automatic meeting detection, custom drivers, and a system-wide capture source. Hardware/application capture remains subject to permissions and real-device testing.

## Evidence and sources

Inventory on October 30, 2026 (America/Chicago): `/Library/Audio/Plug-Ins/HAL` contains Teams, Parrot, and TVRemote drivers; BlackHole is absent. No equivalent installed transport has been verified. Real BlackHole/Teams and OBS gates are blocked pending separate driver installation and interactive audio testing.

Primary references consulted:
- [Apple: capturing system audio with Core Audio taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps)
- [BlackHole official repository and installation instructions](https://github.com/ExistentialAudio/BlackHole)
- [BlackHole: using it as a virtual microphone](https://github.com/ExistentialAudio/BlackHole/wiki/Use-BlackHole-as-a-Virtual-Microphone)

No BlackHole code is linked, copied, or bundled. Preserve the repository's existing LICENSE. Third-party drivers retain their own licenses.

Reference inspection: the user-provided `/Users/bryanbsmith/Downloads/BlackHole-master` contains source and an Xcode project, not a built installer. Its channel-specific UID definitions confirm that stock variants can be represented as distinct endpoints. No source from that tree was copied.
