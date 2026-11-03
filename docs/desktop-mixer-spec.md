# Smixx desktop mixer — six-source pre-Send headphone revision

Status: implemented local prototype. Automated state, native Audio Unit signal, and in-process driver tests are recorded in `THREE-BUS-VERIFICATION.md`. Real Teams/OBS calls, hardware recovery, and long-duration drift checks remain acceptance gates.

This revision supersedes the prior four-output, headphone-mix, global-solo, mix-linking, and no-effects requirements. Provide six interchangeable source slots, Core Audio capture, application taps, device delivery, and background operation.

## Mixer controls

- Exactly three mixer outputs: **Smixx Bus 1**, **Smixx Bus 2**, **Smixx Bus 3**. The revised virtual driver exposes those three named duplex stereo devices, retaining the first three stable device UIDs. Intended new setup: Bus 1 Teams, Bus 2 OBS, Bus 3 spare; actual assignments remain in Setup. There is no direct streaming to YouTube/Facebook.
- Keep the top-left destination selector removed. Restore per-source, per-bus Send below M/S/E. Send and M are independent: Send controls outgoing inclusion; M temporarily silences that route. Neither affects headphones. The selected strip heading is `BUS 1`, `BUS 2`, or `BUS 3`; its endpoint and connection status appear underneath.
- A keyboard-accessible `1 | 2 | 3` segmented selector below the bus fader selects the editing context. It changes no routing values, endpoints, or headphone selection. All three buses run independently.
- Source buttons: **M S E**. M and S apply only to this source in the edited bus. Multiple solos are allowed; all selected solos being muted produces silence. Mute always wins, and solo never enables a route or alters levels. Solo selections are temporary and clear after restart.
- Bus buttons: **M E** only. Bus M silences only that bus's feed, including effect tails. There is no bus solo or mix-link control.
- E opens details; it does not toggle processing. Its enabled indicator reflects processing settings. Detailed panels identify shared source controls and bus-specific processing.
- Source assignment, input trim, EQ, compressor, custom name, and explicit global source mute are shared. Global mute remains available in source details and the menu bar; existing saved global mutes stay global.
- Empty slots produce silence. Assigning or replacing a source, channel, or capture mode disables Send in all three buses and clears that slot's bus solos before the new capture starts. Retain levels and global mute. A deliberate Send enable includes that route, subject to bus/global mute and feedback checks. New assignments are audible in headphones unless globally muted. Identical assignment/reconnection is not replacement.
- Legacy disabled routes retain disabled Send and bus mute with unchanged levels. Send and mute persist independently; solo remains transient.
- Source meters show the shared processed input before bus channel controls. Bus meters show the post-limiter signal. A separate held pre-limiter peak indicator warns at 0 dBFS; floating-point summing retains headroom instead of hard-clipping. Meter motion never proves Teams transmission or OBS recording.

## Headphone monitor

Headphones are a listening destination, not a fourth virtual driver output. The header selector chooses which bus’s channel fader balance to hear, independently of the editing selector. Each source splits after shared processing and its channel level, before Send and bus mute/solo. Global source mute still silences both paths. Headphones do not inherit bus compression, master level/mute, or limiting.

A dedicated headphone fader sits between source 6 and the bus strip. It controls only physical listening volume (-60 to 0 dB), with a dedicated mute and always-on Apple peak limiter. Setup chooses the physical endpoint. Headphones have an independent per-source ring consumer and physical callback; no outgoing endpoint needs to be running. Resampling and bounded drift correction remain. Disconnect preserves the saved endpoint without speaker fallback.

All mixer faders support 0.5 dB mouse-wheel/trackpad increments while hovered, in addition to dragging and numeric entry. Trackpad momentum is ignored. Input gain sits above source faders; Send below M/S/E, matching the row’s 85-point width, with no display-name entry. Remove redundant bus status and scope captions while preserving tooltips/accessibility. Getting started is the first Settings tab.

## Teams return and feedback

Teams microphone = Bus 1. Capture Teams using route playback to suppress duplicate direct playback. Teams return has Send off in Bus 1 but remains audible through the independent headphone mix. Mic, instruments and Safari have Send enabled as desired. Teams playback volume stays audible. The meeting-return identity guard continues to block enabling Teams Send to a meeting bus, even if temporarily muted.

Capture copy leaves original playback active; warn about duplicate headphone listening even when Send is off. Smixx does not change Teams device settings. Hardware loopback and unreported helper-process overlap cannot be reliably identified; no claim of complete feedback detection.

## Processing

Source capture → shared input trim → shared Apple N-band EQ → shared Apple Dynamics Processor → bus channel level → Send/mute/solo → floating-point summing → bus Dynamics Processor → bus master level → Apple Peak Limiter → output meter/delivery and headphone branch.

The existing engine uses direct Core Audio callbacks, not AVAudioEngine. Host Apple's `kAudioUnitSubType_NBandEQ` (the native AU EQ), `kAudioUnitSubType_DynamicsProcessor`, and `kAudioUnitSubType_PeakLimiter` in that path. Do not replace capture or routing solely to add effects.

