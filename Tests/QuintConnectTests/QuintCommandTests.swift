#if os(macOS) || os(Linux)
    import Foundation
    import Testing

    @testable import QuintConnect

    struct QuintCommandTests {
        private let directory = URL(fileURLWithPath: "/tmp/traces")

        @Test func runUsesSimulationWithMbtMetadata() {
            let config = RunConfig(spec: "foo.qnt", seed: "42")
            #expect(
                config.arguments(outputDirectory: directory) == [
                    "run", "foo.qnt", "--seed", "42", "--max-samples", "100", "--n-traces", "100",
                    "--out-itf", "/tmp/traces/run_{seq}.itf.json", "--mbt", "--verbosity", "0",
                ])
        }

        @Test func runPassesOptionalArguments() {
            let config = RunConfig(
                spec: "foo.qnt", main: "sim", initAction: "start", stepAction: "next", maxSamples: 7, maxSteps: 12,
                seed: "1")
            let arguments = config.arguments(outputDirectory: directory)
            #expect(arguments.suffix(8) == ["--main", "sim", "--init", "start", "--step", "next", "--max-steps", "12"])
            #expect(arguments.contains("7"))
        }

        @Test func testSelectsExactlyOneDefinition() {
            let config = TestConfig(spec: "foo.qnt", test: "happyTest", seed: "42")
            #expect(
                config.arguments(outputDirectory: directory) == [
                    "test", "foo.qnt", "--seed", "42", "--match", "^happyTest$", "--max-samples", "100",
                    "--out-itf", "/tmp/traces/test_{seq}.itf.json", "--verbosity", "0",
                ])
        }

        @Test func environmentExecutableHonoursQuintPath() {
            #expect(QuintExecutable.path(URL(fileURLWithPath: "/x/quint")).invocation.leadingArguments.isEmpty)
            #expect(QuintExecutable.path(URL(fileURLWithPath: "/x/quint")).invocation.executable.path == "/x/quint")
        }

        @Test func reportsAMissingExecutable() {
            let config = RunConfig(spec: "x.qnt", quint: .path(URL(fileURLWithPath: "/nonexistent/quint")))
            #expect(throws: QuintConnectError.self) {
                try QuintConnect.simulate(config) { Unchecker() }
            }
        }
    }

    private struct Unchecker: Driver {
        typealias State = Unchecked
        mutating func step(_ step: Step) throws {}
    }
#endif
