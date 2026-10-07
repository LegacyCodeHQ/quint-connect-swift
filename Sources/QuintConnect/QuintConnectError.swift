import Foundation

/// A failure while generating, reading, or replaying Quint traces.
public enum QuintConnectError: Error, Equatable, CustomStringConvertible {
    /// The `quint` executable could not be started.
    case quintNotFound(String)
    /// `quint` ran and exited with a non-zero status.
    case quintFailed(status: Int32, stderr: String)
    /// Trace generation succeeded but wrote no traces.
    case noTraces
    /// A trace file is not valid ITF, or lacks something Quint Connect needs.
    case malformedTrace(String)
    /// A step carries no action name, so Quint could not attribute it to a named action.
    case anonymousAction(trace: Int, step: Int)
    /// The driver was handed an action it does not know.
    case unhandledAction(String)
    /// A required nondeterministic pick is missing from the step.
    case missingPick(action: String, name: String)
    /// A value could not be decoded into the requested type.
    case decoding(String)
    /// The implementation's state differs from the specification's state after a step.
    case stateDivergence(trace: Int, step: Int, action: String, diff: String)

    public var description: String {
        switch self {
        case .quintNotFound(let detail):
            return
                "Could not run quint: \(detail). Install it (npm install -g @informalsystems/quint) or set QUINT_PATH."
        case .quintFailed(let status, let stderr):
            return "quint exited with status \(status):\n\(stderr)"
        case .noTraces:
            return "Trace generation produced zero traces. Check the specification and the test configuration."
        case .malformedTrace(let detail):
            return "Malformed ITF trace: \(detail)"
        case .anonymousAction(let trace, let step):
            return "Trace \(trace), step \(step) has an anonymous action. Give every action in `step` a name."
        case .unhandledAction(let name):
            return "The driver does not handle the action `\(name)`."
        case .missingPick(let action, let name):
            return "Action `\(action)` has no nondeterministic pick named `\(name)`."
        case .decoding(let detail):
            return "Could not decode a Quint value: \(detail)"
        case .stateDivergence(let trace, let step, let action, let diff):
            return """
                Specification and implementation diverge (trace \(trace), step \(step), after `\(action)`).
                - specification
                + implementation
                \(diff)
                """
        }
    }
}
