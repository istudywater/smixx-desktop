import Testing
import Foundation
@testable import SmixxCore
import MixerDSP
import CoreAudio

struct MixerTests {
    func active() -> MixerState {
        var state = MixerState()
        for i in 0..<5 { state.sources[i].muted = false }
        for o in 0..<4 { state.outputs[o].muted = false; for i in 0..<5 { state.outputs[o].sends[i].enabled = true } }
        return state
    }
    @Test func testFreshConfigurationIsSilentAndInterchangeable() {
        let state = MixerState()
        expectTrue(state.outputs.flatMap(\.sends).allSatisfy(\.enabled))
        expectEqual(state.sources.count, 5); expectEqual(state.outputs.count, 4)
        for i in 0..<5 { for o in 0..<4 { expectEqual(state.routeGain(source: i, output: o), 0) } }
    }
    @Test func testGlobalMuteAndSendIsolation() {
        var state = active(); state.sources[2].muted = true
        for o in 0..<4 { expectEqual(state.routeGain(source: 2, output: o), 0) }
        state.outputs[0].sends[1].enabled = false
        expectEqual(state.routeGain(source: 1, output: 0), 0)
        expectEqual(state.routeGain(source: 1, output: 1), 1)
    }
    @Test func testMuteWinsAndSoloResumesOnUnmute() {
        var state = active(); state.sources[1].solo = true; state.sources[1].muted = true
        expectTrue(state.sources[1].solo)
        for i in 0..<5 { expectEqual(state.routeGain(source: i, output: 0), 0) }
        state.sources[1].muted = false
        expectEqual(state.routeGain(source: 1, output: 0), 1)
        expectEqual(state.routeGain(source: 0, output: 0), 0)
        state.clearSolos(); expectEqual(state.routeGain(source: 0, output: 0), 1)
    }
    @Test func testMultipleSourceAndOutputSolosIntersect() {
        var state = active(); state.sources[0].solo = true; state.sources[2].solo = true
        state.outputs[0].solo = true; state.outputs[2].solo = true; state.outputs[2].muted = true
        expectEqual(state.routeGain(source: 0, output: 0), 1)
        expectEqual(state.routeGain(source: 2, output: 0), 1)
        expectEqual(state.routeGain(source: 1, output: 0), 0)
        expectEqual(state.routeGain(source: 0, output: 1), 0)
        expectEqual(state.routeGain(source: 0, output: 2), 0)
        state.outputs[2].muted = false; expectEqual(state.routeGain(source: 2, output: 2), 1)
    }
    @Test func testReplacementMutesBeforeRoutingAndIdenticalAssignmentDoesNothing() {
        var state = active()
        let ref = SourceReference(kind: .device, uid: "device", name: "Microphone", stereo: false)
        for i in 0..<5 {
            state.sources[i].solo = true; state.assign(ref, to: i)
            expectTrue(state.sources[i].muted); expectFalse(state.sources[i].solo)
            state.sources[i].muted = false; state.assign(ref, to: i)
            expectFalse(state.sources[i].muted)
        }
    }
    @Test func testLinkedMixesAndIndependentMasters() throws {
        var state = active(); try state.link(2, to: 0)
        state.outputs[0].sends[1].levelDB = -6; state.outputs[2].levelDB = -6
        expectEqual(state.effectiveSends(2)[1].levelDB, -6)
        expectEqual(state.routeGain(source: 1, output: 2), pow(10, -12.0 / 20), accuracy: 0.0001)
        let before = state.routeGain(source: 1, output: 2)
        try state.link(2, to: nil); expectEqual(state.routeGain(source: 1, output: 2), before)
        state.outputs[0].sends[1].enabled = false; expectTrue(state.effectiveSends(2)[1].enabled)
    }
    @Test func testLinkRejectsCyclesChainsAndLeaderConversion() throws {
        var state = active(); try state.link(2, to: 0)
        expectThrows(try state.link(0, to: 2)); expectThrows(try state.link(1, to: 2))
        expectThrows(try state.link(0, to: 1)); expectThrows(try state.link(1, to: 1))
    }
    @Test func testPersistencePreservesMutesButDropsSolos() throws {
        var state = active(); state.sources[2].solo = true; state.sources[2].muted = true
        state.outputs[3].solo = true; state.outputs[3].muted = true; state.selectedOutput = 3
        let restored = try JSONDecoder().decode(MixerState.self, from: JSONEncoder().encode(state)).validated()
        expectTrue(restored.sources[2].muted); expectTrue(restored.outputs[3].muted)
        expectFalse(restored.hasSolos); expectEqual(restored.selectedOutput, 3)
    }
    @Test func testInvalidConfigurationRejected() {
        var state = active(); state.outputs[0].leader = 99; expectThrows(try state.validated())
        state = active(); state.sources[0].gainDB = .nan; expectThrows(try state.validated())
        state = active(); state.sources.removeLast(); expectThrows(try state.validated())
    }
    @Test func testFeedbackRiskThroughLinkAndLeaderEdits() throws {
        var state = MixerState(); state.sources[3].source = .init(kind: .application, uid: "com.microsoft.teams2", name: "Renamed app")
        state.outputs[2].sends[3].enabled = true
        state.outputs[0].sends[3].enabled = false
        let before = state.risks(); try state.link(0, to: 2)
        expectFalse(state.risks().subtracting(before).isEmpty)
        state.outputs[2].sends[3].enabled = false; expectTrue(state.risks().isEmpty)
        state.outputs[2].sends[3].enabled = true; expectFalse(state.risks().isEmpty)
    }
    @Test func testDestinationSelectionDoesNotChangeRouting() {
        var state = active(); let before = (0..<4).map { state.routeGain(source: 2, output: $0) }
        state.selectedOutput = 3; expectEqual(before, (0..<4).map { state.routeGain(source: 2, output: $0) })
    }
    @Test func testDuplicateOutputRejectedAndReplacementMuted() throws {
        var state = active(); try state.assignOutput("one", name: "First", to: 0)
        expectTrue(state.outputs[0].muted)
        expectThrows(try state.assignOutput("one", name: "First", to: 1))
    }
    @Test func testOutgoingTransportCannotBecomeAnInputInEitherOrder() throws {
        var state = MixerState()
        state.sources[0].source = .init(kind: .device, uid: "BlackHole2ch_UID", name: "Renamed feed")
        try state.assignOutput("BlackHole2ch_UID", name: "Meeting", to: 0)
        expectThrows(try state.checkTransportIsolation())
        expectThrows(try state.validated())
        state.assign(.init(kind: .application, uid: "com.microsoft.teams2", name: "Teams", routeAppPlayback: true), to: 0)
        try state.checkTransportIsolation()
    }
    @Test func testAppPlaybackModeIsPersistedAndReplacementIsMuted() throws {
        var state = active()
        let copy = SourceReference(kind: .application, uid: "app", name: "App")
        state.assign(copy, to: 1); state.sources[1].muted = false
        var routed = copy; routed.routeAppPlayback = true
        state.assign(routed, to: 1)
        expectTrue(state.sources[1].muted)
        let decoded = try JSONDecoder().decode(MixerState.self, from: JSONEncoder().encode(state))
        expectTrue(decoded.sources[1].source!.routeAppPlayback)
    }
    @Test func testAtomicFileRoundTripAndMalformedInput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("config.json")
        var state = active(); state.sources[4].gainDB = -12; state.outputs[2].muted = true
        try ConfigurationFile.save(state, to: url)
        expectEqual(try ConfigurationFile.load(url), state)
        try Data("{broken".utf8).write(to: url)
        expectThrows(try ConfigurationFile.load(url))
        expectEqual(try String(contentsOf: url, encoding: .utf8), "{broken")
    }
    @Test func testSmixxFeedsCannotBeCapturedAndTeamsReturnCannotBeSentBack() throws {
        var state = MixerState()
        state.sources[0].source = .init(kind: .device, uid: SmixxTransport.meetingUID, name: "Renamed")
        expectThrows(try state.checkTransportIsolation())
        state.assign(.init(kind: .application, uid: "com.microsoft.teams2", name: "Remote lesson"), to: 0)
        state.outputs[2].sends[0].enabled = true
        try state.checkTransportIsolation() // recording can include return
        try state.link(0, to: 2)
        expectThrows(try state.checkTransportIsolation()) // linking cannot bypass mix-minus
        try state.link(0, to: nil); state.outputs[0].sends[0].enabled = false
        state.outputs[2].endpointUID = SmixxTransport.meetingUID
        expectThrows(try state.checkTransportIsolation()) // role rename cannot bypass it
    }
    @Test func testInputVisibilityGroupsVariantsAndPreservesRoutes() throws {
        var state = MixerState()
        let mono = SourceReference(kind: .device, uid: "interface", name: "Channel 1", stereo: false)
        let pair = SourceReference(kind: .device, uid: "interface", name: "Stereo pair")
        state.assign(mono, to: 2)
        let before = state.sources
        state.setInputVisible(false, key: MixerState.inputMenuKey(.device, mono.uid), name: "Interface")
        expectFalse(state.offers(pair)); expectEqual(state.sources, before)
        let restored = try JSONDecoder().decode(MixerState.self, from: JSONEncoder().encode(state))
        expectFalse(restored.offers(mono))
        state.showAllInputs()
        let old = try JSONEncoder().encode(state) // nil preference is omitted, as in legacy files
        expectTrue(try JSONDecoder().decode(MixerState.self, from: old).offers(pair))
    }
    @Test func testDSPFiveInputsIndependentOutputsAndHardMute() {
        let dsp = sm_create()!; defer { sm_destroy(dsp) }
        for s in 0..<5 {
            sm_set_gain(dsp, Int32(s), 0, 1)
            sm_set_gain(dsp, Int32(s), 1, s == 0 ? 1 : 0)
            var input = Array(repeating: Float(s + 1) * 0.02, count: 4096)
            input.withUnsafeMutableBytes { bytes in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                sm_capture(dsp, Int32(s), &list, 0, 0)
            }
        }
        func render(_ output: Int32) -> [Float] {
            var samples = Array(repeating: Float(0), count: 2048)
            samples.withUnsafeMutableBytes { bytes in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                sm_render(dsp, output, &list, 48000)
            }
            return samples
        }
        expectEqual(render(0)[1000], 0.3, accuracy: 0.01)
        expectEqual(render(1)[1000], 0.02, accuracy: 0.001)
        for s in 0..<5 { sm_set_gain(dsp, Int32(s), 0, 0) }
        expectTrue(render(0).allSatisfy { $0 == 0 })
        expectGreater(sm_take_source_peak(dsp, 4), 0)
    }
}

private func expectEqual<T: Equatable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a == b, sourceLocation: sourceLocation) }
private func expectEqual<T: BinaryFloatingPoint>(_ a: T, _ b: T, accuracy: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(abs(a - b) <= accuracy, sourceLocation: sourceLocation) }
private func expectTrue(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(value, sourceLocation: sourceLocation) }
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) { #expect(!value, sourceLocation: sourceLocation) }
private func expectGreater<T: Comparable>(_ a: T, _ b: T, sourceLocation: SourceLocation = #_sourceLocation) { #expect(a > b, sourceLocation: sourceLocation) }
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) } catch {}
}
