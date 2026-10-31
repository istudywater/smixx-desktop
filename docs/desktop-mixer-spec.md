# Smixx desktop mixer specification

Status: implementation specification, based on the supplied mixer sketch and review.

First-build scope update: use native Apple audio APIs without BlackHole code, bundled drivers, or installers. Build the five-source/four-mix controls, hardware/application capture, physical outputs, and persistence. Teams/OBS virtual-feed integration remains unverified and deferred until a supported transport is available. This update supersedes earlier transport preferences, not the long-term teaching workflow.

## Purpose

Build a small desktop audio routing utility for people using video calls. Users configure their routing, confirm that audio is working, and return to their meeting. Optimize for a small window, clear destinations, persistent settings, and reliable background operation.

This document specifies product behavior. Inspect the existing application and audio engine before choosing implementation details. Preserve working routing capabilities. Do not represent unsupported audio features as working controls.

## Scope and priorities

- Keep all five configurable source slots in the first version; do not reduce the source count for an initial milestone. Support four output mixes, matching the supplied sketch.
- Target macOS first. Prove Teams routing first, then add OBS as the second integration. The OBS milestone must work simultaneously with Teams.
- Default to a compact view. Provide an expanded mixer for detailed setup.
- Keep source selection, per-destination levels, global source mute and solo, output level, and output mute accessible in compact view.
- Retain input gain, output solo, mix linking, and detailed metering in expanded view or settings.
- Support background routing while the window is hidden. Persist routing and controls across restarts.
- Support sending a dedicated recording mix to OBS. OBS handles recording; do not build an internal recorder, effects, or timelines.

## Integration milestones and teaching workflow

Keep five source slots and the four-output state model throughout both milestones. Sequence integration work without reducing the mixer to two sources.

1. First milestone: macOS + Teams, with an independently configurable headphone monitoring mix. Verify actual capture, outgoing meeting audio, meeting return audio, background operation, and restored settings in a real call.
2. Second milestone: macOS + Teams + OBS simultaneously. A music teacher must be able to teach through Teams while OBS records the session from a separately configurable mix. Starting or stopping OBS must not interrupt Teams or monitoring.

Example five-source configuration: teacher microphone, instrument/audio-interface input, music or backing-track app, Teams return (remote participant audio), and another user-selected source. These are examples, not fixed slot assignments. Verify capture support and source isolation for the chosen implementation; do not assume system audio capture excludes Teams.

Example independent destination mixes:

| Destination | Intended content | Default exclusions when configuring this workflow |
| --- | --- | --- |
| Teams outgoing | Teacher microphone, instrument, and selected backing audio | Teams return, to prevent feeding participants their own audio |
| Headphones | Teams return and selected instrument/backing audio | Teacher microphone unless the user explicitly enables software monitoring |
| OBS recording | Teacher microphone, instrument, backing audio, and Teams return, as selected | Duplicate captures of any source already present in this mix |
| Fourth output | User-configured destination | All sends until configured |

These examples guide an explicit setup flow; they must not activate routes automatically on first launch. Preserve per-destination send-enable and level independence. Source mute and solo are global across every destination. A teacher may need different backing-track or instrument balances in Teams, headphones, and OBS.

## Monitoring and feedback prevention

- Treat headphone monitoring as a named output mix with its own source sends and master controls.
- Exclude Teams return from the Teams outgoing mix in the standard teaching configuration (mix-minus). Before any change would introduce Teams return into Teams outgoing, explain the feedback/echo consequence and require explicit confirmation. Apply this check to send activation, mix linking, leader edits, source or destination reassignment, and overlapping capture scopes. Evaluate all affected followers before committing the change; cancellation leaves the entire change unapplied. Identify roles by configured endpoint/capture scope, not editable display names. If isolation cannot be verified, show the uncertainty during setup.
- Keep teacher microphone software monitoring off in the standard headphone configuration. Allow deliberate enablement and explain possible delayed self-monitoring or duplicate monitoring when the interface also provides direct monitoring.
- Avoid capturing Teams return twice through overlapping app and system captures. Make overlapping capture scope visible and guide users to isolated capture where supported.
- In OBS setup instructions, use the dedicated Smixx recording feed and explain how to avoid capturing the same microphone, desktop audio, or Teams audio again through other OBS sources.
- Do not claim that an OBS recording has started or succeeded merely because its Smixx feed is active. Smixx reports feed status; OBS owns recording status.
- Each source has a global mute that silences it in every Smixx output, including OBS. No slot is reserved for a microphone. To silence a source only in Teams, disable its Teams send without changing its sends to headphones or OBS. Global mute controls Smixx routing, not capture or the meeting application’s own mute state. If the same endpoint is selected in multiple slots, show the duplicate assignment and explain that each slot has separate global controls; muting one slot does not mute the others.