- Optional shared EQ: high-pass 20–500 Hz, low shelf at 150 Hz, parametric mid at 1 kHz (one-octave bandwidth), high shelf at 6 kHz; each tonal gain -12 to +12 dB.
- Optional source/bus compression: threshold -60 to 0 dB, headroom 0.1–40 dB, attack 1–300 ms, release 10–3000 ms. Lower headroom increases compression. Expansion ratio stays 1 and makeup gain stays 0. No unsupported conventional ratio control.
- Independent final bus limiter: enabled by default, pre-gain -40 to 0 dB, release 1–40 ms. Fixed 2 ms attack/lookahead avoids latency jumps during edits. There is no true-peak claim or invented ceiling parameter. Bypass removes peak protection; the limiter cannot repair upstream distortion.
- Numeric fields, bypass, reset, voice EQ/compressor presets, and a limiter safeguard preset are available. EQ/compression default bypassed. The inspected parameter list does not provide usable compression-reduction metering; no simulated reduction meter is displayed.

Instantiate/configure/initialize/warm all AUs before starting their owning callback. Use planar stereo AU buffers and preallocated delay storage, with no callback heap allocation, logging, file access, or blocking synchronization. Prepare again when an owning endpoint's sample rate changes. Supported effect rates: 32–192 kHz; unsupported rates report a connection error.

Run effects continuously, including bypassed chains, to retain history. Smooth numeric targets over approximately 20 ms and crossfade bypass over 10 ms. Delay-match dry/wet paths: source and bus compressors each have a fixed 10 ms stage latency, including native AU latency/padding; limiter latency remains 2 ms. Source processing therefore adds 10 ms and bus processing adds 12 ms even while bypassed. Device/ring/driver buffering adds further latency; physical latency and multi-device drift require measurement. Stereo dynamics use one linked stereo unit, verified with asymmetric stereo test signals.

De-essing, multiband processing, automatic leveling, AUv3 hosting, and recording are outside scope.

## Persistence and migration

Persist version 3 state with six sources, three independent buses, levels/mutes, effects, stable endpoints, monitor bus/volume/mute/endpoint, editing selector, input-menu preferences, and window presentation. Apply saved mutes before device start. Hide/close retains background routing; explicit Quit stops it.

Before migrating version 1 or 2, validate its four-mix structure and write the untouched JSON to `configuration.v<old-version>-backup-<UUID>.json` beside the live file. If backup or migration fails, do not overwrite the original or start saved routes. Materialize each mix's effective linked sends before retaining the first three; this also preserves values inherited from a fourth-mix leader. Preserve levels, disabled routes, source global mutes, and endpoint identities. Rename bus labels and known first-three transport endpoint labels. A selected fourth editing context maps to Bus 3.

Version 2 migration appends an empty sixth source and disabled sixth Send to each bus, preserves all existing assignments/levels/mutes/effects, and mutes headphones until the user reviews the newly audible pre-Send mix. The fourth mix, original links, and original headphone mix from version 1 remain in the untouched backup. Monitoring starts unconfigured/muted because a former independent headphone mix cannot be represented faithfully by selecting one bus. Explain this change and the newly enabled peak limiters; report the exact backup path in the mixer/Diagnostics. Recovery: quit, retain the current v2 file, then restore the backup with the previous four-output app/driver. Do not pretend the old headphone balance was converted to a monitor bus.

## Verification and delivery

Run `scripts/test.sh`, `scripts/test-audio.sh`, `scripts/build-app.sh`, and driver build/contract tests. Verify editing/monitor isolation, bus/global control scope, replacement safeguards, all six slots, feedback/overlap checks, persistence, invalid settings, and migration with the fourth mix as a link leader.

Use generated real PCM through the actual native AUs to verify EQ attenuation, compressor/limiter level changes, stereo linkage, limiter transients, parameter/bypass transitions, bus independence, and pre-Send headphone summing at a different sample rate. Distinguish these from installed HAL/live-call evidence.

Inspect the native mixer, bus selector, monitor selector, source/bus effects panels, setup, and accessible control names. Deliver a local app/driver installer and verification report. Do not silently install the driver, restart Core Audio, or change meeting-device selections during build verification. Driver installation/restart is necessary for the operating system to replace the old four output names with three buses.

Outstanding live acceptance: six actual captures; simultaneous Teams/OBS; audible remote return without echo/duplicates; real headphone reconnect/sample-rate changes; hidden-window operation; restart/recovery; measured source-to-feed/headphone latency; 60-minute multi-device stability; actual recorded output inspection. Record hardware, OS/app versions, buffer sizes/rates, measurements, and remaining failures. Never mark these passed solely from unit tests or UI meters.

The mixer always uses the compact layout; saved expanded state is ignored. No expand/collapse toggle or diagnostic footer is shown. Migration notices, runtime messages, duplicate warnings and source connection details remain in Settings → Diagnostics. Legacy custom names remain in saved settings for compatibility.
