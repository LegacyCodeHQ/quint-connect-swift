import Foundation
import Testing

@testable import QuintConnect

struct StepTests {
    private let mbtState: [String: ITFValue] = [
        "#meta": .record(["index": .int(1)]),
        "mbt::actionTaken": .string("transfer"),
        "mbt::nondetPicks": .record([
            "amount": .record(["tag": .string("Some"), "value": .int(5)]),
            "memo": .record(["tag": .string("None"), "value": .tuple([])]),
        ]),
        "balance": .int(10),
    ]

    @Test func readsActionAndPicksFromMbtVariables() throws {
        let step = try Step(state: mbtState, config: DriverConfig())
        #expect(step.actionTaken == "transfer")
        #expect(step.nondetPicks == ["amount": .int(5)])
        #expect(step.state == .record(["balance": .int(10)]))
    }

    @Test func readsTypedPicks() throws {
        let step = try Step(state: mbtState, config: DriverConfig())
        #expect(try step.pick("amount", as: Int.self) == 5)
        #expect(try step.optionalPick("memo", as: String.self) == nil)
        #expect(throws: QuintConnectError.missingPick(action: "transfer", name: "memo")) {
            try step.pick("memo", as: String.self)
        }
    }

    @Test func followsAStatePath() throws {
        let nested: [String: ITFValue] = [
            "mbt::actionTaken": .string("a"), "mbt::nondetPicks": .record([:]),
            "system": .record(["inner": .record(["n": .int(1)])]),
        ]
        let step = try Step(state: nested, config: DriverConfig(statePath: ["system", "inner"]))
        #expect(step.state == .record(["n": .int(1)]))
    }

    @Test func readsActionFromASumTypeAtANondetPath() throws {
        let record: [String: ITFValue] = [
            "last": .record(["tag": .string("Deposit"), "value": .record(["who": .string("ann")])]),
            "total": .int(3),
        ]
        let step = try Step(state: record, config: DriverConfig(nondetPath: ["last"]))
        #expect(step.actionTaken == "Deposit")
        #expect(step.nondetPicks == ["who": .string("ann")])
    }

    @Test func acceptsASumTypeActionWithoutPicks() throws {
        let record: [String: ITFValue] = ["last": .record(["tag": .string("Init"), "value": .tuple([])])]
        let step = try Step(state: record, config: DriverConfig(nondetPath: ["last"]))
        #expect(step.actionTaken == "Init")
        #expect(step.nondetPicks.isEmpty)
    }

    @Test func explainsAMissingMbtVariable() {
        #expect(throws: QuintConnectError.self) { try Step(state: ["x": .int(1)], config: DriverConfig()) }
    }

    @Test func rejectsABrokenStatePath() {
        let record: [String: ITFValue] = ["mbt::actionTaken": .string("a"), "mbt::nondetPicks": .record([:])]
        #expect(throws: QuintConnectError.self) {
            try Step(state: record, config: DriverConfig(statePath: ["missing"]))
        }
    }
}