## Main mixer — vertical channel strips

Latest user direction: use traditional vertical channel strips as the main mixer. Show all five source strips side by side, followed by a visually distinct vertical master strip. Both compact and expanded views retain vertical send faders and meters.

Revised layout target: approximately 760 logical pixels wide in compact mode, with five source strips and a master strip. Expanded mode may be wider to expose detailed controls. Treat these as layout targets, not fixed dimensions. Choose the smallest size that preserves full labels, usable controls, keyboard focus, and accessibility scaling. Avoid scrolling for the standard five-source view at default text size.

Layout:

1. Header: prominent `Mix sent to: [destination selector]`, destination status, and access to settings.
2. Five vertical source strips: available-source dropdown, recognizable source name, selected-destination send-enable control, small activity meter, vertical send-level fader, editable level value, and global source mute and solo.
3. Visually separated master strip to the right: selected destination name, combined output meter, master level, and output mute.
4. Footer: `Expand mixer` and a brief actionable status only when needed.

Use actual names such as `Microphone`, `System audio`, `Music`, `Teams call`, or `Headphones` when available. Allow custom display names. Unconfigured slots must offer `Choose source` rather than imply an active connection.

Keep settings and detailed controls secondary. Avoid decorative borders, large empty areas, permanent explanatory text, and unnecessary chrome. Preserve sufficient spacing and clear visual hierarchy.

## Routing and state model

- All five source slots are interchangeable. Each offers a dropdown of available supported sources; no slot is reserved for a microphone. Show unavailable saved assignments as disconnected and distinguish them from selectable sources. Include channel selection where needed to identify an instrument or microphone on a multichannel device.
- Each source slot has global input gain, global mute, and global solo selection. These controls affect that slot across all output mixes, including linked mixes.
- Each output mix has independent source-send enabled states and levels, master level, and master mute. There is no per-send mute or per-destination source solo.
- The selected output determines which send-enable, send-level, and master controls the window displays. Merely selecting another output must never modify routing or values. Global source mute and solo remain unchanged and display consistently across destination selections.
- Disabling a send removes that source from the selected mix while retaining its send level. Re-enabling it remains subject to global mute, solo, and feedback checks.
- Label source controls explicitly, for example `Mute Music in all outputs` and `Solo Music in all outputs`. Do not imply these controls mute another app or stop capture.
- Changing a slot’s source must atomically apply global mute before the replacement source can produce output. Retain gain, send levels, and enabled sends, clear that slot’s temporary solo selection, and leave it muted until deliberately unmuted. Apply the same rule to channel/capture-scope changes; reselecting the identical assignment is a no-op. A rename or reconnection of the same saved endpoint is not a replacement.
- Changing an output endpoint must atomically mute that output before connecting the replacement. Retain its mix and master level and require deliberate unmute. Reconnecting the same endpoint preserves saved mute state.
- Global input gain affects all destinations. Label that scope wherever gain can be edited.
- Output master mute affects only that output. It must not pause source capture or change other mixes.
- Use stable endpoint identifiers where available so renamed devices do not silently lose their routing assignments.

## Destination selection

The destination selector exposes the four output mixes with their names and connection states. Keep the current destination visible while editing any send.

On selection, update source-send controls, master controls, meters, output mute states, and linking information together. Avoid displaying controls from different mixes during the transition. Clearly distinguish configured destination, currently available endpoint, and disconnected endpoint.

Treat conferencing apps, OBS, plugins, system speakers, and audio interfaces as possible integration categories, not guaranteed interchangeable endpoints. Application destinations may require virtual audio devices or other supported routing mechanisms. Document the actual mechanism and setup requirements for each implemented integration.

Do not promise AUv3 support or simultaneous output to multiple physical interfaces without checking the existing platform implementation. If multi-device routing requires an aggregate device, explicit clock handling, or another setup step, expose that requirement clearly. Do not silently substitute a different device.

## Levels and meters

