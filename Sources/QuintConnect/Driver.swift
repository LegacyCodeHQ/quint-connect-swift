import Foundation

/// Where to find the state and the nondeterministic picks inside a specification's variables.
public struct DriverConfig: Sendable, Equatable {
    /// Path to the state to compare. Empty means the top-level variables.
    public var statePath: [String]
    /// Path to an action sum type that carries the picks. Empty means Quint's builtin
    /// `mbt::actionTaken` and `mbt::nondetPicks` variables.
    public var nondetPath: [String]

    public init(statePath: [String] = [], nondetPath: [String] = []) {
        self.statePath = statePath
        self.nondetPath = nondetPath
    }
}

/// Connects an implementation to a Quint specification.
///
/// Quint Connect replays each trace by calling ``step(_:)`` once per state, then compares ``state()`` with the
/// specification's state. Translate Quint actions into calls on your code in ``step(_:)``:
///
/// ```swift
/// mutating func step(_ step: Step) throws {
///     switch step.actionTaken {
///     case "init": recorder = Recorder()
///     case "pressRecord": recorder.pressRecord()
///     default: throw QuintConnectError.unhandledAction(step.actionTaken)
///     }
/// }
/// ```
public protocol Driver {
    /// The comparable projection of state. Use ``Unchecked`` for a driver that does not check state.
    associatedtype State: Equatable & Sendable

    /// How to find state and picks in the specification.
    static var config: DriverConfig { get }

    /// Applies one specification step to the implementation.
    mutating func step(_ step: Step) throws

    /// The implementation's state, projected into the specification's shape.
    func state() throws -> State

    /// The specification's state, decoded into the same shape.
    static func decode(specState: ITFValue) throws -> State
}

extension Driver {
    public static var config: DriverConfig { DriverConfig() }
}

extension Driver where State: Decodable {
    /// Decodes the specification state with `Decodable`. See ``ITFValue/decode(_:)`` for the mapping.
    public static func decode(specState: ITFValue) throws -> State {
        try specState.decode(State.self)
    }
}

/// The state of a driver that does not check state: every comparison passes.
public struct Unchecked: Equatable, Sendable, Decodable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

extension Driver where State == Unchecked {
    public func state() throws -> Unchecked { Unchecked() }
    public static func decode(specState: ITFValue) throws -> Unchecked { Unchecked() }
}
