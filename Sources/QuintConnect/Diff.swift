import Foundation

enum Diff {
    /// A line diff of two values, rendered with `dump`. Lines only in `left` start with `-`, lines only in
    /// `right` with `+`, and shared lines near a change are kept as context.
    static func render(_ left: Any, _ right: Any, context: Int = 3) -> String {
        lines(from: lines(of: left), to: lines(of: right), context: context)
    }

    static func lines(from left: [String], to right: [String], context: Int = 3) -> String {
        let script = edits(left, right)
        let changed = script.indices.filter { script[$0].mark != " " }
        guard !changed.isEmpty else { return "" }
        var keep = Set<Int>()
        for index in changed {
            keep.formUnion(max(0, index - context)...min(script.count - 1, index + context))
        }
        var output: [String] = []
        var previous = -1
        for index in keep.sorted() {
            if previous >= 0 && index != previous + 1 { output.append("  ...") }
            output.append("\(script[index].mark) \(script[index].text)")
            previous = index
        }
        return output.joined(separator: "\n")
    }

    private static func lines(of value: Any) -> [String] {
        var text = ""
        dump(value, to: &text)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private struct Edit {
        let mark: Character
        let text: String
    }

    /// The edit script from `left` to `right`, from a longest-common-subsequence table.
    private static func edits(_ left: [String], _ right: [String]) -> [Edit] {
        var table = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)
        for i in stride(from: left.count - 1, through: 0, by: -1) {
            for j in stride(from: right.count - 1, through: 0, by: -1) {
                table[i][j] = left[i] == right[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var script: [Edit] = []
        var i = 0
        var j = 0
        while i < left.count && j < right.count {
            if left[i] == right[j] {
                script.append(Edit(mark: " ", text: left[i]))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                script.append(Edit(mark: "-", text: left[i]))
                i += 1
            } else {
                script.append(Edit(mark: "+", text: right[j]))
                j += 1
            }
        }
        script += left[i...].map { Edit(mark: "-", text: $0) }
        script += right[j...].map { Edit(mark: "+", text: $0) }
        return script
    }
}
