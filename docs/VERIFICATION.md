Current three-bus revision: see [THREE-BUS-VERIFICATION.md](THREE-BUS-VERIFICATION.md). The records below are historical and do not establish acceptance of the revised engine.

# First-build verification

Local native-only prototype, October 30, 2026 (America/Chicago). This record distinguishes implementation from observed operation.

## Passed

- Debug build using Swift 6.2.4 Command Line Tools on Apple Silicon.
- Optimized release build and local app packaging through `scripts/build-app.sh`.
- Ad-hoc app signature: `codesign --verify --deep --strict`.
- Bundle property-list validation with `plutil -lint`.
- Actual Core Audio device/process enumeration with `SmixxDesktop --devices`. Physical microphones, Anker stereo output, built-in speakers and other installed endpoints were enumerated. No BlackHole endpoint was present.
- All 16 automated tests through `scripts/test.sh`: fresh-state silence; five interchangeable slots; global mute; send isolation; pending solo and unmute; intersecting multiple source/output solos; source replacement; linked mixes and independent masters; cycle/chain rejection; persistence and solo clearing; invalid-state rejection; feedback risk propagation; selection isolation; duplicate-output rejection; outgoing-loopback isolation; app-playback-mode persistence; atomic settings-file handling; and five-input DSP mixing, independent output signals and immediate mute. Several behaviors share a test case.

## Not yet verified

- Visual layout, complete keyboard/accessibility operation, long-name behavior and compact/expanded transitions. The app was launched, but UI inspection was interrupted during a computer-use tool call.
- Actual microphone/interface capture through the app, app process-tap permissions, sustained audio delivery to physical headphones, and app original-playback suppression/restoration.
- Five live sources simultaneously, multiple physical device clocks, mono/stereo channel mapping on real interfaces, supported format failures, and sample-rate change recovery.
- Device disconnect/reconnect, app relaunch, sleep/wake, permission revocation/restoration, hidden-window routing and menu-bar actions during active audio.
- End-to-end Teams and OBS delivery. This build does not expose a virtual microphone and includes no driver. A moving meter is not evidence of those integrations.
- Measured monitoring latency, recording synchronization, Intel compatibility, minimum-supported-macOS compatibility, or a 60-minute live-session soak.
- Developer ID signing, notarization, clean-machine installation or public distribution.

## Next native-audio checks

1. Start with headphones at low volume. Select one physical source, then allow microphone capture. Confirm source activity while the source remains globally muted.
2. Assign the physical headphone endpoint, enable only the intended send, and deliberately unmute the source/output. Verify physical output, numeric levels, mute, solo, and selected-output isolation.
3. Add each supported source type in every slot. For applications, compare capture-copy and route-playback behavior, including restoring original playback when the tap stops. Record actual app/process identities and permissions.
4. Test distinct output mixes with identifiable signals. Test linked mixes, cancellation of feedback warnings, source replacement without a transient leak, and output replacement starting muted.
5. Exercise the recovery and background cases above. Record every audible interruption and whether the UI reports it accurately.
6. Choose explicit latency/dropout/drift acceptance targets on a named reference setup before a performance gate can pass. Record device UIDs, OS/app versions, input/output formats, sample rates, callback sizes, run duration and measured values. Run the 60-minute soak specified in the product spec.

Use the full test matrix in `desktop-mixer-spec.md` for eventual meeting/recording integration. Do not substitute these deterministic tests for real-call or recording evidence.