- Display levels in dB using the audio engine's supported range and consistent formatting. Include a clear silence value and a visible unity reference.
- Allow slider adjustment and direct numeric entry. Validate input and reject invalid values without changing the previous valid setting.
- Support keyboard adjustment and a discoverable reset to unity.
- Input gain belongs in expanded view. Offer numeric editing and dragging if consistent with the application's established controls. A knob is optional; compactness and clarity take priority.
- Compact source meters show input activity after input gain and before global source mute/solo and destination send-enable/level processing. Thus activity can remain visible while a source is muted or suppressed; make that state clear.
- The output meter shows the combined signal after all source/send processing, output solo suppression, master level, and master mute. A muted or solo-suppressed output shows no output signal. Label this as mix signal, not proof of delivery. Separately show endpoint availability and feed-delivery status where observable; explicitly show unknown delivery status when it cannot be verified. A disconnected endpoint must never appear to be receiving audio merely because its mix meter moves.
- Show clipping with a distinct indicator and a way to clear held peaks. Separate input activity from connection status.
- Detailed contributions from the five sources may appear in expanded view with source labels. Do not place five unlabeled bars inside the master meter where they could be mistaken for output channels.
- Use the existing engine's channel configuration. Distinguish mono and stereo accurately.

## Expanded mixer

Provide the full five-source and one-selected-output mixer with moderate-length faders, detailed meters, numeric levels, global input gain, source configuration, solo, and mix-link settings.

Preserve the selected destination and all values when switching views. Expansion is presentation only and must not restart or interrupt audio. Keep the destination header and a clearly separated master strip visible.

## Solo

- Source solo is global across all outputs. Allow multiple source solo selections. Solo only suppresses nonselected sources; it never enables a disabled send, overrides any mute, or changes saved gains or levels.
- Mute takes precedence over solo. Retain solo selection while a source is muted, but display `Muted — solo pending`, never an active solo indication. Unmuting activates that pending solo selection, subject to enabled sends and output controls. Selecting solo on a muted source does not unmute it.
- If any source has a solo selection, only selected, unmuted sources are eligible for output. If every selected source is muted, all sources are silent until one is unmuted or the selections are cleared. This avoids unexpectedly exposing nonsoloed sources when muting a soloed source.
- Output solo is global across the four outputs: allow multiple output solo selections, suppressing only unselected outputs. Output mute takes precedence using the same pending-selection rules as source mute. Keep output solo in expanded view and label its effect on Teams, headphones, and OBS explicitly.
- A signal is eligible only if its source is unmuted and passes source solo selection, its destination send is enabled, and its output is unmuted and passes output solo selection. Source and output solo never override one another’s suppression.
- Any active or pending solo selection must remain visible in compact view and the menu-bar menu, with `Clear all solos` available. Clearing solos removes source and output selections without altering mutes, send-enable states, or levels.
- Do not restore temporary solo selections after application restart.

## Linked mixes (“Follow”)

Replace numbered follow buttons with a named setting such as `Use the same mix as: Teams call`.

- For a fresh configuration, all four output mixes are independent. Linking is an explicit user choice; never automatically make a new headphone or OBS mix inherit the Teams sends. Preserve existing saved links and independent configurations.
- Linking shares source-send enabled states and send levels. Each output retains its endpoint, master level, and master mute. Source gain, mute, and solo remain global and are not properties of a link.
- A follower displays the effective inherited send values and the leader's name. Its inherited controls are read-only until the user chooses `Make independent`.
- Making a mix independent copies its current effective send values so unlinking does not cause an audible level jump.
- Prevent self-links and cycles. Keep the initial implementation to one leader per follower, with followers referencing an independent mix directly.
- Output solo selections are not inherited through links. Global source solo affects every mix regardless of linking. Reject attempts to make a leader with existing followers into a follower; require explicit unlinking of its followers first.

## Background operation and persistence

- Closing or hiding the mixer window keeps audio routing running. Provide an explicit `Quit Smixx` command that stops routing.
- Provide menu-bar/tray access to open the mixer, inspect routing status, inspect and toggle each source’s global mute and solo, clear solos, and quit.
- Persist source assignments, destination assignments, names, gains, levels, enabled sends, mutes, mix links, selected destination, window position, and compact/expanded preference.
- Restore valid configuration after restart without resetting levels. Apply all saved source and output mute states before starting any routes, with no transient unmuted audio. Restore no temporary solos.
- On first launch, start with no active sends until configured. Restoring an existing configuration may resume its previously enabled routes.
- When a device disappears, preserve its assignment and settings, mark it disconnected, and avoid silently routing audio elsewhere. Reconnect the same endpoint when it returns.
- Explain permission failures or unavailable devices with concise recovery actions. Do not present silent meters as proof of a disconnected endpoint.
- Reduce meter rendering when hidden while keeping routing uninterrupted. Reuse existing engine scheduling and avoid unnecessary background UI work.

