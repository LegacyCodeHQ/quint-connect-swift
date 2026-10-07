import Foundation

/// Diagnostics on standard error, controlled by `QUINT_VERBOSE` (`0` quiet, `1` steps, `2` raw states).
enum Log {
    static var verbosity: Int {
        ProcessInfo.processInfo.environment["QUINT_VERBOSE"].flatMap(Int.init) ?? 0
    }

    static func info(_ message: @autoclosure () -> String) {
        write("   " + message())
    }

    static func trace(_ level: Int, _ message: @autoclosure () -> String) {
        guard verbosity >= level else { return }
        write("   " + message().replacingOccurrences(of: "\n", with: "\n   "))
    }

    private static func write(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
