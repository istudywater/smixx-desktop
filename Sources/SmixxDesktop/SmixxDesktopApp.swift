import AppKit
import SwiftUI
import SmixxCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    weak var store: MixerStore?
    func applicationDidFinishLaunching(_ notification: Notification) { Self.shared = self }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store?.shutdown() }
}

@main struct SmixxDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store: MixerStore
    init() {
        if CommandLine.arguments.contains("--devices") {
            let inventory = HardwareInventory.scan()
            for d in inventory.devices { print("\(d.name) | UID=\(d.uid) | inputs=\(d.inputs) outputs=\(d.outputs) | \(d.rate) Hz") }
            for a in inventory.apps { print("App: \(a.name) | \(a.id) | \(a.processes)") }
            exit(0)
        }
        _store = StateObject(wrappedValue: MixerStore())
    }
    var body: some Scene {
        Window("Smixx Desktop", id: "mixer") { MixerView(store: store).onAppear { delegate.store = store } }
            .defaultSize(width: 850, height: 630)
            .windowResizability(.contentMinSize)
            .commands {
                CommandGroup(replacing: .appSettings) { Button("Smixx Setup…") { store.showSetup = true }.keyboardShortcut(",") }
                CommandMenu("Mixer") {
                    Button("Clear all solos") { store.clearSolos() }.keyboardShortcut("s", modifiers: [.command, .shift])
                    Button("Clear peak indicators") { store.clearPeaks() }
                    Button("Retry audio") { store.retry() }
                }
            }
        MenuBarExtra("Smixx Desktop", systemImage: "waveform.path") { MixerMenu(store: store) }
    }
}
private struct MixerMenu: View {
    @ObservedObject var store: MixerStore
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Button("Open mixer") { openWindow(id: "mixer"); NSApp.activate(ignoringOtherApps: true) }
        if store.state.hasSolos { Text("Solo selections active or pending") }
        Divider()
        ForEach(0..<5, id: \.self) { i in
            Menu("\(i + 1). \(store.state.sources[i].name)") {
                Toggle("Mute in all outputs", isOn: Binding(get: { store.state.sources[i].muted }, set: { value in store.edit { $0.sources[i].muted = value } }))
                Toggle(store.state.sources[i].muted ? "Solo (pending while muted)" : "Solo in all outputs", isOn: Binding(get: { store.state.sources[i].solo }, set: { value in store.edit { $0.sources[i].solo = value } }))
                Text(store.sourceStatus[i])
            }
        }
        Divider()
        ForEach(0..<4, id: \.self) { i in Text("\(store.state.outputs[i].name): \(store.outputStatus[i])") }
        Button("Clear all solos") { store.clearSolos() }.disabled(!store.state.hasSolos)
        Divider()
        Button("Quit Smixx Desktop") { store.shutdown(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
