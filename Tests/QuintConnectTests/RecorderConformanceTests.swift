#if os(macOS) || os(Linux)
    import Foundation
    import Testing

    @testable import QuintConnect

    /// The implementation under test: a small voice recorder with asynchronous mic acquisition and release.
    /// `Fixtures/recorder.qnt` is its specification.
    private struct Recorder {
        enum Phase: String, Decodable {
            case idle = "Idle"
            case acquiring = "Acquiring"
            case recording = "Recording"
            case paused = "Paused"
            case releasing = "Releasing"
            case finished = "Finished"
        }

        var phase = Phase.idle
        var micAcquired = false
        /// Plants the bug the model checker exists to catch: the mic is dropped as soon as Finish is pressed.
        var releasesMicEarly = false

        mutating func pressRecord() { phase = .acquiring }

        mutating func startListening() {
            phase = .recording
            micAcquired = true
        }

        mutating func pause() { phase = .paused }
        mutating func resume() { phase = .recording }

        mutating func pressFinish() {
            phase = .releasing
            if releasesMicEarly { micAcquired = false }
        }

        mutating func releaseMic() {
            phase = .finished
            micAcquired = false
        }
    }

    private struct RecorderDriver: Driver {
        struct Snapshot: Equatable, Sendable, Decodable {
            let state: String
            let micAcquired: Bool
        }

        var recorder = Recorder()

        mutating func step(_ step: Step) throws {
            switch step.actionTaken {
            case "init": recorder = Recorder(releasesMicEarly: recorder.releasesMicEarly)
            case "pressRecord": recorder.pressRecord()
            case "startListening": recorder.startListening()
            case "pause": recorder.pause()
            case "resume": recorder.resume()
            case "pressFinish": recorder.pressFinish()
            case "releaseMic": recorder.releaseMic()
            default: throw QuintConnectError.unhandledAction(step.actionTaken)
            }
        }

        func state() throws -> Snapshot {
            Snapshot(state: recorder.phase.rawValue.capitalized, micAcquired: recorder.micAcquired)
        }
    }

    /// Runs the real `quint` against the fixture specification. Needs `make setup` (the pinned Quint).
    @Suite(.enabled(if: Quint.pinned != nil, "run `make setup` to install the pinned Quint"))
    struct RecorderConformanceTests {
        private var quint: QuintExecutable { .path(Quint.pinned ?? URL(fileURLWithPath: "/missing")) }
        private let spec = Quint.fixture("recorder.qnt")

        @Test func simulatedTracesMatchTheImplementation() throws {
            let config = RunConfig(spec: spec, maxSamples: 50, maxSteps: 12, seed: "0x1", quint: quint)
            try QuintConnect.simulate(config) { RecorderDriver() }
        }

        @Test func scriptedTracesWithoutActionNamesExplainWhatToDo() throws {
            let config = TestConfig(
                spec: spec, test: "releaseIsAsynchronousTest", maxSamples: 1, seed: "0x1", quint: quint)
            do {
                try QuintConnect.replayTest(config) { RecorderDriver() }
                Issue.record("Expected a malformed trace error")
            } catch let QuintConnectError.malformedTrace(detail) {
                #expect(detail.contains("quint run --mbt"))
            }
        }

        @Test func anEarlyMicReleaseIsCaughtAsADivergence() throws {
            let config = RunConfig(spec: spec, maxSamples: 200, maxSteps: 12, seed: "0x1", quint: quint)
            do {
                try QuintConnect.simulate(config) { RecorderDriver(recorder: Recorder(releasesMicEarly: true)) }
                Issue.record("The planted bug was not detected")
            } catch let QuintConnectError.stateDivergence(_, _, action, diff) {
                #expect(action == "pressFinish")
                #expect(diff.contains("micAcquired"))
            }
        }

        @Test func quintErrorsSurfaceWithTheirOutput() {
            let config = RunConfig(spec: "does-not-exist.qnt", quint: quint)
            #expect(throws: QuintConnectError.self) { try QuintConnect.simulate(config) { RecorderDriver() } }
        }
    }

    /// A spec that tracks its own action in a sum type, so scripted `run` tests can be replayed.
    private struct CounterDriver: Driver {
        struct Snapshot: Equatable, Sendable, Decodable { let total: Int }

        static var config: DriverConfig { DriverConfig(nondetPath: ["last"]) }
        var total = 0

        mutating func step(_ step: Step) throws {
            switch step.actionTaken {
            case "Init": total = 0
            case "Increment": total += try step.pick("by", as: Int.self)
            default: throw QuintConnectError.unhandledAction(step.actionTaken)
            }
        }

        func state() throws -> Snapshot { Snapshot(total: total) }
    }

    private struct Broken: Driver {
        struct Snapshot: Equatable, Sendable, Decodable { let total: Int }
        static var config: DriverConfig { DriverConfig(nondetPath: ["last"]) }
        var total = 0
        mutating func step(_ step: Step) throws {
            if step.actionTaken == "Increment" { total += 1 }
        }
        func state() throws -> Snapshot { Snapshot(total: total) }
    }

    @Suite(.enabled(if: Quint.pinned != nil, "run `make setup` to install the pinned Quint"))
    struct ScriptedScenarioTests {
        private var quint: QuintExecutable { .path(Quint.pinned ?? URL(fileURLWithPath: "/missing")) }

        @Test func aRunDefinitionIsReplayedThroughTheDriver() throws {
            let config = TestConfig(
                spec: Quint.fixture("counter.qnt"), test: "incrementTest", maxSamples: 1, seed: "0x1", quint: quint)
            try QuintConnect.replayTest(config) { CounterDriver() }
        }

        @Test func aWrongImplementationFailsTheScriptedScenario() throws {
            let config = TestConfig(
                spec: Quint.fixture("counter.qnt"), test: "incrementTest", maxSamples: 1, seed: "0x1", quint: quint)
            #expect(throws: QuintConnectError.self) { try QuintConnect.replayTest(config) { Broken() } }
        }
    }

    enum Quint {
        /// `node_modules/.bin/quint` at the package root, when `make setup` has run.
        static let pinned: URL? = {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            let url = root.appendingPathComponent("node_modules/.bin/quint")
            return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
        }()

        static func fixture(_ name: String) -> String {
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/\(name)").path
        }
    }
#endif
