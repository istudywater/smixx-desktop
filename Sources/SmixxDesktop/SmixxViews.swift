import SwiftUI
import SmixxCore

private let accent = Color(red: 0.20, green: 0.69, blue: 0.59)

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
                ForEach(0..<5, id: \.self) { index in
                    SourceStrip(store: store, index: index)
                    Divider()
                }
                master.padding(12).frame(maxWidth: .infinity)
                    .background(.quaternary.opacity(0.35))
                    }
                    .environment(\.faderHeight, max(110, area.size.height - (store.state.expanded ? 365 : 235)))
                    .frame(width: area.size.width)
                }
            }
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(minWidth: store.state.expanded ? 820 : 690, maxWidth: .infinity, minHeight: 410, maxHeight: .infinity)
        .tint(accent)
        .sheet(isPresented: $store.showSetup) { SetupView(store: store) }
        .background(WindowAttachment())
        .onAppear { AppDelegate.shared?.store = store }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("SMIXX", systemImage: "waveform.path").font(.system(.headline, design: .rounded))
                Text("DESKTOP").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { store.showSetup = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Sources, outputs, and setup").accessibilityLabel("Open setup")
            }
            HStack {
                Text("Mix sent to").foregroundStyle(.secondary)
                Picker("Mix sent to", selection: Binding(get: { store.selected }, set: { store.select($0) })) {
                    ForEach(store.state.outputs) { output in Text(output.name).tag(output.id) }
                }.labelsHidden().pickerStyle(.menu)
            }
            HStack(spacing: 5) {
                Image(systemName: store.selectedOutput.endpointUID == nil ? "cable.connector.slash" : "cable.connector")
                Text(store.selectedOutput.endpointName ?? "Choose an output in Setup")
                    .lineLimit(1).truncationMode(.middle)
            }.font(.caption).foregroundStyle(.secondary).help(store.outputStatus[store.selected])
            if let leader = store.selectedOutput.leader {
                HStack {
                    Label("Following \(store.state.outputs[leader].name)", systemImage: "link")
                    Spacer()
                    Button("Make independent") { store.edit { try $0.link(store.selected, to: nil) } }
                }.font(.caption)
            }
            if store.state.hasSolos {
                HStack {
                    Label("Solo selections affect all mixes", systemImage: "headphones")
                    Spacer()
                    Button("Clear all") { store.clearSolos() }
                }.font(.caption).foregroundStyle(.orange)
            }
        }.padding(14)
    }
    private var master: some View {
        VStack(spacing: 10) {
            Text("MASTER").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(store.selectedOutput.name).font(.headline).lineLimit(2).frame(height: 36).help(store.selectedOutput.name)
            Text("Selected output").font(.caption2).foregroundStyle(.secondary).frame(height: 20)
            HStack(alignment: .top, spacing: 12) {
                LevelControl(value: Binding(get: { store.selectedOutput.levelDB }, set: { value in store.edit { $0.outputs[store.selected].levelDB = value } }), label: "\(store.selectedOutput.name) output level", vertical: true)
                VerticalMeter(value: store.outputPeaks[store.selected], clipping: store.outputClips[store.selected], label: "\(store.selectedOutput.name) mix signal", clear: store.clearPeaks)
            }
            HStack(spacing: 5) {
                stateButton("M", active: store.selectedOutput.muted, color: .orange, label: "Mute output \(store.selectedOutput.name)") { store.edit { $0.outputs[store.selected].muted.toggle() } }
                stateButton(store.selectedOutput.solo && store.selectedOutput.muted ? "S…" : "S", active: store.selectedOutput.solo && !store.selectedOutput.muted, color: accent, label: "Solo output \(store.selectedOutput.name)") { store.edit { $0.outputs[store.selected].solo.toggle() } }
            }
            Text("Output mute / solo").font(.caption2).foregroundStyle(.secondary)
            if store.state.expanded {
                Text("Use the same mix as").font(.caption2)
                Picker("Use the same mix as", selection: Binding(get: { store.selectedOutput.leader ?? -1 }, set: { value in store.edit { try $0.link(store.selected, to: value < 0 ? nil : value) } })) {
                    Text("Independent").tag(-1)
                    ForEach(store.state.outputs.filter { $0.id != store.selected && $0.leader == nil }) { output in Text(output.name).tag(output.id) }
                }.labelsHidden()
                Text(store.outputStatus[store.selected]).font(.caption2).foregroundStyle(.secondary).lineLimit(3).help(store.outputStatus[store.selected])
            }
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(store.state.expanded ? "Compact mixer" : "Expand mixer", systemImage: store.state.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                    store.edit { $0.expanded.toggle() }
                }.buttonStyle(.plain).font(.caption)
                Spacer()
                Button("Setup") { store.showSetup = true }.buttonStyle(.plain).font(.caption)
            }
            if let message = store.message ?? store.duplicateWarning {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SourceStrip: View {
    @ObservedObject var store: MixerStore
    let index: Int
    private var source: SourceSlot { store.state.sources[index] }
    private var send: Send { store.sends[index] }
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
            Toggle("Send", isOn: Binding(get: { send.enabled }, set: { value in store.edit { $0.outputs[store.selected].sends[index].enabled = value } }))
                .toggleStyle(.checkbox).font(.caption).frame(height: 20)
                .disabled(store.selectedOutput.leader != nil)
                .accessibilityLabel("Send \(source.name) to \(store.selectedOutput.name)")
            HStack(alignment: .top, spacing: 10) {
                LevelControl(value: Binding(get: { send.levelDB }, set: { value in store.edit { $0.outputs[store.selected].sends[index].levelDB = value } }), label: "\(source.name) level to \(store.selectedOutput.name)", vertical: true)
                    .disabled(store.selectedOutput.leader != nil)
                VerticalMeter(value: store.sourcePeaks[index], clipping: store.sourceClips[index], label: "\(source.name) input activity before mute", clear: store.clearPeaks)
            }
            HStack(spacing: 5) {
                stateButton("M", active: source.muted, color: .orange, label: "Mute \(source.name) in all outputs") { store.edit { $0.sources[index].muted.toggle() } }
                stateButton(source.muted && source.solo ? "S…" : "S", active: source.solo && !source.muted, color: accent, label: source.muted && source.solo ? "\(source.name) muted, solo pending" : "Solo \(source.name) in all outputs") { store.edit { $0.sources[index].solo.toggle() } }
            }
            Text("Global mute / solo").font(.caption2).foregroundStyle(.secondary)
            if store.state.expanded {
                TextField("Display name", text: Binding(get: { source.customName }, set: { value in store.edit { $0.sources[index].customName = value } })).accessibilityLabel("Source \(index + 1) display name")
                Text("Input gain · global").font(.caption2).foregroundStyle(.secondary)
                LevelControl(value: Binding(get: { source.gainDB }, set: { value in store.edit { $0.sources[index].gainDB = value } }), label: "\(source.name) input gain for all outputs")
                Text(store.sourceStatus[index]).font(.caption2).foregroundStyle(.secondary).lineLimit(3).help(store.sourceStatus[index])
            }
        }.padding(12).frame(maxWidth: .infinity)
    }
}