## Accessibility and interaction

All controls must work with keyboard navigation and have descriptive accessible names, values, and state. Use text or icons in addition to color for mute, solo, disconnect, and clipping states. Maintain readable contrast, visible focus, and usable pointer targets. Do not shrink targets solely to meet the proposed window dimensions.

Long source and destination names may truncate visually but must remain available through accessible text and a tooltip. Distinguish selected-destination send enable, global source mute/solo, and output mute/solo in labels and active states. Explain pending solo selections accessibly.

## Acceptance criteria

1. A user can configure five sources and four named output mixes, select a destination, adjust its mix, and verify output activity from compact view.
2. The standard layout shows all five vertical source strips and the master strip without scrolling at default text size.
3. Switching destinations shows the correct complete mix and changes no stored values or audible routing by itself.
4. Editing an independent mix changes that mix and its explicitly linked followers only; editing global input gain affects all routes from that source and is labeled accordingly.
5. Global source mute/solo, per-destination send enable, and output mute/solo each affect only their documented scope. All five slots use available-source dropdowns with no reserved microphone slot. Source replacement mutes the slot before any replacement audio is routed.
6. Input activity remains understandable when a source is muted; output metering reflects the processed mix signal and is clearly distinguished from verified endpoint delivery.
7. Linked mixes inherit sends correctly, retain independent masters, reject cycles, and become independent without changing their effective levels.
8. Solo behavior is visibly indicated, reversible, and cleared after restart without destroying saved levels or mutes.
9. Hiding the window and changing views do not interrupt audio. Quitting stops routing.
10. Restart restores configuration and saved mutes. Device loss preserves assignments and never silently reroutes audio.
11. Every primary control is keyboard accessible and understandable without relying on color.
12. Unsupported integrations are clearly identified; no placeholder endpoint or simulated meter is presented as working audio routing.
13. All five source slots are present and functional in the first macOS version; the first integration milestone proves Teams plus independent headphone monitoring.
14. The standard teaching configuration sends Teams return to headphones and, when selected, OBS, while excluding it from Teams outgoing. Teacher microphone software monitoring starts off unless explicitly enabled.
15. In the OBS milestone, Teams and OBS receive different simultaneous mixes, including remote participant audio in OBS when selected, without feeding Teams return back to Teams or duplicating recorded sources.
16. Starting/stopping OBS or muting only its output does not interrupt the Teams call or alter the headphone mix.
17. Complete a real Teams call with the mixer hidden, then reopen it and confirm the settings remain intact. For the OBS milestone, also inspect an actual OBS recording for the intended local and remote sources, correct balance, and absence of duplicate audio.

## Implementation and verification instructions for Codex

Inspect repository guidance, existing screens, audio capabilities, and persistence before implementation. Reuse the current framework and design conventions. Resolve routine layout choices autonomously. If an audio capability is absent, report the concrete dependency and implement the supported portions without implying completion of that capability.

Verify routing-state isolation, mix-link behavior, persistence, and mute/solo restoration with focused tests. Inspect compact and expanded layouts with realistic long names, disconnected endpoints, mute states, and keyboard focus. Use real audio loopback or the project's established integration harness to verify audio behavior where available; distinguish UI verification from verified audio integration in the completion report.

Deliver the implemented screens, a brief summary of behavior changes, verification results, and any remaining platform or audio-engine limitations. Publishing, distribution, and unrelated audio features are outside this implementation scope.


## Audio feasibility gate

Before implementing the complete mixer UI, document and demonstrate a working audio path for the five-source/four-output model. Keep all five slots; do not substitute simulated audio for unsupported capabilities.

