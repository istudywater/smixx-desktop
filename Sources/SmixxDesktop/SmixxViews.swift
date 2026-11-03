import SwiftUI
import SmixxCore

let accent = Color(red: 0.20, green: 0.69, blue: 0.59)

private struct FaderHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 220 }
private extension EnvironmentValues {
    var faderHeight: CGFloat {
        get { self[FaderHeightKey.self] }
        set { self[FaderHeightKey.self] = newValue }
    }
}

struct MixerView: View {
    @ObservedObject var store: MixerStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { area in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                ForEach(0..<6, id: \.self) { index in
                    SourceStrip(store: store, index: index, output: store.selected).id("\(index)-\(store.selected)")
                    Divider()
                }
                headphones.padding(12).frame(maxWidth: .infinity, alignment: .top)
                Divider()
                master.id(store.selected).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(.quaternary.opacity(0.35))
                    }
                    .environment(\.faderHeight, max(110, area.size.height - 235))
                    .frame(width: area.size.width)
                    .frame(minHeight: area.size.height, alignment: .top)
                }
            }
        }
        .frame(minWidth: 1080, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .tint(accent)
        .sheet(isPresented: $store.showSetup) { SetupView(store: store) }
        .sheet(item: $store.effectsTarget) { EffectsView(store: store, target: $0) }
        .background(WindowAttachment())
        .onAppear { AppDelegate.shared?.store = store }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("SMIXX", systemImage: "waveform.path").font(.system(.headline, design: .rounded))
                Text("DESKTOP").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "headphones").foregroundStyle(.secondary).accessibilityHidden(true)
                    Picker("Headphone monitor", selection: Binding(get: { store.state.monitor.bus }, set: { value in store.edit { $0.monitor.bus = value } })) {
                        ForEach(0..<3, id: \.self) { Text("Bus \($0 + 1)").tag($0) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 90)
                        .accessibilityLabel(store.state.monitor.muted ? "Headphone monitor, muted" : "Headphone monitor")
                }
                .help("Choose the channel balance for headphones. Listening is before Send and bus mute/solo; headphone volume is on the mixer.")
                .padding(.trailing, 12)
                Button { store.showSetup = true } label: { Label("Settings", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Sources, outputs, and setup").accessibilityLabel("Open settings")
            }
            if store.state.hasSolos {
                HStack {
                    Label("Bus-specific solo selections active", systemImage: "headphones")
                    Spacer()
                    Button("Clear all") { store.clearSolos() }
                }.font(.caption).foregroundStyle(.orange)
            }
        }.padding(14)
    }
    private var headphones: some View {
        VStack(spacing: 10) {
            Text("HEADPHONES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(store.state.monitor.endpointName ?? "Choose in Settings").font(.headline).lineLimit(2).frame(height: 36)
            Text(store.monitorStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height: 30).help(store.monitorStatus)
            LevelControl(value: Binding(get: { store.state.monitor.levelDB }, set: { value in store.edit { $0.monitor.levelDB = value } }), label: "Headphone listening volume", vertical: true, maximum: 0)
            Label("Limiter on", systemImage: "shield.checkered").font(.caption2).foregroundStyle(.secondary).help("Independent headphone peak limiter; outgoing bus effects do not change headphone audio")
            stateButton("M", active: store.state.monitor.muted, color: .orange, label: "Mute headphones only") { store.edit { $0.monitor.muted.toggle() } }
        }
    }
    private var master: some View {
        let outputIndex = store.selected
        return VStack(spacing: 10) {
            Text("BUS \(store.selected + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(store.selectedOutput.endpointName ?? "Choose destination in Setup").font(.headline).lineLimit(2).frame(height: 36).help(store.selectedOutput.name)
            Text(store.outputStatus[store.selected]).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(height: 30).help(store.outputStatus[store.selected])
            HStack(alignment: .top, spacing: 12) {
                LevelControl(value: Binding(get: { store.state.outputs[outputIndex].levelDB }, set: { value in store.edit { $0.outputs[outputIndex].levelDB = value } }), label: "\(store.selectedOutput.name) output level", vertical: true)
                VerticalMeter(value: store.outputPeaks[store.selected], clipping: store.outputClips[store.selected], label: "\(store.selectedOutput.name) mix signal", clear: store.clearPeaks)
            }
            HStack(spacing: 5) {
                stateButton("M", active: store.selectedOutput.muted, color: .orange, label: "Mute output \(store.selectedOutput.name)") { store.edit { $0.outputs[store.selected].muted.toggle() } }
                stateButton("E", active: (store.selectedOutput.effects ?? .bus).enabled, color: accent, label: "Effects for \(store.selectedOutput.name)") { store.effectsTarget = EffectsTarget(bus: true, index: store.selected) }
            }
            if store.preLimiterClips[store.selected] { Button("Pre-limit peak ≥ 0 dBFS") { store.clearPeaks() }.font(.caption2).foregroundStyle(.orange).help("Reduce upstream levels if distorted; click to clear") }
            Picker("Bus being edited", selection: Binding(get: { store.selected }, set: { store.select($0) })) {
                ForEach(0..<3, id: \.self) { Text("\($0 + 1)").tag($0) }
            }.labelsHidden().pickerStyle(.segmented).accessibilityLabel("Bus being edited")


        }
    }

}

private struct SourceStrip: View {
    @ObservedObject var store: MixerStore
    let index: Int
    let output: Int
    private var source: SourceSlot { store.state.sources[index] }
    private var controlName: String { "Source \(index + 1), \(source.name)" }
    private var send: Send { store.state.outputs[output].sends[index] }
    var body: some View {
        VStack(spacing: 10) {
            Text("SOURCE \(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Source \(index + 1)", selection: Binding(get: { source.source?.identity ?? "none" }, set: { store.setSource(index, identity: $0) })) {
                Text("Choose source").tag("none")
                if let saved = source.source, !store.offeredSources.contains(where: { $0.identity == saved.identity }) {
                    Text("\(saved.name) · \(store.state.offers(saved) ? "unavailable" : "hidden")").tag(saved.identity).disabled(true)
                }
                ForEach(store.offeredSources, id: \.identity) { reference in Text(reference.name).tag(reference.identity) }
            }.labelsHidden().pickerStyle(.menu).frame(height: 36)
                .help(source.source?.name ?? "Select a hardware or application source")
            LevelControl(value: Binding(get: { source.gainDB }, set: { value in store.edit { $0.sources[index].gainDB = value } }), label: "\(controlName) input gain for all outputs").frame(height: 30)
            HStack(alignment: .top, spacing: 10) {
                LevelControl(value: Binding(get: { send.levelDB }, set: { value in store.edit { $0.outputs[output].sends[index].levelDB = value } }), label: "\(controlName) level to \(store.selectedOutput.name)", vertical: true)
                VerticalMeter(value: store.sourcePeaks[index], clipping: store.sourceClips[index], label: "\(controlName) input activity before mute", clear: store.clearPeaks)
            }
            HStack(spacing: 5) {
                stateButton("M", active: send.muted, color: .orange, label: "Mute \(controlName) in Bus \(store.selected + 1)") { store.edit { $0.outputs[output].sends[index].muted.toggle() } }
                stateButton(send.solo && (send.muted || source.muted) ? "S…" : "S", active: send.solo, color: accent, label: "Solo \(controlName) in Bus \(store.selected + 1); mute takes precedence") { store.edit { $0.outputs[output].sends[index].solo.toggle() } }
                stateButton("E", active: (source.effects ?? Effects()).enabled, color: accent, label: "Shared effects and details for \(controlName)") { store.effectsTarget = EffectsTarget(bus: false, index: index) }
            }
            stateButton("Send", active: send.enabled, color: accent, label: "Send \(controlName) to Bus \(output + 1); headphones are independent", fillWidth: true) { store.edit { $0.outputs[output].sends[index].enabled.toggle() } }
                .disabled(source.source == nil)
        }.padding(12).frame(maxWidth: .infinity)
    }
}

private final class ScrollFader: NSSlider {
    private var accumulatedScroll: CGFloat = 0
    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        if event.phase == .began { accumulatedScroll = 0 }
        guard event.momentumPhase.isEmpty else { return }
        accumulatedScroll += event.scrollingDeltaY * (event.isDirectionInvertedFromDevice ? -1 : 1)
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
        let steps = Int(accumulatedScroll / threshold)
        guard steps != 0 else { return }
        accumulatedScroll -= CGFloat(steps) * threshold
        doubleValue = min(maxValue, max(minValue, doubleValue + Double(steps) * 0.5))
        sendAction(action, to: target)
    }
}

