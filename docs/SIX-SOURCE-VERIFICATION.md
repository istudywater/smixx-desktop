# Six-source / pre-Send headphone revision

Verified locally on Apple Silicon, November 2, 2026.

## Implemented

- Six interchangeable sources with preserved existing assignments.
- Independent persisted Send and bus mute; solo is transient and bus-specific.
- Headphones sum the selected channel balance before Send/M/S and outgoing master/effects, using independent source rings and physical callback clock. Global source mute still applies.
- Independent headphone gain/mute and always-on peak limiter, with a visible limiter indicator.
- Headphone strip between source 6 and bus; input trim above each source fader; display name and Send below M/S/E. Redundant status/scope captions removed.
- Mouse wheel/trackpad control for all mixer faders, 0.5 dB increments, bounded ranges, no momentum changes.
- Getting started first in Settings, with revised Teams routing guidance.
- Version 1/2 migration backs up untouched JSON, preserves outgoing feeds, appends an empty sixth slot, and starts headphones muted for review of newly audible sources.

## Passed

- 14 Swift state tests: Send/mute/solo isolation, pre-Send headphone eligibility, global mute, empty slots, feedback guards, persistence, invalid-state handling, and v1/v2 migration with byte-identical backups.
- Native Audio Unit tests at 44.1/48/96 kHz: EQ, compression, stereo linkage, limiter and transition behavior.
- Actual mixer PCM: source 6 excluded from the outgoing feed but present in headphones, 48 kHz source/44.1 kHz headphones, continued headphone playback without outgoing callbacks, and independent mute/tail suppression.
- Release app build and strict code-signature verification (local ad-hoc signing).
- Driver build and both timeline/driver-contract tests. Local installer built and payload inspected.
- Native audio-disabled UI preview: six strips, correct headphone placement, moved gain/Send controls, removed captions, readable layout at 1120×700, first Settings tab and updated guidance. Scroll actions visibly changed input gain, source 6, bus, and headphone values; headphone value stopped at 0 dB.

## Remaining launch acceptance

Live AudioBox GO + Teams call: remote participants hear mic/instruments/Safari without hearing their own return, while headphones hear all intended sources. Check microphone monitoring latency/direct-monitor duplication, reconnect, sleep/wake, six simultaneous captures, long-session clock stability, and OBS if used. No live call or hardware-loop test was performed in this revision. Public release still needs distribution signing/notarization and minimum-OS/Intel verification. The installer is a local prototype artifact; no driver installation or Core Audio restart was performed.

## Compact interface polish

Removed expansion toggle and alternate layout, removed display-name entry, widened Send to fill each source strip, and moved footer messages exclusively to Diagnostics. Native preview visually verified all four changes and diagnostic message access. Release app/installer rebuilt; driver contract tests and signature verification passed. Audio routing was unchanged.
