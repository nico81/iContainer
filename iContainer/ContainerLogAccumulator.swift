import Foundation

/// Pure state machine for the container Logs tab.
///
/// The UI polls `container logs --tail N`, receives a full tail snapshot each
/// time, and this accumulator keeps only the visible text plus the previous
/// snapshot needed to append newly-seen lines.
nonisolated struct ContainerLogAccumulator {
    private(set) var text: String = ""
    private var lastSnapshotLines: [String] = []
    private var lastClearDate: Date = .distantPast

    mutating func ingest(_ output: String) {
        let lines = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .filter { line in
                lineTimestamp(line) >= lastClearDate
            }

        let delta: [String]
        if lastSnapshotLines.isEmpty && text.isEmpty {
            delta = lines
        } else {
            delta = deltaLines(previous: lastSnapshotLines, current: lines)
        }

        append(delta)
        lastSnapshotLines = lines
    }

    mutating func replaceWithUnavailableMessage() {
        text = "No logs available."
    }

    mutating func clear(at date: Date) {
        text = ""
        lastClearDate = date
        lastSnapshotLines.removeAll()
    }

    private mutating func append(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        let joined = lines.joined(separator: "\n")
        if text.isEmpty {
            text = joined
        } else {
            text += "\n" + joined
        }
    }

    private func deltaLines(previous: [String], current: [String]) -> [String] {
        let prefixCount = commonPrefixCount(previous, current)
        if prefixCount < current.count {
            return Array(current.dropFirst(prefixCount))
        }
        return []
    }

    private func commonPrefixCount(_ a: [String], _ b: [String]) -> Int {
        let count = min(a.count, b.count)
        var idx = 0
        while idx < count, a[idx] == b[idx] {
            idx += 1
        }
        return idx
    }

    private func lineTimestamp(_ line: String) -> Date {
        if let parsed = parseRFC3339(line) {
            return parsed
        }
        return lastClearDate
    }

    private func parseRFC3339(_ line: String) -> Date? {
        let pattern = #"^\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s"#
        guard let match = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let token = String(line[match]).trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: token) {
            return date
        }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        return isoNoFrac.date(from: token)
    }
}
