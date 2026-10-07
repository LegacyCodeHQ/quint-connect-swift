import Foundation

/// One state of a trace, read as "this action was taken, and the specification is now in this state".
public struct Step: Sendable {
    /// The name of the Quint action that produced this state. `init` for the first state.
    public let actionTaken: String
    /// The values the action chose with `nondet`, by name. A `None` pick is left out and a `Some(x)` is unwrapped.
    public let nondetPicks: [String: ITFValue]
    /// The specification state after the action, at the driver's configured state path.
    public let state: ITFValue

    public init(actionTaken: String, nondetPicks: [String: ITFValue] = [:], state: ITFValue) {
        self.actionTaken = actionTaken
        self.nondetPicks = nondetPicks
        self.state = state
    }

    /// Reads a pick the action must have made.
    public func pick<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        guard let value = nondetPicks[name] else {
            throw QuintConnectError.missingPick(action: actionTaken, name: name)
        }
        return try value.decode(type)
    }

    /// Reads a pick the action may not have made.
    public func optionalPick<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T? {
        try nondetPicks[name]?.decode(type)
    }
}

extension Step {
    /// Derives a step from one state record.
    ///
    /// With an empty `config.nondetPath` the action and picks come from Quint's `mbt::actionTaken` and
    /// `mbt::nondetPicks` variables (`quint run --mbt`). Otherwise they come from a sum type stored in the
    /// state at that path, where the variant tag is the action and its record payload is the picks.
    init(state record: [String: ITFValue], config: DriverConfig) throws {
        var record = record
        record["#meta"] = nil
        if config.nondetPath.isEmpty {
            guard case .string(let action)? = record.removeValue(forKey: "mbt::actionTaken") else {
                throw QuintConnectError.malformedTrace(
                    "Missing `mbt::actionTaken`. Generate traces with `quint run --mbt`. `quint test` traces carry no "
                        + "action names (Quint 0.33), so a spec replayed from `run` tests must track its action in a "
                        + "sum-type variable and the driver must set DriverConfig.nondetPath to it.")
            }
            guard let picks = record.removeValue(forKey: "mbt::nondetPicks") else {
                throw QuintConnectError.malformedTrace("Missing `mbt::nondetPicks`")
            }
            self.init(
                actionTaken: action, nondetPicks: try Self.picks(from: picks),
                state: try Self.value(at: config.statePath, in: record))
        } else {
            guard case .record(let sum) = try Self.value(at: config.nondetPath, in: record),
                case .string(let action)? = sum["tag"]
            else {
                throw QuintConnectError.malformedTrace("Expected an action sum type at \(config.nondetPath)")
            }
            record["mbt::actionTaken"] = nil
            record["mbt::nondetPicks"] = nil
            self.init(
                actionTaken: action, nondetPicks: try Self.picks(from: sum["value"] ?? .tuple([])),
                state: try Self.value(at: config.statePath, in: record))
        }
    }

    private static func picks(from value: ITFValue) throws -> [String: ITFValue] {
        switch value {
        case .record(let fields):
            return fields.compactMapValues(\.unwrappingOption)
        case .tuple(let items) where items.isEmpty:
            return [:]
        default:
            throw QuintConnectError.malformedTrace("Expected nondet picks to be a record, found \(value)")
        }
    }

    static func value(at path: [String], in record: [String: ITFValue]) throws -> ITFValue {
        var current = ITFValue.record(record)
        for segment in path {
            guard case .record(let fields) = current else {
                throw QuintConnectError.malformedTrace("Cannot read `\(segment)` from non-record \(current)")
            }
            guard let next = fields[segment] else {
                throw QuintConnectError.malformedTrace("No `\(segment)` in \(current) while following \(path)")
            }
            current = next
        }
        return current
    }
}

extension Step: CustomStringConvertible {
    public var description: String {
        var lines = ["Action taken: \(actionTaken.isEmpty ? "<anonymous>" : actionTaken)"]
        if nondetPicks.isEmpty {
            lines.append("Nondet picks: <none>")
        } else {
            lines.append("Nondet picks:")
            lines += nondetPicks.keys.sorted().map { "+ \($0): \(nondetPicks[$0]?.description ?? "")" }
        }
        lines.append("Next state: \(state)")
        return lines.joined(separator: "\n")
    }
}