private struct NativeVerticalFader: NSViewRepresentable {
    @Binding var value: Double
    var label: String
    var vertical = true
    var maximum: Double = 12
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = ScrollFader(frame: NSRect(x: 0, y: 0, width: vertical ? 24 : 100, height: vertical ? 220 : 20))
        slider.minValue = -60; slider.maxValue = maximum
        slider.sliderType = .linear
        slider.target = context.coordinator; slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.maxValue = maximum; slider.doubleValue = value; slider.isEnabled = context.environment.isEnabled
        slider.setAccessibilityLabel(label)
    }
    final class Coordinator: NSObject {
        var parent: NativeVerticalFader
        init(_ parent: NativeVerticalFader) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = (sender.doubleValue * 2).rounded() / 2 }
    }
}

private struct VerticalMeter: View {
    @Environment(\.faderHeight) private var faderHeight
    var value: Float
    var clipping: Bool
    var label: String
    var clear: () -> Void
    private var fraction: CGFloat { value <= 0 ? 0 : CGFloat(max(0, min(1, (20 * log10(value) + 60) / 60))) }
    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Capsule().fill(.quaternary)
                Capsule().fill(value >= 1 ? Color.red : accent).frame(height: faderHeight * fraction)
            }.frame(width: 8, height: faderHeight)
                .accessibilityLabel(label).accessibilityValue(value <= 0 ? "Silent" : String(format: "%.1f dBFS", 20 * log10(value)))
            Button(clipping ? "CLIP" : "Peak", action: clear).buttonStyle(.plain).font(.system(size: 8)).foregroundStyle(clipping ? .red : .secondary).help("Clear held peaks")
        }
    }
}

