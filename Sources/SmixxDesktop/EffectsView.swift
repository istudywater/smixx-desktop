import SwiftUI
import SmixxCore

struct EffectsView: View {
    @ObservedObject var store: MixerStore
    let target: EffectsTarget
    @Environment(\.dismiss) private var dismiss
    private var effects: Effects { target.bus ? (store.state.outputs[target.index].effects ?? .bus) : (store.state.sources[target.index].effects ?? Effects()) }
    private var title: String { target.bus ? "Smixx Bus \(target.index + 1) effects" : "\(store.state.sources[target.index].name) · shared details" }
    private func flag(_ key: WritableKeyPath<Effects, Bool>) -> Binding<Bool> {
        Binding(get: { effects[keyPath: key] }, set: { value in store.updateEffects(target) { $0[keyPath: key] = value } })
    }
    private func number(_ name: String, _ key: WritableKeyPath<Effects, Double>, _ range: ClosedRange<Double>, unit: String) -> some View {
        let value = Binding<Double>(get: { effects[keyPath: key] }, set: { value in if value.isFinite && range.contains(value) { store.updateEffects(target) { $0[keyPath: key] = value } } })
        return HStack {
            Text(name).frame(width: 135, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(name)
            TextField(name, value: value, format: .number.precision(.fractionLength(1))).frame(width: 70).textFieldStyle(.roundedBorder).accessibilityLabel("\(name) in \(unit)")
            Text(unit).font(.caption).frame(width: 28)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.title3.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(target.bus ? "Processing affects only this outgoing bus." : "Assignment, input trim, global mute, EQ and compressor affect this source in all three buses and headphones.").foregroundStyle(.secondary)
                    if !target.bus {
                        Toggle("Mute source everywhere", isOn: Binding(get: { store.state.sources[target.index].muted }, set: { value in store.edit { $0.sources[target.index].muted = value } }))
                        Text("New and replacement sources start with Send off in all buses, but remain audible in headphones. Enable Send on the mixer for intended outgoing routes. An existing global mute must also be cleared here.").font(.caption)
                        HStack {
                            Text("Shared input trim")
                            Slider(value: Binding(get: { store.state.sources[target.index].gainDB }, set: { value in store.edit { $0.sources[target.index].gainDB = value } }), in: -60...12, step: 0.5).accessibilityLabel("Shared input trim in all buses")
                            Text(String(format: "%.1f dB", store.state.sources[target.index].gainDB))
                        }
                        GroupBox("EQ · shared") {
                            VStack(alignment: .leading) {
                                Toggle("Enable EQ (off = bypass)", isOn: flag(\.eqEnabled))
                                number("High-pass cutoff", \.highPassHz, 20...500, unit: "Hz")
                                number("Low shelf · 150 Hz", \.lowDB, -12...12, unit: "dB")
                                number("Mid · 1 kHz", \.midDB, -12...12, unit: "dB")
                                number("High shelf · 6 kHz", \.highDB, -12...12, unit: "dB")
                                HStack {
                                    Button("Reset EQ") { store.updateEffects(target) { $0.eqEnabled = false; $0.highPassHz = 80; $0.lowDB = 0; $0.midDB = 0; $0.highDB = 0 } }
                                    Button("Voice cleanup") { store.updateEffects(target) { $0.eqEnabled = true; $0.highPassHz = 80; $0.lowDB = -2; $0.midDB = 0; $0.highDB = 1 } }
                                }
                            }.padding(6)
                        }
                    }
                    GroupBox("Apple compressor") {
                        VStack(alignment: .leading) {
                            Toggle("Enable compressor (off = bypass)", isOn: flag(\.compressorEnabled))
                            number("Threshold", \.thresholdDB, -60...0, unit: "dB")
                            number("Headroom", \.headroomDB, 0.1...40, unit: "dB")
                            number("Attack", \.attackMS, 1...300, unit: "ms")
                            number("Release", \.releaseMS, 10...3000, unit: "ms")
                            Text("Lower headroom means stronger compression. Makeup gain stays at 0 dB; expansion is disabled. This unit does not expose a conventional ratio. Gain-reduction metering is unavailable in the verified parameter list.").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("Reset compressor") { store.updateEffects(target) { $0.compressorEnabled = false; $0.thresholdDB = -18; $0.headroomDB = 10; $0.attackMS = 10; $0.releaseMS = 100 } }
                                Button("Gentle voice") { store.updateEffects(target) { $0.compressorEnabled = true; $0.thresholdDB = -18; $0.headroomDB = 10; $0.attackMS = 10; $0.releaseMS = 150 } }
                            }
                        }.padding(6)
                    }
                    if target.bus {
                        GroupBox("Final Apple peak limiter") {
                            VStack(alignment: .leading) {
                                Toggle("Enable limiter (off = bypass)", isOn: flag(\.limiterEnabled))
                                number("Release", \.limiterReleaseMS, 1...40, unit: "ms")
                                number("Pre-gain", \.limiterPreGainDB, -40...0, unit: "dB")
                                Text("Attack/lookahead is fixed at 2 ms to keep latency stable. No true-peak claim. Reduce source levels if distortion occurs before this stage; bypass removes peak protection.").font(.caption).foregroundStyle(.secondary)
                                Button("Reset to peak-catching safeguard") { store.updateEffects(target) { $0.limiterEnabled = true; $0.limiterAttackMS = 2; $0.limiterReleaseMS = 5; $0.limiterPreGainDB = 0 } }
                            }.padding(6)
                        }
                    }
                    HStack {
                        Button("Bypass all") { store.updateEffects(target) { $0.eqEnabled = false; $0.compressorEnabled = false; $0.limiterEnabled = false } }
                        Button("Reset all") { store.updateEffects(target) { $0 = target.bus ? .bus : Effects() } }
                        Spacer()
                        Text(effects.enabled ? "● Processing enabled" : "Processing bypassed").font(.caption)
                    }
                }.padding()
            }
        }.frame(width: 590, height: 650).tint(accent)
    }
}