- Record the existing engine/framework, minimum supported macOS version, supported hardware/architectures, capture permissions, installation steps, and any virtual-device or other external dependency.
- Document actual source capture and destination delivery mechanisms. Demonstrate microphone, selected audio-interface channel, backing audio, isolated Teams return, and a fifth supported source concurrently. Show how the user selects Teams input/output and later the dedicated OBS feed.
- Document mono/stereo mapping, supported sample rates, buffer configuration, clock ownership, resampling/drift handling, and any multi-device or aggregate-device requirements. Verify that simultaneous consumers do not share unintended mixes.
- Prove Teams outgoing plus independent headphones first. Prove the separate OBS feed concurrently for milestone two, including remote audio and consumer start/stop isolation.
- Record measured monitoring and feed latency, and establish numeric acceptance limits on a named reference setup before calling a milestone passed. Record the chosen values in the test report; unresolved limits remain open acceptance items.
- List unsupported configurations and concrete dependencies. UI completion alone does not satisfy this gate.

## Required testing and evidence

These are required verification tasks, not claims of completed tests. Report each as passed, failed, blocked, or not run, with evidence and remaining limitations. Use deterministic state tests for routing logic and real audio or the established integration harness for signal behavior.

| Area | Required tests | Pass condition / evidence |
| --- | --- | --- |
| Five interchangeable sources | Select each supported source type in any slot; exercise available-source dropdowns, channel selection, duplicate endpoints, and disconnected saved assignments. | No reserved microphone slot; supported capture works and duplicate/unsupported scopes are clearly identified. |
| Global source controls | Mute each source across all four outputs; solo one and multiple sources; mute a soloed source; select solo while muted; unmute; clear solos. Repeat with linked mixes. | Mute always wins; pending solo is visible; unmute activates selection; disabled sends remain disabled; all-selected-muted produces silence. |
| Output controls | Solo one and multiple outputs; combine source/output solos and mutes; mute all selected outputs; clear solos. | Only eligible outputs produce audio; pending selections and scope match the documented rules; saved levels and sends do not change. |
| Reassignment | Replace source, source channel/scope, and output endpoint while audio is flowing, including a soloed source. Reselect the identical assignment and rename/reconnect it separately. | Replacement is muted before its first routed sample; source solo clears on replacement; no transient leak. Identical assignments are no-ops; reconnect retains saved state. |
| Mix isolation and links | Edit independent mixes and leaders; link/unlink; reject cycles, self-links, and leaders becoming followers. Switch destinations and views. | Only the edited mix and explicit followers change; unlink copies effective sends; masters remain independent; selection/view changes do not alter audio. |
| Feedback and overlap | Introduce Teams return through direct sends, linking, leader edits, reassignment, and overlapping system capture. Cancel and accept warnings. | Every supported path is checked before committing; cancellation preserves all affected state; isolation uncertainty is visible; standard workflow has no return-to-Teams loop. |
| Persistence and recovery | Restart with mixed source/output mutes and solos; disconnect/reconnect devices; restart Teams and OBS; revoke/restore permissions; sleep/wake the Mac. | Saved mutes apply before audio starts; solos clear on restart; no silent device substitution; recovery is either successful or accompanied by an actionable status. |
| Meters and delivery | Apply known signals, gain, mute, solo suppression, clipping, and endpoint disconnection. | Input/output meter positions match the spec; peak clearing works; meter movement never implies unverified endpoint delivery. |
| Latency and stability | Measure source-to-headphones and source-to-application-feed latency on the reference setup. Run a minimum 60-minute Teams call with all five sources configured and active test signals, including OBS for milestone two. | Report configuration, measured latency against agreed limits, observed dropouts, drift, CPU and memory behavior. No unexplained interruption or increasing synchronization drift; unresolved failures block acceptance. |
| Teaching workflow | Use distinct identifiable local and remote signals; verify Teams receives its intended mix and headphones their independent mix. Record the separate OBS mix; start/stop OBS and mute its output during the call. | Remote participant confirms intended outgoing audio; inspect the actual recording for all intended sources, independent balances, and no duplicate captures. Teams/headphones remain uninterrupted by OBS changes. |
| Background and accessibility | Hide/close/reopen the window during a real call; operate menu-bar source controls; quit explicitly. Inspect both views with long names, keyboard navigation, accessibility scaling, disconnected endpoints, and active/pending solos. | Hidden routing continues; quit stops routing; controls and scope remain accessible. Default compact view fits without scrolling, with larger accessible layouts permitted. |

Store the test report with the implementation, including application/OS versions, hardware and device identifiers, dependency versions, channel/sample-rate/buffer settings, test duration, measured results, and links to logs or test recordings where appropriate. Do not mark real-call, latency, recovery, or recording checks passed based solely on unit tests or UI meters.