@ViewBuilder private func stateButton(_ title: String, active: Bool, color: Color, label: String, fillWidth: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title == "E" && active ? "E•" : title).font(.caption.weight(.semibold)).frame(minWidth: 25, maxWidth: fillWidth ? .infinity : nil, minHeight: 23)
            .foregroundStyle(active ? color : .secondary)
            .background(active ? color.opacity(0.24) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
    }
        .buttonStyle(.plain)
        .help(label).accessibilityLabel(label).accessibilityValue(active ? "On" : "Off")
}

private struct LevelControl: View {
    @Environment(\.faderHeight) private var faderHeight
    @Binding var value: Double
    let label: String
    var vertical = false
    var maximum: Double = 12
    @State private var entry = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if vertical {
                VStack(spacing: 6) {
                    HStack(spacing: 2) {
                        NativeVerticalFader(value: $value, label: label, maximum: maximum).frame(width: 24, height: faderHeight)
                        ZStack {
                            ForEach(maximum == 0 ? [0, -12, -24, -60] : [12, 0, -24, -60], id: \.self) { db in
                                Text(db == -60 ? "−∞" : (db > 0 ? "+\(db)" : "\(db)"))
                                    .position(x: 12, y: max(5, min(faderHeight - 5, CGFloat(maximum - Double(db)) / CGFloat(maximum + 60) * faderHeight)))
                            }
                        }.font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, height: faderHeight)
                    }
                    numericField
                }
            } else {
                HStack(spacing: 5) {
                    NativeVerticalFader(value: $value, label: label, vertical: false, maximum: maximum).frame(height: 20)
                    numericField
                }
            }
        }.contextMenu { Button("Reset to unity (0 dB)") { value = 0; entry = formatted } }
    }
    private var numericField: some View {
            TextField("dB", text: $entry)
                .font(.caption.monospacedDigit()).multilineTextAlignment(.trailing).textFieldStyle(.roundedBorder)
                .frame(width: 49).focused($focused).onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onAppear { entry = formatted }
                .onChange(of: value) { _, _ in if !focused { entry = formatted } }
                .help(invalid ? "Enter −60 to \(Int(maximum)) dB, or −∞ for silence." : "\(label), dB. 0 is unity; −∞ is silence.")
                .accessibilityLabel("\(label) in decibels")
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(invalid ? Color.orange : .clear))
    }
    private var formatted: String { value <= -60 ? "−∞" : String(format: "%.1f", value) }
    private func commit() {
        let text = entry.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-")
        let parsed = ["-∞", "-inf", "silence"].contains(text.lowercased()) ? -60.0 : Double(text)
        if let parsed, parsed.isFinite, (-60...maximum).contains(parsed) { value = parsed; invalid = false } else { invalid = true }
        entry = formatted
    }
}
private struct Meter: View {
    var value: Float
    var clipping: Bool
    var label: String
    var clear: () -> Void
    private var fraction: CGFloat { value <= 0 ? 0 : CGFloat(max(0, min(1, (20 * log10(value) + 60) / 60))) }
    var body: some View {
        HStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(value >= 1 ? Color.red : accent).frame(width: geometry.size.width * fraction)
                }
            }.frame(height: 4).accessibilityLabel(label).accessibilityValue(value <= 0 ? "Silent" : String(format: "%.1f dBFS", 20 * log10(value)))
            if clipping { Button("CLIP", action: clear).buttonStyle(.plain).font(.system(size: 8, weight: .bold)).foregroundStyle(.red).help("Clear held peaks") }
        }.frame(height: 7)
    }
}

