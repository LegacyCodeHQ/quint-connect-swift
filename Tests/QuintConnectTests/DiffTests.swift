import Testing

@testable import QuintConnect

struct DiffTests {
    @Test func identicalValuesHaveNoDiff() {
        #expect(Diff.render(["a", "b"], ["a", "b"]).isEmpty)
    }

    @Test func marksChangedLines() {
        let diff = Diff.lines(from: ["a", "b", "c"], to: ["a", "x", "c"], context: 1)
        #expect(diff == "  a\n- b\n+ x\n  c")
    }

    @Test func collapsesDistantContext() {
        let left = (1...20).map(String.init)
        var right = left
        right[0] = "changed"
        right[19] = "changed too"
        let diff = Diff.lines(from: left, to: right, context: 1)
        #expect(diff.contains("  ..."))
        #expect(!diff.contains("10"))
    }

    @Test func rendersStructFieldsThroughDump() {
        struct State { var phase: String }
        let diff = Diff.render(State(phase: "Idle"), State(phase: "Recording"))
        #expect(diff.contains("- "))
        #expect(diff.contains("Idle"))
        #expect(diff.contains("Recording"))
    }
}
