import Foundation
import Testing

@testable import QuintConnect

/// A counter specification: `init` sets 0, `increment` adds `by`.
private struct Counter: Driver {
    struct Snapshot: Equatable, Sendable, Decodable { let value: Int }

    var value = 0
    var bug = false
    var seen: [String] = []

    mutating func step(_ step: Step) throws {
        seen.append(step.actionTaken)
        switch step.actionTaken {
        case "init": value = 0
        case "increment": value += try step.pick("by", as: Int.self) + (bug ? 1 : 0)
        default: throw QuintConnectError.unhandledAction(step.actionTaken)
        }
    }

    func state() throws -> Snapshot { Snapshot(value: value) }
}

private func state(_ action: String, value: Int, picks: [String: ITFValue] = [:]) -> ITFValue {
    .record([
        "mbt::actionTaken": .string(action), "mbt::nondetPicks": .record(picks), "value": .int(value),
    ])
}

private func pick(_ value: Int) -> [String: ITFValue] {
    ["by": .record(["tag": .string("Some"), "value": .int(value)])]
}

private let goodTrace = ITFTrace(
    vars: ["value"],
    states: [
        state("init", value: 0), state("increment", value: 2, picks: pick(2)),
        state("increment", value: 5, picks: pick(3)),
    ])

private struct Recorderless: Driver {
    typealias State = Unchecked
    var actions: [String] = []
    mutating func step(_ step: Step) throws { actions.append(step.actionTaken) }
}

struct ReplayTests {
    @Test func passesWhenTheImplementationMatchesTheSpecification() throws {
        try QuintConnect.replay([goodTrace, goodTrace]) { Counter() }
    }

    @Test func buildsAFreshDriverForEveryTrace() throws {
        var built = 0
        try QuintConnect.replay([goodTrace, goodTrace]) {
            built += 1
            return Counter()
        }
        #expect(built == 2)
    }

    @Test func reportsTheFirstDivergenceWithADiff() {
        do {
            try QuintConnect.replay([goodTrace]) { Counter(bug: true) }
            Issue.record("Expected a divergence")
        } catch let QuintConnectError.stateDivergence(trace, step, action, diff) {
            #expect(trace == 1)
            #expect(step == 1)
            #expect(action == "increment")
            #expect(diff.contains("- "))
            #expect(diff.contains("+ "))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func failsOnAnEmptyTraceList() {
        #expect(throws: QuintConnectError.noTraces) { try QuintConnect.replay([]) { Counter() } }
    }

    @Test func failsOnAnAnonymousAction() {
        let trace = ITFTrace(vars: [], states: [state("", value: 0)])
        #expect(throws: QuintConnectError.anonymousAction(trace: 1, step: 0)) {
            try QuintConnect.replay([trace]) { Counter() }
        }
    }

    @Test func propagatesDriverErrors() {
        let trace = ITFTrace(vars: [], states: [state("explode", value: 0)])
        #expect(throws: QuintConnectError.unhandledAction("explode")) {
            try QuintConnect.replay([trace]) { Counter() }
        }
    }

    @Test func rejectsAStateThatIsNotARecord() {
        let trace = ITFTrace(vars: [], states: [.int(1)])
        #expect(throws: QuintConnectError.self) { try QuintConnect.replay([trace]) { Counter() } }
    }

    @Test func replaysTraceFilesFromADirectoryInNaturalOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
            {"vars": ["value"], "states": [
              {"mbt::actionTaken": "init", "mbt::nondetPicks": {}, "value": 0}]}
            """
        for name in ["run_10.itf.json", "run_2.itf.json", "notes.txt"] {
            try Data(json.utf8).write(to: directory.appendingPathComponent(name))
        }
        let traces = try ITFTrace.traces(in: directory)
        #expect(traces.count == 2)
        try QuintConnect.replay(directory: directory) { Counter() }
    }

    @Test func statelessDriversSkipStateChecks() throws {
        try QuintConnect.replay([goodTrace]) { Recorderless() }
    }
}
