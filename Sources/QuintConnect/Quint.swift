#if os(macOS) || os(Linux)
    import Foundation

    /// How to launch `quint`.
    public enum QuintExecutable: Sendable, Equatable {
        /// `$QUINT_PATH` when set, otherwise `quint` from `PATH`.
        case environment
        /// A specific executable, such as `node_modules/.bin/quint` for a pinned version.
        case path(URL)

        var invocation: (executable: URL, leadingArguments: [String]) {
            switch self {
            case .path(let url):
                return (url, [])
            case .environment:
                if let path = ProcessInfo.processInfo.environment["QUINT_PATH"], !path.isEmpty {
                    return (URL(fileURLWithPath: path), [])
                }
                return (URL(fileURLWithPath: "/usr/bin/env"), ["quint"])
            }
        }
    }

    /// A random seed in the form Quint takes, or `$QUINT_SEED` to reproduce an earlier failure.
    public func randomQuintSeed() -> String {
        if let seed = ProcessInfo.processInfo.environment["QUINT_SEED"], !seed.isEmpty { return seed }
        return "0x" + String(UInt32.random(in: 0...UInt32.max), radix: 16)
    }

    /// Generates traces by simulating a specification with `quint run`.
    public struct RunConfig: Sendable, Equatable {
        public var spec: String
        public var main: String?
        public var initAction: String?
        public var stepAction: String?
        public var maxSamples: Int
        public var maxSteps: Int?
        public var seed: String
        public var quint: QuintExecutable

        public init(
            spec: String, main: String? = nil, initAction: String? = nil, stepAction: String? = nil,
            maxSamples: Int = 100, maxSteps: Int? = nil, seed: String = randomQuintSeed(),
            quint: QuintExecutable = .environment
        ) {
            self.spec = spec
            self.main = main
            self.initAction = initAction
            self.stepAction = stepAction
            self.maxSamples = maxSamples
            self.maxSteps = maxSteps
            self.seed = seed
            self.quint = quint
        }

        /// The arguments after the executable. `--mbt` makes Quint record which action ran at each step.
        func arguments(outputDirectory: URL) -> [String] {
            var arguments = [
                "run", spec, "--seed", seed, "--max-samples", String(maxSamples), "--n-traces", String(maxSamples),
                "--out-itf", outputDirectory.appendingPathComponent("run_{seq}.itf.json").path, "--mbt",
                "--verbosity", "0",
            ]
            if let main { arguments += ["--main", main] }
            if let initAction { arguments += ["--init", initAction] }
            if let stepAction { arguments += ["--step", stepAction] }
            if let maxSteps { arguments += ["--max-steps", String(maxSteps)] }
            return arguments
        }
    }

    /// Generates traces from one `run` definition with `quint test`.
    public struct TestConfig: Sendable, Equatable {
        public var spec: String
        public var main: String?
        public var test: String
        public var maxSamples: Int
        public var seed: String
        public var quint: QuintExecutable

        public init(
            spec: String, test: String, main: String? = nil, maxSamples: Int = 100,
            seed: String = randomQuintSeed(), quint: QuintExecutable = .environment
        ) {
            self.spec = spec
            self.test = test
            self.main = main
            self.maxSamples = maxSamples
            self.seed = seed
            self.quint = quint
        }

        func arguments(outputDirectory: URL) -> [String] {
            var arguments = [
                "test", spec, "--seed", seed, "--match", "^\(test)$", "--max-samples", String(maxSamples),
                "--out-itf", outputDirectory.appendingPathComponent("test_{seq}.itf.json").path,
                "--verbosity", "0",
            ]
            if let main { arguments += ["--main", main] }
            return arguments
        }
    }

    extension QuintConnect {
        /// Simulates the specification with `quint run`, then replays the traces through a driver.
        public static func simulate<D: Driver>(_ config: RunConfig, makeDriver: () throws -> D) throws {
            Log.info("== Simulating \(config.spec) with seed \(config.seed)")
            try replayGenerated(
                quint: config.quint, seed: config.seed, makeDriver: makeDriver,
                arguments: config.arguments(outputDirectory:))
        }

        /// Replays the traces of one Quint `run` definition through a driver.
        public static func replayTest<D: Driver>(_ config: TestConfig, makeDriver: () throws -> D) throws {
            Log.info("== Replaying \(config.test) from \(config.spec) with seed \(config.seed)")
            try replayGenerated(
                quint: config.quint, seed: config.seed, makeDriver: makeDriver,
                arguments: config.arguments(outputDirectory:))
        }

        private static func replayGenerated<D: Driver>(
            quint: QuintExecutable, seed: String, makeDriver: () throws -> D,
            arguments: (URL) -> [String]
        ) throws {
            let workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("quint-connect-\(UUID().uuidString)")
            let traceDirectory = workDirectory.appendingPathComponent("traces")
            try FileManager.default.createDirectory(at: traceDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            try execute(quint, arguments: arguments(traceDirectory), workDirectory: workDirectory)
            do {
                try replay(directory: traceDirectory, makeDriver: makeDriver)
                Log.info("[OK]")
            } catch {
                Log.info("[FAIL] reproduce with QUINT_SEED=\(seed)")
                throw error
            }
        }

        /// Runs `quint` and throws if it cannot start or exits non-zero.
        static func execute(_ quint: QuintExecutable, arguments: [String], workDirectory: URL) throws {
            let invocation = quint.invocation
            let stderrURL = workDirectory.appendingPathComponent("stderr.txt")
            FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
            let stderr = try FileHandle(forWritingTo: stderrURL)
            defer { try? stderr.close() }

            let process = Process()
            process.executableURL = invocation.executable
            process.arguments = invocation.leadingArguments + arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                throw QuintConnectError.quintNotFound(error.localizedDescription)
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
                if process.terminationStatus == 127, message.contains("quint") {
                    throw QuintConnectError.quintNotFound(message)
                }
                throw QuintConnectError.quintFailed(status: process.terminationStatus, stderr: message)
            }
        }
    }
#endif
