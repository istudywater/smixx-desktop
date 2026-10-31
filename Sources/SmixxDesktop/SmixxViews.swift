import SwiftUI
import SmixxCore

private let accent = Color(red: 0.20, green: 0.69, blue: 0.59)

struct MixerView: View {
    @ObservedObject var store: MixerStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    SourceRow(store: store, index: index)
                    if index < 4 { Divider().padding(.leading, 30) }
                }
            }.padding(.horizontal, 14)
            Divider()
            master.padding(14).background(.quaternary.opacity(0.35))
            Divider()
            footer.padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: store.state.expanded ? 620 : 440)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(store.selectedOutput.name).font(.headline).lineLimit(1).help(store.selectedOutput.name)
                Spacer()
                Text("OUTPUT MIX").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                LevelControl(value: Binding(get: { store.selectedOutput.levelDB }, set: { value in store.edit { $0.outputs[store.selected].levelDB = value } }), label: "\(store.selectedOutput.name) output level")
                stateButton(store.selectedOutput.muted ? "Muted" : "Mute", active: store.selectedOutput.muted, color: .orange, label: "Mute output \(store.selectedOutput.name)") {
                    store.edit { $0.outputs[store.selected].muted.toggle() }
                }
                if store.state.expanded {
                    stateButton(store.selectedOutput.solo && store.selectedOutput.muted ? "Solo pending" : "Solo", active: store.selectedOutput.solo && !store.selectedOutput.muted, color: accent, label: "Solo output \(store.selectedOutput.name); suppress other unselected outputs") {
                        store.edit { $0.outputs[store.selected].solo.toggle() }
                    }
                }
            }
            Meter(value: store.outputPeaks[store.selected], clipping: store.outputClips[store.selected], label: "\(store.selectedOutput.name) post-master mix signal", clear: store.clearPeaks)
            if store.state.expanded {
                Text(store.outputStatus[store.selected]).font(.caption).foregroundStyle(.secondary)
                Picker("Use the same mix as", selection: Binding(get: { store.selectedOutput.leader ?? -1 }, set: { value in store.edit { try $0.link(store.selected, to: value < 0 ? nil : value) } })) {
                    Text("Independent").tag(-1)
                    ForEach(store.state.outputs.filter { $0.id != store.selected && $0.leader == nil }) { output in Text(output.name).tag(output.id) }
                }.font(.caption)
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

private struct SourceRow: View {
    @ObservedObject var store: MixerStore
    let index: Int
    private var source: SourceSlot { store.state.sources[index] }
    private var send: Send { store.sends[index] }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(String(index + 1)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16)
                Picker("Source \(index + 1)", selection: Binding(get: { source.source?.identity ?? "none" }, set: { store.setSource(index, identity: $0) })) {
                    Text("Choose source").tag("none")
                    if let saved = source.source, !store.inventory.sources.contains(where: { $0.identity == saved.identity }) {
                        Text("\(saved.name) · unavailable").tag(saved.identity)
                    }
                    ForEach(store.inventory.sources, id: \.identity) { reference in Text(reference.name).tag(reference.identity) }
                }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    .help(source.source?.name ?? "Select any available hardware or application source")
                if !source.customName.isEmpty { Text(source.customName).font(.caption).lineLimit(1).help(source.customName) }
                Image(systemName: source.source == nil ? "circle.dotted" : (store.sourceStatus[index].hasPrefix("Capture receiving") ? "waveform" : "info.circle"))
                    .foregroundStyle(.secondary).font(.caption).help(store.sourceStatus[index])
                    .accessibilityLabel(store.sourceStatus[index])
            }
            HStack(spacing: 7) {
                Toggle(isOn: Binding(get: { send.enabled }, set: { value in store.edit { $0.outputs[store.selected].sends[index].enabled = value } })) { EmptyView() }
                    .toggleStyle(.checkbox).labelsHidden().frame(width: 16)
                    .disabled(store.selectedOutput.leader != nil)
                    .help("Enable \(source.name) send to \(store.selectedOutput.name)")
                    .accessibilityLabel("Send \(source.name) to \(store.selectedOutput.name)")
                LevelControl(value: Binding(get: { send.levelDB }, set: { value in store.edit { $0.outputs[store.selected].sends[index].levelDB = value } }), label: "\(source.name) level to \(store.selectedOutput.name)")
                    .disabled(store.selectedOutput.leader != nil)
                stateButton("M", active: source.muted, color: .orange, label: "Mute \(source.name) in all outputs") { store.edit { $0.sources[index].muted.toggle() } }
                stateButton(source.muted && source.solo ? "S…" : "S", active: source.solo && !source.muted, color: accent, label: source.muted && source.solo ? "\(source.name) muted, solo pending; unmute to activate" : "Solo \(source.name) in all outputs") { store.edit { $0.sources[index].solo.toggle() } }
            }
            Meter(value: store.sourcePeaks[index], clipping: store.sourceClips[index], label: "\(source.name) input activity before mute", clear: store.clearPeaks)
                .padding(.leading, 23)
            if store.state.expanded {
                HStack {
                    TextField("Display name", text: Binding(get: { source.customName }, set: { value in store.edit { $0.sources[index].customName = value } })).frame(width: 135)
                        .accessibilityLabel("Source \(index + 1) display name")
                    Text("Input gain · all outputs").font(.caption).foregroundStyle(.secondary)
                    LevelControl(value: Binding(get: { source.gainDB }, set: { value in store.edit { $0.sources[index].gainDB = value } }), label: "\(source.name) input gain for all outputs")
                }
                Text(store.sourceStatus[index]).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 9)
    }
}

@ViewBuilder private func stateButton(_ title: String, active: Bool, color: Color, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).font(.caption.weight(.semibold)).frame(minWidth: 17) }
        .buttonStyle(.bordered).tint(active ? color : .secondary)
        .help(label).accessibilityLabel(label).accessibilityValue(active ? "On" : "Off")
}

private struct LevelControl: View {
    @Binding var value: Double
    let label: String
    @State private var entry = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 5) {
            Slider(value: $value, in: -60...12, step: 0.5).accessibilityLabel(label).help("\(label). 0 dB is unity. Control-click to reset.")
                .contextMenu { Button("Reset to unity (0 dB)") { value = 0 } }
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
                outputs.tabItem { Label("Outputs", systemImage: "cable.connector") }
                workflow.tabItem { Label("Getting started", systemImage: "list.number") }
                diagnostics.tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            }.padding(.horizontal)
        }.frame(width: 610, height: 600).tint(accent)
    }
    private var outputs: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Four mixes. Independent destinations.").font(.headline)
                Text("Native device outputs are available now. Sending a mix into Teams or OBS as a microphone requires a separately installed virtual audio endpoint; none is bundled.").font(.callout).foregroundStyle(.secondary)
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
                Text("This build does not create a virtual microphone. Teams and OBS feed integration is unverified until an external endpoint is installed and tested. Keep meeting return disabled in the meeting-send mix. Never capture an outgoing loopback feed as a source.")
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
                Text("macOS 14.2+ · native Core Audio · no bundled drivers").foregroundStyle(.secondary)
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
