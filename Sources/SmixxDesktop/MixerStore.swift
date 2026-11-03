import SwiftUI
import AVFoundation
import SmixxCore
import MixerDSP

@MainActor final class MixerStore: ObservableObject {
    @Published private(set) var state = MixerState()
    @Published private(set) var inventory = HardwareInventory()
    @Published var sourceStatus = Array(repeating: "Choose source", count: 6)
    @Published var outputStatus = Array(repeating: "Choose destination", count: 3)
    @Published var sourcePeaks = Array(repeating: Float(0), count: 6)
    @Published var outputPeaks = Array(repeating: Float(0), count: 3)
    @Published var sourceClips = Array(repeating: false, count: 6)
    @Published var preLimiterClips = Array(repeating: false, count: 3)
    @Published var outputClips = Array(repeating: false, count: 3)
    @Published var monitorStatus = "Choose headphones in Setup"
    @Published var effectErrors: UInt64 = 0
    @Published var effectsTarget: EffectsTarget?
    @Published var message: String?
    @Published var showSetup = false
    @Published var setupSection = 0
    @Published var dropouts: UInt64 = 0
    let dsp: OpaquePointer
    private var captures: [Int: AudioConnection] = [:]
    private var monitorPlayback: AudioConnection?
    private var playback: [Int: AudioConnection] = [:]
    private var attempts: [String: String] = [:]
    private var timer: Timer?
    private var saveTimer: Timer?
    private var ticks = 0
    private var loadFailed = false
    private var permissionRequested = false
    private var lastCaptureCounts = Array(repeating: UInt64(0), count: 6)
    private var lastRenderCounts = Array(repeating: UInt64(0), count: 3)
    private var wakeObserver: NSObjectProtocol?
    private let preview = CommandLine.arguments.contains("--preview") || Bundle.main.object(forInfoDictionaryKey: "SmixxLayoutPreview") as? Bool == true
    private let configurationURL: URL
    init() {
        dsp = sm_create()!
        configurationURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SmixxDesktop/configuration.json")
        if preview { message = "Layout preview · audio and persistence disabled"; return }
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            do { state = try ConfigurationFile.load(configurationURL); message = state.migrationNotice }
            catch { message = error.localizedDescription; loadFailed = true }
        }
        inventory = HardwareInventory.scan()
        applyGains() // All gains are zero until endpoints are connected.
        reconcile()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.retry() }
        }
    }
    var offeredSources: [SourceReference] { inventory.sources.filter(state.offers) }
    var selected: Int { state.selectedOutput }
    var sends: [Send] { state.effectiveSends(selected) }
    var selectedOutput: OutputMix { state.outputs[selected] }
    var duplicateWarning: String? {
        let assigned = state.sources.compactMap(\.source)
        if Set(assigned.map(\.identity)).count < assigned.count { return "Duplicate source: each slot has separate mute controls and may double the audio." }
        return nil
    }
    func edit(_ mutation: (inout MixerState) throws -> Void) {
        var next = state
        do { try mutation(&next); try next.checkTransportIsolation() } catch { message = error.localizedDescription; return }
        guard next != state else { return }
        for i in 0..<6 where next.sources[i].source?.routeAppPlayback == true && next.sources[i].source != state.sources[i].source {
            let alert = NSAlert(); alert.messageText = "Route this app’s playback through Smixx?"
            alert.informativeText = "The app’s original playback will be suppressed while capture is running. Choose and unmute your headphone device to hear it through Smixx. Headphones hear sources before Send and bus M/S. Keep Teams Send off in the meeting bus to prevent echo. Quitting Smixx restores original playback."
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Route playback")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        let risks = next.risks().subtracting(state.risks())
        if !risks.isEmpty {
            let alert = NSAlert(); alert.messageText = "Check this route before applying"
            alert.informativeText = "Sending meeting return back to the meeting causes echo. Confirm the selected source contains only intended audio.\n\n" + risks.sorted().joined(separator: "\n\n")
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Apply route")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        // Install new mute states before stopping/replacing any device.
        state = next; applyGains(); reconcile(); scheduleSave()
    }
    func setSource(_ slot: Int, identity: String) {
        let reference = offeredSources.first { $0.identity == identity }
        guard reference != nil || identity == "none" else { return }
        edit { $0.assign(reference, to: slot) }
    }
    func setEndpoint(_ output: Int, uid: String) {
        let device = inventory.devices.first { $0.uid == uid }
        edit { try $0.assignOutput(device?.uid, name: device?.name, to: output) }
    }
    func setMonitorEndpoint(_ uid: String) {
        let device = inventory.devices.first { $0.uid == uid }
        edit { try $0.assignMonitor(device?.uid, name: device?.name) }
    }
    func updateEffects(_ target: EffectsTarget, _ mutation: (inout Effects) -> Void) {
        edit { state in
            var settings = target.bus ? (state.outputs[target.index].effects ?? .bus) : (state.sources[target.index].effects ?? Effects())
            mutation(&settings)
            guard settings.valid else { throw MixerError.invalidConfiguration }
            if target.bus { state.outputs[target.index].effects = settings } else { state.sources[target.index].effects = settings }
        }
    }
    func clearSolos() { edit { $0.clearSolos() } }
    func clearPeaks() { preLimiterClips = Array(repeating: false, count: 3); sourceClips = Array(repeating: false, count: 6); outputClips = Array(repeating: false, count: 3) }
    func select(_ output: Int) { edit { $0.selectedOutput = output } }
    func retry() {
        for i in 0..<6 { for o in 0..<4 { sm_set_gain(dsp, Int32(i), Int32(o), 0) } }
        captures.removeAll(); playback.removeAll(); monitorPlayback = nil; attempts.removeAll(); sm_reset(dsp)
        inventory = HardwareInventory.scan(); reconcile()
    }
    func shutdown() {
        timer?.invalidate(); saveTimer?.invalidate(); save()
        captures.removeAll(); playback.removeAll(); monitorPlayback = nil
    }
    func resetInvalidConfiguration() {
        let alert = NSAlert(); alert.messageText = "Start a new configuration?"
        alert.informativeText = "The unreadable configuration will be copied to a dated backup first. All routes start disabled."
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Back up and reset")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            let backup = configurationURL.deletingPathExtension().appendingPathExtension("backup-\(Int(Date().timeIntervalSince1970)).json")
            try FileManager.default.copyItem(at: configurationURL, to: backup)
            loadFailed = false; state = MixerState(); message = nil; retry(); save()
        } catch { message = error.localizedDescription }
    }
    var needsReset: Bool { loadFailed }
    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in Task { @MainActor in self?.save() } }
    }
    private func save() {
        guard !loadFailed && !preview else { return }
        do { try ConfigurationFile.save(state, to: configurationURL) }
        catch { message = "Could not save settings: \(error.localizedDescription)" }
    }
    private func applyEffects(_ e: Effects, bus: Bool, index: Int) {
        let values: [Float] = [e.eqEnabled ? 1 : 0, Float(e.highPassHz), Float(e.lowDB), Float(e.midDB), Float(e.highDB), e.compressorEnabled ? 1 : 0, Float(e.thresholdDB), Float(e.headroomDB), Float(e.attackMS / 1000), Float(e.releaseMS / 1000), e.limiterEnabled ? 1 : 0, 0.002, Float(e.limiterReleaseMS / 1000), Float(e.limiterPreGainDB)]
        for (p, value) in values.enumerated() { sm_set_effect(dsp, bus ? 1 : 0, Int32(index), Int32(p), value) }
    }
    private func applyGains() {
        for o in 0..<3 {
            applyEffects(state.outputs[o].effects ?? .bus, bus: true, index: o)
            sm_set_master(dsp, Int32(o), state.outputs[o].muted || playback[o] == nil ? 0 : MixerState.amplitude(state.outputs[o].levelDB))
        }
        let monitor = state.monitor
        sm_set_monitor(dsp, Int32(monitor.bus), monitor.muted || monitorPlayback == nil ? 0 : MixerState.amplitude(monitor.levelDB))
        for i in 0..<6 {
            applyEffects(state.sources[i].effects ?? Effects(), bus: false, index: i)
            sm_set_input_gain(dsp, Int32(i), MixerState.amplitude(state.sources[i].gainDB))
            sm_set_gain(dsp, Int32(i), 3, captures[i] != nil && monitorPlayback != nil ? state.headphoneGain(source: i) : 0)
            for o in 0..<3 {
                let connected = captures[i] != nil && playback[o] != nil
                sm_set_gain(dsp, Int32(i), Int32(o), connected ? state.routeGain(source: i, output: o) : 0)
            }
        }
    }
    private func reconcile() {
        guard !preview else { return }
        for i in 0..<6 {
            guard let reference = state.sources[i].source else { captures[i] = nil; attempts["s\(i)"] = nil; sourceStatus[i] = "Choose source"; continue }
            let device = inventory.devices.first { $0.uid == reference.uid }
            let app = inventory.apps.first { $0.id == reference.uid }
            let signature = reference.identity + ":\(device?.id ?? 0):\(device?.rate ?? 0):\(app?.processes ?? [])"
            if captures[i]?.signature == signature { continue }
            for o in 0..<4 { sm_set_gain(dsp, Int32(i), Int32(o), 0) }
            captures[i] = nil
            if attempts["s\(i)"] == signature { continue }
            attempts["s\(i)"] = signature
            if reference.kind == .device && AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
                sourceStatus[i] = "Microphone permission required — enable Smixx Desktop in Privacy & Security."
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined && !permissionRequested {
                    permissionRequested = true
                    AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in Task { @MainActor in self?.attempts.removeAll(); self?.reconcile() } }
                }
                continue
            }
            do {
                captures[i] = try AudioConnection(dsp: dsp, slot: i, source: reference, inventory: inventory, signature: signature)
                sourceStatus[i] = "Capture open · waiting for audio callbacks"
            } catch { sourceStatus[i] = error.localizedDescription }
        }
        for o in 0..<3 {
            guard let uid = state.outputs[o].endpointUID else { playback[o] = nil; attempts["o\(o)"] = nil; outputStatus[o] = "Choose destination in Setup"; continue }
            guard let device = inventory.devices.first(where: { $0.uid == uid && $0.outputs > 0 }) else {
                playback[o] = nil; attempts["o\(o)"] = nil; outputStatus[o] = "Disconnected · \(state.outputs[o].endpointName ?? uid)"; continue
            }
            let signature = "\(uid):\(device.id):\(device.rate)"
            if playback[o]?.signature == signature { continue }
            for i in 0..<6 { sm_set_gain(dsp, Int32(i), Int32(o), 0) }
            playback[o] = nil
            if attempts["o\(o)"] == signature { continue }
            attempts["o\(o)"] = signature
            do {
                playback[o] = try AudioConnection(dsp: dsp, output: o, device: device, signature: signature)
                outputStatus[o] = "Endpoint open · consumer status unknown"
            } catch { outputStatus[o] = error.localizedDescription }
        }
        reconcileMonitor()
        applyGains()
    }
    private func reconcileMonitor() {
        guard let uid = state.monitor.endpointUID else { monitorPlayback = nil; attempts["monitor"] = nil; monitorStatus = "Choose headphones in Setup"; return }
        guard let device = inventory.devices.first(where: { $0.uid == uid && $0.outputs >= 2 }) else {
            monitorPlayback = nil; attempts["monitor"] = nil; monitorStatus = "Headphones disconnected — reconnect the saved device"; return
        }
        let signature = "\(uid):\(device.id):\(device.rate)"
        if monitorPlayback?.signature == signature { return }
        sm_set_monitor(dsp, Int32(state.monitor.bus), 0); monitorPlayback = nil
        if attempts["monitor"] == signature { return }
        attempts["monitor"] = signature
        do { monitorPlayback = try AudioConnection(dsp: dsp, output: 3, device: device, signature: signature); monitorStatus = "Headphone endpoint open" }
        catch { monitorStatus = error.localizedDescription }
    }
    private func tick() {
        ticks += 1
        let visible = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
        if visible || ticks % 10 == 0 {
            for i in 0..<6 {
                let value = sm_take_source_peak(dsp, Int32(i)); sourcePeaks[i] = value; if value >= 1 { sourceClips[i] = true }
            }
            for o in 0..<3 {
                if sm_take_pre_limiter_peak(dsp, Int32(o)) >= 1 { preLimiterClips[o] = true }
                let value = sm_take_output_peak(dsp, Int32(o)); outputPeaks[o] = value; if value >= 1 { outputClips[o] = true }
            }
            dropouts = sm_dropouts(dsp); effectErrors = sm_effect_errors(dsp)
        }
        if ticks % 20 == 0 {
            let refreshed = HardwareInventory.scan()
            if refreshed != inventory { inventory = refreshed; reconcile() }
            for i in captures.keys {
                let count = sm_capture_count(dsp, Int32(i))
                sourceStatus[i] = count > lastCaptureCounts[i] ? "Capture receiving · \(state.sources[i].source?.stereo == true ? "stereo" : "mono")" : "Capture open · no callbacks; check playback or permissions"
                lastCaptureCounts[i] = count
            }
            if monitorPlayback != nil { monitorStatus = "Pre-Send balance \(state.monitor.bus + 1) · \(state.monitor.endpointName ?? "headphones")" }
            for o in playback.keys {
                let count = sm_render_count(dsp, Int32(o))
                outputStatus[o] = count > lastRenderCounts[o] ? "Endpoint receiving · app consumption unknown" : "Endpoint open · no delivery callbacks"
                lastRenderCounts[o] = count
            }
        }
    }
}

struct EffectsTarget: Identifiable { let bus: Bool; let index: Int; var id: String { "\(bus)-\(index)" } }
