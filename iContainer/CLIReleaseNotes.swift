import Foundation

/// Structured view of an `apple/container` GitHub release body.
///
/// Apple's notes follow a stable shape: an optional `## Highlights` header,
/// a legend (`⌨️ denotes breaking CLI changes.` / `👩‍💻 denotes breaking API
/// changes.`), a two-level bullet list grouped by area (`- Core` →
/// `  - [Title](PR url)`), then `## What's Changed` (`* Title by @user in url`)
/// and `## New Contributors`. Some patch releases omit the `## Highlights`
/// header (1.6.1), so everything before `## What's Changed` is treated as
/// highlights.
nonisolated struct CLIReleaseNotes: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        var id: String { text + (url?.absoluteString ?? "") }
        /// Title with Markdown inline syntax (backticks) preserved.
        let text: String
        let url: URL?
        let isBreakingCLI: Bool
        let isBreakingAPI: Bool
        var isBreaking: Bool { isBreakingCLI || isBreakingAPI }
    }

    struct Group: Equatable, Sendable, Identifiable {
        var id: String { (title ?? "") + "|" + items.map(\.text).joined(separator: "|") }
        /// Area name (`Core`, `Kubernetes`, …); `nil` for ungrouped items.
        let title: String?
        let items: [Item]
    }

    struct Change: Equatable, Sendable, Identifiable {
        var id: String { title + (url?.absoluteString ?? "") }
        let title: String
        let author: String?
        let url: URL?
    }

    let highlights: [Group]
    let changes: [Change]

    var highlightCount: Int { highlights.reduce(0) { $0 + $1.items.count } }
    var breakingItems: [Item] { highlights.flatMap(\.items).filter(\.isBreaking) }
    var isEmpty: Bool { highlights.isEmpty && changes.isEmpty }
}

nonisolated extension CLIParsers {
    static func parseReleaseNotes(_ body: String) -> CLIReleaseNotes {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        // Split into the highlights block and the "What's Changed" block.
        var highlightLines: [String] = []
        var changeLines: [String] = []
        var section = "highlights"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased()
                if heading.hasPrefix("what's changed") || heading.hasPrefix("what’s changed") { section = "changes"; continue }
                if heading.hasPrefix("new contributors") { section = "other"; continue }
                if heading.hasPrefix("highlights") { section = "highlights"; continue }
                if section == "highlights" { continue }
                section = "other"; continue
            }
            if trimmed.hasPrefix("**Full Changelog**") { section = "other"; continue }
            switch section {
            case "highlights": highlightLines.append(line)
            case "changes": changeLines.append(line)
            default: break
            }
        }

        // Highlights: "- Area" groups with indented "- [Title](url)" items.
        var groups: [CLIReleaseNotes.Group] = []
        var currentTitle: String?
        var currentItems: [CLIReleaseNotes.Item] = []
        var hasOpenGroup = false
        func flush() {
            if hasOpenGroup, !currentItems.isEmpty || currentTitle != nil {
                if !currentItems.isEmpty { groups.append(.init(title: currentTitle, items: currentItems)) }
            }
            currentTitle = nil; currentItems = []; hasOpenGroup = false
        }
        for line in highlightLines {
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if content.lowercased().contains("denotes breaking") { continue }
            let item = releaseItem(content)
            if indent == 0 {
                if item.url == nil && !item.isBreaking {
                    // A bare top-level bullet is an area header.
                    flush()
                    currentTitle = item.text
                    hasOpenGroup = true
                } else {
                    // Top-level item with a link: belongs to an untitled group.
                    if hasOpenGroup && currentTitle != nil { flush() }
                    hasOpenGroup = true
                    currentItems.append(item)
                }
            } else {
                hasOpenGroup = true
                currentItems.append(item)
            }
        }
        flush()

        // What's Changed: "* Title by @user in https://…"
        let changes: [CLIReleaseNotes.Change] = changeLines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") else { return nil }
            var rest = String(trimmed.dropFirst(2))
            var url: URL?
            if let range = rest.range(of: " in https://", options: .backwards) {
                url = URL(string: String(rest[rest.index(range.lowerBound, offsetBy: 4)...]).trimmingCharacters(in: .whitespaces))
                rest = String(rest[..<range.lowerBound])
            }
            var author: String?
            if let range = rest.range(of: " by @", options: .backwards) {
                author = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                rest = String(rest[..<range.lowerBound])
            }
            let title = rest.trimmingCharacters(in: .whitespaces)
            return title.isEmpty ? nil : .init(title: title, author: author, url: url)
        }

        return CLIReleaseNotes(highlights: groups, changes: changes)
    }

    /// `⌨️ [Removed X](url)` → text "Removed X", url, breaking CLI.
    private static func releaseItem(_ raw: String) -> CLIReleaseNotes.Item {
        var text = raw
        let breakingCLI = text.contains("⌨️") || text.contains("⌨")
        let breakingAPI = text.contains("👩‍💻")
        for marker in ["⌨️", "⌨", "👩‍💻", "\u{FE0F}"] { text = text.replacingOccurrences(of: marker, with: "") }
        text = text.trimmingCharacters(in: .whitespaces)
        var url: URL?
        // Whole-line link "[Title](url)" (possibly followed by text).
        if text.hasPrefix("["), let close = text.range(of: "]("), let end = text[close.upperBound...].firstIndex(of: ")") {
            let title = String(text[text.index(after: text.startIndex)..<close.lowerBound])
            url = URL(string: String(text[close.upperBound..<end]))
            let tail = String(text[text.index(after: end)...]).trimmingCharacters(in: .whitespaces)
            text = tail.isEmpty ? title : "\(title) \(tail)"
        }
        return .init(text: text, url: url, isBreakingCLI: breakingCLI, isBreakingAPI: breakingAPI)
    }
}
