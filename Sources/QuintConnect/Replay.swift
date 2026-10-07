import Foundation

/// Replays Quint traces against an implementation and fails on the first divergence.
public enum QuintConnect {
    /// Replays traces through a driver.
    ///
    /// For every state of every trace this derives a ``Step``, hands it to ``Driver/step(_:)``, then compares the
    /// implementation's state with the specification's. Each trace gets a fresh driver, because every trace starts
    /// with the specification's `init`.
    ///
    /// - Throws: ``QuintConnectError/noTraces`` for an empty list, ``QuintConnectError/stateDivergence(trace:step:action:diff:)``
    ///   on the first mismatch, and whatever the driver throws.
    public static func replay<D: Driver>(_ traces: [ITFTrace], makeDriver: () throws -> D) throws {
        guard !traces.isEmpty else { throw QuintConnectError.noTraces }
        let config = D.config
        for (traceIndex, trace) in traces.enumerated() {
            var driver = try makeDriver()
            Log.trace(1, "[Trace \(traceIndex + 1)]")
            for (stepIndex, state) in trace.states.enumerated() {
                guard case .record(let record) = state else {
                    throw QuintConnectError.malformedTrace(
                        "Trace \(traceIndex + 1), state \(stepIndex) is not a record")
                }
                let step = try Step(state: record, config: config)
                Log.trace(1, "[Step \(stepIndex)]\n\(step)")
                guard !step.actionTaken.isEmpty else {
                    throw QuintConnectError.anonymousAction(trace: traceIndex + 1, step: stepIndex)
                }
                try driver.step(step)
                try check(driver, against: step, trace: traceIndex + 1, index: stepIndex)
            }
        }
    }

    /// Replays every `*.itf.json` file in a directory. This is the entry point for platforms that cannot launch
    /// `quint`, such as the iOS simulator: generate the traces ahead of time and load them here.
    public static func replay<D: Driver>(directory: URL, makeDriver: () throws -> D) throws {
        try replay(try ITFTrace.traces(in: directory), makeDriver: makeDriver)
    }

    private static func check<D: Driver>(_ driver: D, against step: Step, trace: Int, index: Int) throws {
        let specification = try D.decode(specState: step.state)
        let implementation = try driver.state()
        guard specification == implementation else {
            throw QuintConnectError.stateDivergence(
                trace: trace, step: index, action: step.actionTaken,
                diff: Diff.render(specification, implementation))
        }
    }
}
