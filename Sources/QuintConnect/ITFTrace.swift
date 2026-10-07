import Foundation

/// One execution of the specification: the sequence of states Quint passed through, as written by `--out-itf`.
public struct ITFTrace: Equatable, Sendable {
    /// The names of the state variables.
    public let vars: [String]
    /// One record per state, keyed by variable name.
    public let states: [ITFValue]

    public init(vars: [String], states: [ITFValue]) {
        self.vars = vars
        self.states = states
    }

    public init(json: Data) throws {
        let document = try ITFValue(json: json)
        guard case .list(let states)? = document["states"] else {
            throw QuintConnectError.malformedTrace("Missing `states`")
        }
        var vars: [String] = []
        if case .list(let names)? = document["vars"] { vars = names.compactMap(\.stringValue) }
        self.init(vars: vars, states: states)
    }

    public init(contentsOf url: URL) throws {
        do {
            try self.init(json: try Data(contentsOf: url))
        } catch let error as QuintConnectError {
            throw QuintConnectError.malformedTrace("\(url.path): \(error)")
        }
    }

    /// Loads every `*.itf.json` file in a directory, in natural file-name order (`run_2` before `run_10`).
    public static func traces(in directory: URL) throws -> [ITFTrace] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".itf.json") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return try files.map(ITFTrace.init(contentsOf:))
    }
}