struct SetupView: View {
    @ObservedObject var store: MixerStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Smixx settings").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
            HStack(spacing: 6) {
                ForEach(Array(["Getting started", "Inputs", "Outputs", "Diagnostics"].enumerated()), id: \.offset) { index, title in
                    Button { store.setupSection = index } label: {
                        Text(title).font(.callout.weight(store.setupSection == index ? .semibold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(store.setupSection == index ? Color.white : Color.primary)
                            .background(store.setupSection == index ? accent.opacity(0.65) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).accessibilityLabel("Setup: \(title)").accessibilityValue(store.setupSection == index ? "Selected" : "Not selected")
                }
            }.padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            Group {
                switch store.setupSection {
                case 0: workflow
                case 1: inputs
                case 2: outputs
                default: diagnostics
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(width: 610, height: 600).tint(accent)
    }
    private var inputs: some View {
        let devices = store.inventory.devices.filter { $0.inputs > 0 && !SmixxTransport.feedUIDs.contains($0.uid) }
        let deviceKeys = devices.map { MixerState.inputMenuKey(.device, $0.uid) }
        let appKeys = store.inventory.apps.map { MixerState.inputMenuKey(.application, $0.id) }
        let present = Set(deviceKeys + appKeys)
        let missing = (store.state.hiddenInputs ?? [:]).keys.filter { !present.contains($0) }.sorted()
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Show in source menus").font(.headline)
                    Spacer()
                    Button("Show all") { store.edit { $0.showAllInputs() } }
                        .disabled(store.state.hiddenInputs == nil)
                }
                Text("Uncheck a device to hide all its channels, or an app to hide both capture modes. Sources already assigned to a strip keep playing.").font(.callout).foregroundStyle(.secondary)
                Divider()
                Text("Hardware inputs").font(.headline)
                ForEach(devices) { d in
                    inputToggle(d.name, key: MixerState.inputMenuKey(.device, d.uid), detail: "\(d.inputs) input channel\(d.inputs == 1 ? "" : "s")")
                }
                Divider()
                Text("Applications").font(.headline)
                ForEach(store.inventory.apps) { app in
                    inputToggle(app.name, key: MixerState.inputMenuKey(.application, app.id), detail: app.id)
                }
                if !missing.isEmpty {
                    Divider()
                    Text("Currently unavailable").font(.headline)
                    ForEach(missing, id: \.self) { key in
                        inputToggle(store.state.hiddenInputs?[key] ?? key, key: key, detail: "Check to show next time it is available")
                    }
                }
            }.padding()
        }
    }
    private func inputToggle(_ name: String, key: String, detail: String) -> some View {
        Toggle(isOn: Binding(get: { store.state.hiddenInputs?[key] == nil }, set: { visible in
            store.edit { $0.setInputVisible(visible, key: key, name: name) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }.toggleStyle(.checkbox).accessibilityLabel("Show \(name) in source menus")
    }
    private var outputs: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Three buses. Independent headphone monitoring.").font(.headline)
                Text("Smixx Bus 1–3 are independent feeds. Select Bus 1 as the Teams microphone and Bus 2 in OBS for a new setup. Existing endpoint assignments are preserved during migration. Streaming to YouTube or Facebook requires streaming software.").font(.callout).foregroundStyle(.secondary)
                GroupBox("Headphone monitoring") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Channel balance", selection: Binding(get: { store.state.monitor.bus }, set: { value in store.edit { $0.monitor.bus = value } })) {
                            ForEach(0..<3, id: \.self) { Text("Smixx Bus \($0 + 1)").tag($0) }
                        }
                        Picker("Headphone device", selection: Binding(get: { store.state.monitor.endpointUID ?? "none" }, set: { store.setMonitorEndpoint($0) })) {
                            Text("Choose headphones").tag("none")
                            if let uid = store.state.monitor.endpointUID, !store.inventory.devices.contains(where: { $0.uid == uid }) { Text("\(store.state.monitor.endpointName ?? uid) · disconnected").tag(uid) }
                            ForEach(store.inventory.devices.filter { $0.outputs >= 2 && !SmixxTransport.feedUIDs.contains($0.uid) }) { Text($0.name).tag($0.uid) }
                        }
                        Toggle("Mute headphones", isOn: Binding(get: { store.state.monitor.muted }, set: { value in store.edit { $0.monitor.muted = value } }))
                        HStack {
                            Text("Listening volume")
                            LevelControl(value: Binding(get: { store.state.monitor.levelDB }, set: { value in store.edit { $0.monitor.levelDB = value } }), label: "Headphone listening volume", maximum: 0)
                            Text(String(format: "%.1f dB", store.state.monitor.levelDB)).monospacedDigit()
                        }
                        Text(store.monitorStatus).font(.caption)
                        Text("Headphones use the selected channel balance before Send and bus mute/solo, with their own volume and peak limiter. Outgoing bus effects and master controls do not affect headphones. No automatic speaker fallback.").font(.caption).foregroundStyle(.secondary)
                    }.padding(4)
                }
                ForEach(0..<3, id: \.self) { index in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.state.outputs[index].name).font(.headline)
                            Picker("Purpose", selection: Binding(get: { store.state.outputs[index].role }, set: { value in store.edit { $0.outputs[index].role = value } })) {
                                Text("Meeting send").tag(OutputRole.meeting)
                                Text("Recording feed").tag(OutputRole.recording); Text("Other").tag(OutputRole.custom)
                            }
                            Picker("Device", selection: Binding(get: { store.state.outputs[index].endpointUID ?? "none" }, set: { store.setEndpoint(index, uid: $0) })) {
                                Text("Choose destination").tag("none")
                                if let uid = store.state.outputs[index].endpointUID, !store.inventory.devices.contains(where: { $0.uid == uid && $0.outputs >= 2 }) {
                                    Text("\(store.state.outputs[index].endpointName ?? uid) · unavailable").tag(uid)
                                }
                                ForEach(store.inventory.devices.filter { $0.outputs >= 2 }) { device in
                                    Text("\(device.name) · channels 1–2").tag(device.uid)
                                }
                            }
                            Text(store.outputStatus[index]).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }.padding(4)
                    }
                }
                Text("Changing a destination mutes it. Select its mix and unmute deliberately. Buses and the headphone monitor must use distinct endpoints. Monitoring uses bounded resampling and clock-drift correction; actual device stability still needs verification.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
    }
    private var workflow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("First, listen through headphones").font(.title3.bold())
                Text("1. In Outputs, choose a physical headphone device. Choose the channel balance for headphones, begin with a low listening volume, then unmute headphones.")
                Text("2. Assign up to six sources. New or replacement assignments start with Send off in every bus, but are audible in headphones. Enable Send for sources you want the call to hear, then unmute the outgoing bus.")
                Text("3. Use 1 | 2 | 3 to edit mixes. The Headphones selector independently chooses the channel balance you hear before Send and bus M/S. Source M/S affect only the edited bus; source E and input trim are shared.")
                Divider()
                Text("Teams return: hear participants once").font(.headline)
                Text("Set Teams microphone to Smixx Bus 1. Add Teams as a source using route playback to hear participants through Smixx without duplicate direct playback. Leave Teams Send off in Bus 1; enable Send for your mic, instruments, and music. Choose your AudioBox or other physical headphones in Outputs. Headphones include Teams even with Send off. Keep Teams playback volume audible; do not use it to prevent echo. Capture copy keeps the original playback active and can be heard twice.")
                Text("Application taps are isolated to the reported application processes. Smixx has no system-wide capture source. Hardware loopback content and helper-process overlap cannot always be identified; verify capture scope in setup. Do not capture the same source twice in OBS.")
                Divider()
                Text("Meeting and recording feeds").font(.headline)
                Text("Install the revised Smixx Audio driver to expose exactly Smixx Bus 1, 2, and 3. Choose Bus 1 as Teams’ microphone and Bus 2 as OBS Audio Input Capture for new setups. Migration preserves old endpoint UIDs; an existing OBS assignment may still use Bus 3. Driver replacement requires an audio-service restart or logout; installation does not happen from this panel.")
                Text("Compression and EQ start bypassed. Each bus has an enabled Apple peak limiter after its master. This is not a true-peak limiter and cannot undo upstream distortion. Keep source and mix levels sensible. Effects panels show actual parameter values; no simulated gain-reduction meter is displayed.")
                Text("Closing the mixer keeps audio running. Use Quit Smixx Desktop to stop capture and output.")
            }.font(.callout).padding()
        }
    }
    private var diagnostics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connection is separate from signal").font(.headline)
                Text("Meters show the audio processed by Smixx. Endpoint callbacks do not prove that Teams is transmitting or OBS is recording.").foregroundStyle(.secondary)
                ForEach(0..<6, id: \.self) { i in Text("Source \(i + 1): \(store.sourceStatus[i])").textSelection(.enabled) }
                Divider()
                ForEach(0..<3, id: \.self) { i in Text("\(store.state.outputs[i].name): \(store.outputStatus[i])").textSelection(.enabled) }
                Divider()
                Text(store.monitorStatus)
                Text("Audio Unit render/parameter errors: \(store.effectErrors)")
                if let notice = store.state.migrationNotice { Text(notice).textSelection(.enabled) }
                Text("Buffer underrun/overrun events: \(store.dropouts)").monospacedDigit()
                Text("macOS 14.2+ · Core Audio · optional Smixx Audio transport").foregroundStyle(.secondary)
                Button("Retry audio and refresh devices") { store.retry() }
                Text("Retry briefly restarts all configured capture and output paths. Device reconnects are otherwise handled individually.").font(.caption).foregroundStyle(.secondary)
                Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
                if store.needsReset { Button("Back up invalid settings and start fresh") { store.resetInvalidConfiguration() } }
                if let message = store.message, message != store.state.migrationNotice { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
                if let warning = store.duplicateWarning { Text(warning).foregroundStyle(.orange).textSelection(.enabled) }
            }.font(.callout).padding()
        }
    }
}

struct WindowAttachment: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.setFrameAutosaveName("SmixxMixerWindow") }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