private struct NativeVerticalFader: NSViewRepresentable {
    @Binding var value: Double
    var label: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(frame: NSRect(x: 0, y: 0, width: 24, height: 220))
        slider.minValue = -60; slider.maxValue = 12
        slider.sliderType = .linear
        slider.target = context.coordinator; slider.action = #selector(Coordinator.changed(_:))
        slider.setAccessibilityLabel(label)
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.parent = self
        slider.doubleValue = value; slider.isEnabled = context.environment.isEnabled
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

@ViewBuilder private func stateButton(_ title: String, active: Bool, color: Color, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).font(.caption.weight(.semibold)).frame(minWidth: 17) }
        .buttonStyle(.bordered).tint(active ? color : .secondary)
        .help(label).accessibilityLabel(label).accessibilityValue(active ? "On" : "Off")
}

private struct LevelControl: View {
    @Environment(\.faderHeight) private var faderHeight
    @Binding var value: Double
    let label: String
    var vertical = false
    @State private var entry = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        Group {
            if vertical {
                VStack(spacing: 6) {
                    HStack(spacing: 2) {
                        NativeVerticalFader(value: $value, label: label).frame(width: 24, height: faderHeight)
                        ZStack {
                            ForEach([12, 0, -24, -60], id: \.self) { db in
                                Text(db == -60 ? "−∞" : (db > 0 ? "+\(db)" : "\(db)"))
                                    .position(x: 12, y: max(5, min(faderHeight - 5, CGFloat(12 - db) / 72 * faderHeight)))
                            }
                        }.font(.system(size: 8).monospacedDigit()).foregroundStyle(.secondary).frame(width: 24, height: faderHeight)
                    }
                    numericField
                }
            } else {
                HStack(spacing: 5) {
                    Slider(value: $value, in: -60...12, step: 0.5).accessibilityLabel(label)
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
                .help(invalid ? "Enter −60 to +12 dB, or −∞ for silence." : "\(label), dB. 0 is unity; −∞ is silence.")
                .accessibilityLabel("\(label) in decibels")
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(invalid ? Color.orange : .clear))
    }
    private var formatted: String { value <= -60 ? "−∞" : String(format: "%.1f", value) }
    private func commit() {
        let text = entry.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "−", with: "-")
        let parsed = ["-∞", "-inf", "silence"].contains(text.lowercased()) ? -60.0 : Double(text)
        if let parsed, parsed.isFinite, (-60...12).contains(parsed) { value = parsed; invalid = false } else { invalid = true }
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
            HStack { Text("Smixx setup").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
            TabView {
                inputs.tabItem { Label("Inputs", systemImage: "mic") }
                outputs.tabItem { Label("Outputs", systemImage: "cable.connector") }
                workflow.tabItem { Label("Getting started", systemImage: "list.number") }
                diagnostics.tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }.padding(.horizontal)
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
                Text("Four mixes. Independent destinations.").font(.headline)
                Text("Assign each mix a distinct endpoint from Smixx Out 1–4. To send the same balance to several destinations, expand the mixer and choose “Use the same mix as” for each follower. These endpoints appear after installing the Smixx Audio driver. Keep headphones on a physical output. Driver delivery and app consumption must be verified separately.").font(.callout).foregroundStyle(.secondary)
                ForEach(0..<4, id: \.self) { index in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Mix name", text: Binding(get: { store.state.outputs[index].name }, set: { value in store.edit { $0.outputs[index].name = value } }))
                                .font(.headline).accessibilityLabel("Output \(index + 1) name")
                            Picker("Purpose", selection: Binding(get: { store.state.outputs[index].role }, set: { value in store.edit { $0.outputs[index].role = value } })) {
                                Text("Meeting send").tag(OutputRole.meeting); Text("Headphones").tag(OutputRole.headphones)
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
                Text("Changing a destination mutes it. Select its mix and unmute deliberately. Two outputs cannot share one endpoint in this prototype.").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
    }
    private var workflow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text("First, listen through headphones").font(.title3.bold())
                Text("1. Assign your physical headphones or interface to the Headphones mix in Outputs.")
                Text("2. Choose up to five hardware or application sources in the mixer. Any slot can hold any supported source.")
                Text("3. Select Headphones, enable the intended sends, then unmute those sources and the output. Begin at a low output level.")
                Text("4. Expand the mixer for input gain, mix links, custom names, and output solos.")
                Divider()
                Text("Application capture").font(.headline)
                Text("Capture copy leaves the app’s normal playback audible. Route playback explicitly suppresses its original playback while Smixx captures it, letting Smixx control what reaches your headphones. Use that option for Teams return to avoid hearing it twice. Allow system-audio recording when macOS asks.")
                Text("Applications appear when Core Audio exposes their audio processes. Open the app and play audio if it is missing. Some helper-process apps may need further compatibility work.")
                Divider()
                Text("Meeting and recording feeds").font(.headline)
                Text("The Smixx installer includes the Smixx Audio driver. After installation and an audio-service restart, choose Smixx Out 1 as Teams’ microphone and Smixx Out 3 as an OBS Audio Input Capture source. Select those same endpoints for the corresponding Smixx output mixes. Teams return is blocked from meeting sends. Do not enable duplicate microphone or desktop captures in OBS. Integration remains unverified until a real listener and recording confirm the intended audio.")
                Text("Global M and S affect every output. Mute wins; a muted solo selection remains pending until unmuted. To remove a source from just one mix, turn off that mix’s send checkbox.")
                Text("Closing the mixer keeps audio running. Use Quit Smixx Desktop to stop capture and output.")
            }.font(.callout).padding()
        }
    }
    private var diagnostics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connection is separate from signal").font(.headline)
                Text("Meters show the audio processed by Smixx. Endpoint callbacks do not prove that Teams is transmitting or OBS is recording.").foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { i in Text("Source \(i + 1): \(store.sourceStatus[i])").textSelection(.enabled) }
                Divider()
                ForEach(0..<4, id: \.self) { i in Text("\(store.state.outputs[i].name): \(store.outputStatus[i])").textSelection(.enabled) }
                Divider()
                Text("Buffer underrun/overrun events: \(store.dropouts)").monospacedDigit()
                Text("macOS 14.2+ · Core Audio · optional Smixx Audio transport").foregroundStyle(.secondary)
                Button("Retry audio and refresh devices") { store.retry() }
                Text("Retry briefly restarts all configured capture and output paths. Device reconnects are otherwise handled individually.").font(.caption).foregroundStyle(.secondary)
                Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!) }
                if store.needsReset { Button("Back up invalid settings and start fresh") { store.resetInvalidConfiguration() } }
                if let message = store.message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
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
