import Foundation

public enum SourceKind: String, Codable { case device, application }
public struct SourceReference: Codable, Equatable, Hashable {
    public var kind: SourceKind
    public var uid: String
    public var name: String
    public var channel: Int
    public var stereo: Bool
    public var routeAppPlayback: Bool
    public init(kind: SourceKind, uid: String, name: String, channel: Int = 0, stereo: Bool = true, routeAppPlayback: Bool = false) {
        self.kind = kind; self.uid = uid; self.name = name; self.channel = channel; self.stereo = stereo; self.routeAppPlayback = routeAppPlayback
    }
    public var identity: String { "\(kind.rawValue):\(uid):\(channel):\(stereo):\(routeAppPlayback)" }
}
public struct SourceSlot: Codable, Equatable, Identifiable {
    public var id: Int
    public var source: SourceReference?
    public var customName = ""
    public var gainDB: Double = 0
    public var muted = true
    // Transient: deliberately excluded from persistence.
    public var solo = false
    public var name: String { customName.isEmpty ? (source?.name ?? "Choose source") : customName }
    enum CodingKeys: String, CodingKey { case id, source, customName, gainDB, muted }
    public init(id: Int) { self.id = id }
}
public struct Send: Codable, Equatable {
    public var enabled = true
    public var levelDB: Double = 0
    public init(enabled: Bool = true, levelDB: Double = 0) { self.enabled = enabled; self.levelDB = levelDB }
}
public enum OutputRole: String, Codable, CaseIterable { case meeting, headphones, recording, custom }
public struct OutputMix: Codable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var role: OutputRole
    public var endpointUID: String?
    public var endpointName: String?
    public var sends = Array(repeating: Send(), count: 5)
    public var leader: Int?
    public var levelDB: Double = 0
    public var muted = true
    public var solo = false
    enum CodingKeys: String, CodingKey { case id, name, role, endpointUID, endpointName, sends, leader, levelDB, muted }
    public init(id: Int, name: String, role: OutputRole) { self.id = id; self.name = name; self.role = role }
}
public enum MixerError: LocalizedError {
    case invalidConfiguration, invalidLink, leaderHasFollowers, duplicateOutput, outgoingCapture, meetingReturn
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "The saved configuration is invalid or from an unsupported version. The file has been preserved."
        case .invalidLink: return "Choose a different independent mix. Links cannot form chains or cycles."
        case .leaderHasFollowers: return "Make this mix’s followers independent before linking it to another mix."
        case .outgoingCapture: return "An outgoing virtual feed cannot also be a Smixx input. Use isolated application capture for Teams return."
        case .meetingReturn: return "Teams return cannot be sent to the Teams meeting mix. Send it to headphones or the recording mix instead."
        case .duplicateOutput: return "This endpoint already belongs to another output. Choose distinct endpoints for independent mixes."
        }
    }
}
public struct MixerState: Codable, Equatable {
    public var version = 1
    public var sources = (0..<5).map { SourceSlot(id: $0) }
    public var outputs = SmixxTransport.orderedUIDs.enumerated().map { index, uid in
        var mix = OutputMix(id: index, name: "Smixx Out \(index + 1)", role: [OutputRole.meeting, .custom, .recording, .custom][index])
        mix.endpointUID = uid; mix.endpointName = mix.name
        return mix
    }
    public var selectedOutput = 0
    // Optional for decoding configurations saved before input-menu preferences existed.
    public private(set) var hiddenInputs: [String: String]?
    public static func inputMenuKey(_ kind: SourceKind, _ uid: String) -> String { "\(kind.rawValue):\(uid)" }
    public func offers(_ source: SourceReference) -> Bool {
        hiddenInputs?[Self.inputMenuKey(source.kind, source.uid)] == nil
    }
    public mutating func setInputVisible(_ visible: Bool, key: String, name: String) {
        var hidden = hiddenInputs ?? [:]
        if visible { hidden.removeValue(forKey: key) } else { hidden[key] = name }
        hiddenInputs = hidden.isEmpty ? nil : hidden
    }
    public mutating func showAllInputs() { hiddenInputs = nil }
    public var expanded = false
    public init() {}
    public func effectiveSends(_ output: Int) -> [Send] { outputs[outputs[output].leader ?? output].sends }
    public var hasSolos: Bool { sources.contains { $0.solo } || outputs.contains { $0.solo } }
    public mutating func clearSolos() {
        for i in sources.indices { sources[i].solo = false }
        for i in outputs.indices { outputs[i].solo = false }
    }
    public mutating func assign(_ reference: SourceReference?, to slot: Int) {
        guard sources[slot].source?.identity != reference?.identity else { return }
        sources[slot].muted = true; sources[slot].solo = false; sources[slot].source = reference
        // Independent meeting mixes exclude their own return on assignment.
        // Linked mixes still pass through the usual atomic isolation check.
        if let reference, reference.kind == .application, reference.uid.lowercased().hasPrefix("com.microsoft.teams") {
            for i in outputs.indices where outputs[i].leader == nil && (outputs[i].role == .meeting || outputs[i].endpointUID == SmixxTransport.meetingUID) {
                outputs[i].sends[slot].enabled = false
            }
        }
    }
    public mutating func assignOutput(_ uid: String?, name: String?, to output: Int) throws {
        guard outputs[output].endpointUID != uid else { return }
        if let uid, outputs.contains(where: { $0.id != output && $0.endpointUID == uid }) { throw MixerError.duplicateOutput }
        outputs[output].muted = true; outputs[output].endpointUID = uid; outputs[output].endpointName = name
    }
    public mutating func link(_ follower: Int, to leader: Int?) throws {
        if let leader {
            guard outputs.indices.contains(leader), follower != leader, outputs[leader].leader == nil else { throw MixerError.invalidLink }
            guard !outputs.contains(where: { $0.leader == follower }) else { throw MixerError.leaderHasFollowers }
            outputs[follower].leader = leader
        } else {
            let values = effectiveSends(follower)
            outputs[follower].leader = nil; outputs[follower].sends = values
        }
    }
    public func sourceEligible(_ i: Int) -> Bool {
        !sources[i].muted && (!sources.contains { $0.solo } || sources[i].solo)
    }
    public func outputEligible(_ i: Int) -> Bool {
        !outputs[i].muted && (!outputs.contains { $0.solo } || outputs[i].solo)
    }
    public func routeGain(source: Int, output: Int) -> Float {
        let send = effectiveSends(output)[source]
        guard sourceEligible(source), outputEligible(output), send.enabled else { return 0 }
        return Self.amplitude(sources[source].gainDB) * Self.amplitude(send.levelDB) * Self.amplitude(outputs[output].levelDB)
    }
    public static func amplitude(_ db: Double) -> Float { db <= -60 ? 0 : Float(pow(10, db / 20)) }
    // Conservative warnings also cover hardware return feeds whose contents are not knowable.
    // Names are not used to establish meeting roles. All app captures sent to a meeting require confirmation.
    public func risks() -> Set<String> {
        var result = Set<String>()
        for output in outputs where output.role == .meeting {
            for (i, send) in effectiveSends(output.id).enumerated() where send.enabled {
                guard let source = sources[i].source else { continue }
                result.insert("Meeting route: \(source.identity) → \(output.endpointUID ?? "unassigned") (mix \(output.id)). Verify this source excludes meeting return and overlapping captures.")
            }
        }
        for output in outputs {
            for (i, send) in effectiveSends(output.id).enumerated() where send.enabled {
                if let source = sources[i].source, source.kind == .device, source.uid == output.endpointUID {
                    result.insert("Possible hardware loop: source \(i + 1) and \(output.name) use the same device. Verify channel routing and direct monitoring.")
                }
            }
        }
        return result
    }
    public func checkTransportIsolation() throws {
        let transports = Set(outputs.compactMap(\.endpointUID).filter { $0.lowercased().hasPrefix("blackhole") }).union(SmixxTransport.feedUIDs)
        for output in outputs where output.role == .meeting || output.endpointUID == SmixxTransport.meetingUID {
            for (index, send) in effectiveSends(output.id).enumerated() where send.enabled {
                if let ref = sources[index].source, ref.kind == .application, ref.uid.lowercased().hasPrefix("com.microsoft.teams") {
                    throw MixerError.meetingReturn
                }
            }
        }
        if sources.contains(where: { $0.source?.kind == .device && transports.contains($0.source?.uid ?? "") }) {
            throw MixerError.outgoingCapture
        }
    }
    public func validated() throws -> MixerState {
        guard version == 1, sources.count == 5, outputs.count == 4,
              sources.map(\.id) == Array(0..<5), outputs.map(\.id) == Array(0..<4), (0..<4).contains(selectedOutput),
              sources.allSatisfy({ $0.gainDB.isFinite && (-60...12).contains($0.gainDB) && ($0.source?.channel ?? 0) >= 0 }),
              outputs.allSatisfy({ $0.sends.count == 5 && $0.levelDB.isFinite && (-60...12).contains($0.levelDB) && $0.sends.allSatisfy { $0.levelDB.isFinite && (-60...12).contains($0.levelDB) } }) else { throw MixerError.invalidConfiguration }
        for output in outputs {
            if let leader = output.leader {
                guard (0..<4).contains(leader), leader != output.id, outputs[leader].leader == nil else { throw MixerError.invalidConfiguration }
            }
        }
        let endpoints = outputs.compactMap(\.endpointUID)
        guard Set(endpoints).count == endpoints.count else { throw MixerError.invalidConfiguration }
        try checkTransportIsolation()
        var result = self
        for i in result.outputs.indices {
            if result.outputs[i].name == ["Teams call", "Headphones", "OBS recording", "Output 4"][i] {
                result.outputs[i].name = "Smixx Out \(i + 1)"
            }
            if let uid = result.outputs[i].endpointUID, let n = SmixxTransport.orderedUIDs.firstIndex(of: uid) {
                result.outputs[i].endpointName = "Smixx Out \(n + 1)"
            }
        }
        result.clearSolos(); return result
    }
}
public enum ConfigurationFile {
    public static func load(_ url: URL) throws -> MixerState {
        try JSONDecoder().decode(MixerState.self, from: Data(contentsOf: url)).validated()
    }
    public static func save(_ state: MixerState, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

/// Transport identities only. The mixer and Core Audio adapter do not link libASPL.
/// Replacing the driver with another endpoint transport leaves the five-by-four model intact.
public enum SmixxTransport {
    public static let meetingUID = "org.smixx.audio.meeting"
    public static let recordingUID = "org.smixx.audio.recording"
    public static let orderedUIDs = [meetingUID, "org.smixx.audio.out2", recordingUID, "org.smixx.audio.out4"]
    public static let feedUIDs = Set(orderedUIDs)
}
