import Foundation

/// A single service parsed out of a compose file's `services:` map.
///
/// Only the directives the `container` CLI can map to `container create`
/// flags are captured as typed fields; everything else is surfaced via
/// `ParsedComposeFile.ignoredDirectives` instead of being silently dropped.
nonisolated struct ComposeService: Equatable {
    let name: String
    var image: String? = nil
    var containerName: String? = nil
    var ports: [String] = []
    var environment: [String] = []
    var volumes: [String] = []
    var command: [String] = []
    var dependsOn: [String] = []

    /// The name the container should be created with: the explicit
    /// `container_name` if the service set one, otherwise the
    /// `<project>-<service>` convention.
    func resolvedContainerName(project: String) -> String {
        containerName ?? "\(project)-\(name)"
    }
}

/// The result of parsing a compose file: the services `container` can
/// actually run, plus a human-readable list of directives it can't map
/// (surfaced to the user as warnings — parsing never fails just because a
/// file uses a feature outside this MVP's scope).
nonisolated struct ParsedComposeFile: Equatable {
    var services: [ComposeService]
    var ignoredDirectives: [String]
}

/// Pure parser for the small subset of the compose-file YAML format this
/// MVP supports: 2-space (or any consistent width) indentation, a
/// `services:` map, and per-service `image`, `container_name`, `ports`,
/// `environment`, `volumes`, `command`, `depends_on`.
///
/// This is deliberately not a general YAML parser — just enough structure
/// (indentation-delimited blocks, `key: value` lines, `- item` lists, inline
/// `[a, b]` arrays) to read real-world compose files without pulling in a
/// dependency. If compose support grows beyond the MVP, replacing this with
/// a proper YAML library (e.g. Yams) is the natural next step; every
/// function here is pure so the swap only touches this file.
///
/// Like `CLIParsers`, this whole namespace is `nonisolated`, deterministic,
/// and side-effect free so it can be exhaustively unit tested.
nonisolated enum ComposeParser {

    // MARK: - Public API

    /// Parses `contents` into a `ParsedComposeFile`. Returns `nil` when the
    /// input doesn't look like a compose file at all (empty input, or no
    /// top-level `services:` mapping) — anything past that point degrades
    /// gracefully: unknown directives are recorded in `ignoredDirectives`
    /// rather than causing a failure.
    static func parse(_ contents: String) -> ParsedComposeFile? {
        let lines = rawLines(contents)
        guard !lines.isEmpty else { return nil }

        var ignoredDirectives: [String] = []
        let topLevel = directChildren(lines: lines, after: -1, parentIndent: -1)

        var servicesIndex: Int?
        for index in topLevel {
            let (key, value) = splitKeyValue(lines[index].text)
            if key == "services" {
                // "services:" must introduce a mapping, not a scalar value.
                guard value == nil else { return nil }
                servicesIndex = index
            } else if key == "version" || key == "name" || key.hasPrefix("x-") {
                continue
            } else if topLevelUnsupportedKeys.contains(key) {
                ignoredDirectives.append(
                    "top-level '\(key)' is not supported by the container CLI and was ignored " +
                    "(services share a single per-project network; only per-service bind mounts under 'volumes:' are supported)."
                )
            }
        }

        guard let servicesIndex else { return nil }

        let serviceEntries = directChildren(lines: lines, after: servicesIndex, parentIndent: lines[servicesIndex].indent)
        var services: [ComposeService] = []

        for serviceIndex in serviceEntries {
            let (name, inlineValue) = splitKeyValue(lines[serviceIndex].text)
            // A scalar where a service body was expected — skip this one
            // entry rather than fail the whole file.
            guard inlineValue == nil, !name.isEmpty else { continue }

            var service = ComposeService(name: name)
            let directiveIndent = lines[serviceIndex].indent
            let directives = directChildren(lines: lines, after: serviceIndex, parentIndent: directiveIndent)

            for directiveIndex in directives {
                let (key, value) = splitKeyValue(lines[directiveIndex].text)
                switch key {
                case "image":
                    service.image = value.map(unquoted)
                case "container_name":
                    service.containerName = value.map(unquoted)
                case "ports":
                    service.ports = gatherChildren(.list, inlineValue: value, afterDirectiveAt: directiveIndex, lines: lines)
                case "volumes":
                    service.volumes = gatherChildren(.list, inlineValue: value, afterDirectiveAt: directiveIndex, lines: lines)
                case "depends_on":
                    service.dependsOn = gatherChildren(.mapKeysOnly, inlineValue: value, afterDirectiveAt: directiveIndex, lines: lines)
                case "environment":
                    service.environment = gatherChildren(.mapAsKeyValue, inlineValue: value, afterDirectiveAt: directiveIndex, lines: lines)
                case "command":
                    service.command = parseCommand(inlineValue: value, afterDirectiveAt: directiveIndex, lines: lines)
                default:
                    ignoredDirectives.append("\(name): '\(key)' is not supported by the container CLI and was ignored.")
                }
            }

            if service.image?.isEmpty ?? true {
                ignoredDirectives.append(
                    "\(name): no 'image' specified — only pre-built images are supported ('build:' is ignored), so this service will be skipped."
                )
            }

            services.append(service)
        }

        return ParsedComposeFile(services: services, ignoredDirectives: ignoredDirectives)
    }

    /// Sanitizes an arbitrary directory name into a token that's safe to use
    /// as both a container-name prefix and a network name: lowercase
    /// alphanumerics, `-`, and `_` only, no leading/trailing/duplicate
    /// dashes, never empty.
    static func sanitizedProjectName(_ raw: String) -> String {
        var result = ""
        for scalar in raw.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("-")
            }
        }
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return result.isEmpty ? "compose-project" : result
    }

    /// Name of the shared network created for a project's containers.
    static func networkName(forProject project: String) -> String {
        "\(project)-net"
    }

    /// Orders `services` so every service appears after everything it
    /// `depends_on` (a stable topological sort). Dependencies that don't
    /// match a known service name are ignored. A dependency cycle can't be
    /// fully satisfied; it's broken deterministically (the service that
    /// completes the cycle is emitted without waiting further) instead of
    /// recursing forever, so every input service still appears exactly once
    /// in the output.
    static func topologicalOrder(_ services: [ComposeService]) -> [ComposeService] {
        let byName = Dictionary(services.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var visited: Set<String> = []
        var visiting: Set<String> = []
        var result: [ComposeService] = []

        func visit(_ service: ComposeService) {
            guard !visited.contains(service.name) else { return }
            guard !visiting.contains(service.name) else { return }
            visiting.insert(service.name)
            for dependencyName in service.dependsOn {
                if let dependency = byName[dependencyName] {
                    visit(dependency)
                }
            }
            visiting.remove(service.name)
            visited.insert(service.name)
            result.append(service)
        }

        for service in services {
            visit(service)
        }
        return result
    }

    // MARK: - Line model

    private struct Line {
        let indent: Int
        let text: String
    }

    /// Top-level compose keys this MVP recognises but can't map to anything
    /// the `container` CLI supports (custom network drivers, named volumes,
    /// Swarm configs/secrets).
    private static let topLevelUnsupportedKeys: Set<String> = ["networks", "volumes", "configs", "secrets"]

    /// Splits `contents` into non-blank, comment-stripped lines with their
    /// leading-whitespace indentation width.
    private static func rawLines(_ contents: String) -> [Line] {
        contents
            .components(separatedBy: .newlines)
            .compactMap { rawLine -> Line? in
                let withoutComment = stripComment(rawLine)
                let indent = withoutComment.prefix(while: { $0 == " " }).count
                let trimmed = withoutComment.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed != "---", trimmed != "..." else { return nil }
                return Line(indent: indent, text: trimmed)
            }
    }

    /// Strips a trailing `# comment`, honouring quotes so a `#` inside a
    /// quoted string (e.g. a password) isn't mistaken for one. Matches the
    /// common YAML convention that only a `#` preceded by whitespace (or at
    /// the start of the line) begins a comment.
    private static func stripComment(_ line: String) -> String {
        var inSingle = false
        var inDouble = false
        var result = ""
        var previousChar: Character?
        for char in line {
            if char == "'" && !inDouble { inSingle.toggle() }
            else if char == "\"" && !inSingle { inDouble.toggle() }
            if char == "#" && !inSingle && !inDouble,
               previousChar == nil || previousChar == " " || previousChar == "\t" {
                break
            }
            result.append(char)
            previousChar = char
        }
        return result
    }

    // MARK: - Indentation tree helpers

    /// Indices of every line that is a descendant of the line at `index`
    /// (or of the document root when `index == -1`), i.e. every subsequent
    /// line whose indent is greater than `parentIndent`, up to the first
    /// line that isn't.
    private static func childIndices(lines: [Line], after index: Int, parentIndent: Int) -> [Int] {
        var result: [Int] = []
        var i = index + 1
        while i < lines.count, lines[i].indent > parentIndent {
            result.append(i)
            i += 1
        }
        return result
    }

    /// Like `childIndices`, but only the immediate children — lines at the
    /// shallowest indentation among the descendants — not grandchildren.
    private static func directChildren(lines: [Line], after index: Int, parentIndent: Int) -> [Int] {
        let all = childIndices(lines: lines, after: index, parentIndent: parentIndent)
        guard let minIndent = all.map({ lines[$0].indent }).min() else { return [] }
        return all.filter { lines[$0].indent == minIndent }
    }

    /// Splits a `key: value` (or bare `key:`) line. The colon must be
    /// immediately followed by whitespace or end-of-line to count as the
    /// key/value separator — matching YAML's rule and so a scalar value
    /// like `8080:80` isn't mistaken for a nested mapping.
    private static func splitKeyValue(_ text: String) -> (key: String, value: String?) {
        guard let colon = findTopLevelColon(text) else {
            return (text, nil)
        }
        let key = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
        let value = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (key, value.isEmpty ? nil : value)
    }

    private static func findTopLevelColon(_ text: String) -> String.Index? {
        var inSingle = false
        var inDouble = false
        var idx = text.startIndex
        while idx < text.endIndex {
            let char = text[idx]
            if char == "'" && !inDouble { inSingle.toggle() }
            else if char == "\"" && !inSingle { inDouble.toggle() }
            if char == ":" && !inSingle && !inDouble {
                let next = text.index(after: idx)
                if next == text.endIndex || text[next] == " " {
                    return idx
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    /// Strips a single layer of matching surrounding quotes, if present.
    private static func unquoted(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return trimmed }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    // MARK: - List / map directive values

    private enum ChildForm {
        /// `- item` lines become plain strings.
        case list
        /// `- KEY=val` lines pass through; `KEY: val` map lines become `"KEY=val"`.
        case mapAsKeyValue
        /// `- name` lines pass through; `name: ...` map lines contribute just `name`.
        case mapKeysOnly
    }

    /// Reads a list-valued directive (`ports`, `volumes`, `depends_on`,
    /// `environment`) in whichever form it was written: an inline `[...]`
    /// array on the same line, a `- item` list on following lines, or (for
    /// `environment`/`depends_on`) a nested map.
    private static func gatherChildren(
        _ form: ChildForm,
        inlineValue: String?,
        afterDirectiveAt index: Int,
        lines: [Line]
    ) -> [String] {
        if let inlineValue, let items = parseInlineArray(inlineValue) {
            return items
        }
        let children = directChildren(lines: lines, after: index, parentIndent: lines[index].indent)
        return children.map { childIndex in
            let text = lines[childIndex].text
            if text.hasPrefix("-") {
                return unquoted(String(text.dropFirst()).trimmingCharacters(in: .whitespaces))
            }
            let (key, value) = splitKeyValue(text)
            switch form {
            case .mapAsKeyValue:
                return "\(key)=\(unquoted(value ?? ""))"
            case .mapKeysOnly, .list:
                return key
            }
        }
    }

    /// `command:` is unique among the mapped directives in that its scalar
    /// form (`command: npm start`) needs shell-style splitting rather than
    /// being kept as one string, since it becomes trailing `container run`
    /// arguments.
    private static func parseCommand(inlineValue: String?, afterDirectiveAt index: Int, lines: [Line]) -> [String] {
        guard let inlineValue else {
            return gatherChildren(.list, inlineValue: nil, afterDirectiveAt: index, lines: lines)
        }
        if let inline = parseInlineArray(inlineValue) {
            return inline
        }
        return shellSplit(unquoted(inlineValue))
    }

    /// Parses a flow-style YAML array (`[a, "b c", 'd']`) into its unquoted
    /// elements. Returns `nil` when `raw` isn't bracketed, so callers can
    /// fall back to their block-form handling.
    private static func parseInlineArray(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") else { return nil }
        var inner = trimmed
        inner.removeFirst()
        if inner.hasSuffix("]") { inner.removeLast() }
        let content = inner.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return [] }
        return splitTopLevelCommas(content).map(unquoted)
    }

    private static func splitTopLevelCommas(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for char in text {
            if char == "'" && !inDouble { inSingle.toggle() }
            else if char == "\"" && !inSingle { inDouble.toggle() }
            if char == "," && !inSingle && !inDouble {
                items.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { items.append(last) }
        return items
    }

    /// Minimal whitespace tokenizer for a scalar `command:` string, honouring
    /// quoted substrings (`command: sh -c "echo hi"` → `["sh", "-c", "echo hi"]`).
    private static func shellSplit(_ text: String) -> [String] {
        var items: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        for char in text {
            if char == "'" && !inDouble { inSingle.toggle(); continue }
            if char == "\"" && !inSingle { inDouble.toggle(); continue }
            if char == " " && !inSingle && !inDouble {
                if !current.isEmpty { items.append(current); current = "" }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { items.append(current) }
        return items
    }
}
