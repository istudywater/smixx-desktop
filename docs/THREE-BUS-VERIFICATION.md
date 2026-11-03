# Three-bus revision verification

Local revision: 0.4.0. Work date: November 2, 2026 (America/Chicago). Environment reported by the build host: macOS 27.0.1 (26A434), arm64; Apple Swift 6.2.4 / Swift driver 1.127.15. Native Apple Audio Units; no new external dependency. The existing driver/libASPL transport and branding are retained.

## Results

| Check | Result | Evidence / boundary |
| --- | --- | --- |
| Routing/state/persistence/migration | PASS | `scripts/test.sh`: 12 Swift Testing tests. Three buses/five slots; editing and monitor independence; per-bus multiple/pending solos and mute precedence; global mute; silent empty/replacement slots; stable levels; feedback/overlap checks; endpoint conflicts; effects and monitor persistence; invalid/corrupt settings; original four-mix backup and fourth-leader materialization. |
| Actual native AU signal processing | PASS | `scripts/test-audio.sh`, C harness invoking production `SMEffects` and `MixerDSP`. 256-frame blocks at 44.1/48/96 kHz; planar stereo AUs; five generated sources and separate headphone clock. No simulated effects. |
| Saved input trim from first sample | PASS | With saved gain 0.01 and input 0.4, processed source peak stays ≤0.00401; no startup ramp from unity. |
| EQ attenuation | PASS | At 48 kHz, 30 Hz / 0.5-amplitude input RMS changes from 0.353754 to 0.014143 with a 150 Hz high-pass. |
| Compressor behavior | PASS | At 48 kHz, 1 kHz / 0.8 input RMS changes from 0.565685 bypassed to 0.061016 with -30 dB threshold / 5 dB headroom. No makeup gain. |
| Peak limiter behavior | PASS | At 48 kHz, 1 kHz / 2.0 input yields peak 0.926836. A 4.0-amplitude impulse produces peak 0.860206. This is sample-peak evidence, not true-peak certification. |
| Stereo linkage | PASS | Right signal = 0.25 × left; EQ/compressor/limiter output preserves that ratio within 0.0001 for tested signals/rates. |
| Bypass and parameter transitions | PASS for harness | Maximum adjacent-sample jump 0.005550 on the 100 Hz / 0.4 test with EQ/compressor enable, bypass, and parameter edits, under the 0.03 test bound. No AU render/parameter errors. This is not an exhaustive perceptual click test on all material/devices. |
| Bus/headphone isolation | PASS for harness | Five DC source levels sum to 0.3 in Bus 1 and 0.01 in the other test buses. Monitoring Bus 1 at 0.25 volume yields 0.075; selecting Bus 2 at 0.5 volume yields 0.005 while Bus 1 remains 0.3. A 44.1 kHz monitor reads a 48 kHz bus in the harness. Bus master mute silences delayed tails. |
| Driver identities and transport | PASS in-process | `scripts/build-driver.sh`: both timeline and driver-contract tests pass. Exactly three duplex stereo 48 kHz devices named Smixx Bus 1–3, stable UIDs, producer filtering, multiple readers, and silence after supplied frames end. |
| Native UI | PASS for inspected layouts | Isolated preview (audio/persistence disabled): five strips, M/S/E and bus M/E, active-state styling, independent headphone selector, bus selector with no adjacent visible label, one top-right Settings entry. Source and bus effects sheets inspected. |
| Settings navigation regression | PASS | Replaced collapsing native TabView labels with four explicit equal-width controls. Inputs, Outputs, Getting started, and Diagnostics all visibly render and open. Headphone device/volume and three bus destinations are in Outputs. |
| Release app / installer build | PASS | `scripts/build-app.sh` and `scripts/build-installer.sh`; version 0.4.0 app, revised driver, icon/license resources, local installer. Payload expanded for inspection; no install or Core Audio restart performed. |
| Installed driver / real call / recording | NOT RUN | The running system driver was not replaced. In-process tests do not prove installed HAL delivery, a Teams call, OBS consumption, or recording success. |
| Hardware capture/reconnect/rate changes | NOT RUN live | Connection lifecycle code retains the existing device handling and prepares AUs at actual format rate; physical five-source capture, Bluetooth disconnect/reconnect, sleep/wake, and permission recovery still need tests. |
| Long-session drift / physical latency | NOT RUN | No 60-minute Teams/OBS test or source-to-headphone/feed latency measurement. Numeric physical-latency acceptance limits remain open pending a named device setup. |

Raw results: [state tests](verification/three-bus-state.txt), [native audio signal tests](verification/three-bus-audio.txt), [release/driver/package build](verification/three-bus-build.txt).

## Header monitor layout follow-up

Moved the headphone bus selector into the top-right header immediately left of Settings. Removed the lower monitor box and its settings shortcut; device, volume, and mute remain in Settings → Outputs. Compact faders now use the reclaimed height, while expanded mode retains room for input controls. Audio routing and monitor-selection behavior are unchanged. Native preview checks passed for compact and expanded layouts; selecting monitor Bus 3 left editing Bus 1 unchanged. Release build and installer were refreshed.

## Parameter and latency inspection

The installed Apple AU parameter lists were queried directly before UI design. Compressor ranges: threshold -100…20 dB, headroom 0.1…40 dB, attack 0.001…0.3 s, release 0.01…3 s, expansion ratio 1…50, master gain -40…40 dB. The UI deliberately offers narrower threshold range, disables expansion, and fixes makeup gain at zero. No conventional ratio or gain-reduction meter is invented.

Limiter ranges: attack 0.0005…0.03 s, release 0.001…0.04 s, pre-gain -40…40 dB. Inspection confirmed attack changes reported latency. This revision fixes attack at 0.002 s and exposes release plus non-positive pre-gain. Defaults are enabled with 0 dB pre-gain and 5 ms release.

Native units accepted non-interleaved stereo float32; interleaved format was rejected and is not used for AU hosting. Capture/delivery still accept the adapter's existing PCM buffer layouts. Dry/wet delay compensation adds fixed 10 ms source compression stage plus 10 ms bus compression stage and 2 ms limiter. Device, driver, ring and monitor buffering add further latency. Stereo and DSP tests above are offline signal evidence, not physical latency measurements.

## Migration and recovery

The untouched original configuration is backed up next to `~/Library/Application Support/SmixxDesktop/configuration.json` as `configuration.v1-backup-<UUID>.json` before writing version 2. The exact path is reported in the mixer and Diagnostics. Tests compare the backup byte-for-byte with the original.

The first three mixes retain effective levels/exclusions and global source mutes. Links are resolved before removal of the fourth active mix. The fourth mix and old links remain in the backup. The old independent headphone mix is not automatically converted; the new monitor starts unconfigured/muted. The migration notice explains this and the newly enabled final limiters.

Recovery requires quitting, preserving the new v2 file, and using the backup with the previous four-output app/driver. Source replacements and changed headphone endpoints start muted; saved reconnects preserve their settings. Driver installation requires administrator access and restart, and is intentionally separate from this build work.

## Remaining live acceptance procedure

1. Install the 0.4.0 local package and restart at a suitable time. Confirm exactly three Smixx Bus devices in Audio MIDI Setup; record the installed device UIDs and rate/buffer settings.
2. Configure five actual supported captures, Bus 1 → Teams microphone, Bus 2 → OBS input capture, and physical headphone monitoring. Record hardware, macOS, Teams and OBS versions.
3. Set Teams speakers directly to headphones for the default return arrangement. Confirm outgoing mix plus remote participants are heard once, with no return sent to callers. If monitoring the OBS mix includes Teams return, avoid duplicate direct playback as explained by the warning/setup guide.
4. Confirm bus faders/mutes/solos and monitor selection/volume are isolated during a real call; start/stop OBS and inspect its actual recording.
5. Exercise effects bypass/edits on representative material, headphone disconnect/reconnect, sample-rate changes, hide/reopen, restart, sleep/wake and permission recovery. Record any glitches and AU/underrun counters.
6. Measure physical monitoring/feed latency and run at least 60 minutes with identifiable signals. Establish numeric limits for the named setup; document drift, dropouts, CPU/memory and audio evidence before declaring live acceptance complete.
