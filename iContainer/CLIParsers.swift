import Foundation

/// Pure parsers for the output of the Apple `container` CLI.
///
/// All functions in this namespace are deterministic and side-effect free,
/// so they can be exhaustively unit tested without spawning a process or
/// touching the filesystem. `ContainerizationWrapper` and `ServiceManager`
/// are thin wrappers around these functions: they run the CLI and forward
/// the raw output here.
///
/// The whole namespace is `nonisolated` so it can be called from any
/// actor — in particular from `nonisolated static` helpers in
/// `ServiceManager` that run on background threads. The project default
/// is `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, so we have to opt out
/// explicitly.
nonisolated enum CLIParsers {

    // MARK: - Image references

    /// Splits an OCI image reference into `(name, tag)`.
    ///
    /// - `"alpine:3.19"` → `("alpine", "3.19")`
    /// - `"docker.io/library/alpine:3.19"` → `("docker.io/library/alpine", "3.19")`
    /// - `"alpine"` → `("alpine", nil)`
    /// - `""` → `("", nil)`
    ///
    /// The colon in a registry port (e.g. `"localhost:5000/img"`) is preserved
    /// because the last `:` is used as the tag separator only when it appears
    /// after the final `/`.
    static func splitReference(_ reference: String) -> (name: String, tag: String?) {
        guard !reference.isEmpty else { return ("", nil) }
        // Only the last colon AFTER the last slash is a tag separator.
        let lastSlash = reference.lastIndex(of: "/")
        let searchStart = lastSlash.map { reference.index(after: $0) } ?? reference.startIndex
        if let colon = reference[searchStart...].lastIndex(of: ":") {
            let name = String(reference[..<colon])
            let tag = String(reference[reference.index(after: colon)...])
            return (name, tag.isEmpty ? nil : tag)
        }
        return (reference, nil)
    }

    // MARK: - Image list

    /// Parses the JSON output of `container image list --format json` into
    /// a list of `ContainerImage`. Returns an empty array on malformed input.
    static func parseImageList(_ output: String) -> [ContainerImage] {
        guard let data = output.data(using: .utf8) else { return [] }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let array = json as? [[String: Any]] else {
            return []
        }
        return array.compactMap { mapImage($0) }
    }

    private static func mapImage(_ dict: [String: Any]) -> ContainerImage? {
        // container CLI ≤ 0.x puts `reference` and `descriptor` at the top
        // level; CLI ≥ 1.0 nests them inside `configuration`, with the
        // reference under `name` and the creation date in `creationDate`.
        let configuration = dict["configuration"] as? [String: Any]
        let reference = stringValue(dict, keys: ["reference", "ref"])
            ?? stringValue(configuration ?? [:], keys: ["name"])
            ?? ""
        let (name, tag) = splitReference(reference)
        let descriptor = dict["descriptor"] as? [String: Any]
            ?? configuration?["descriptor"] as? [String: Any]
        let digest = descriptor?["digest"] as? String
        let sizeBytes = intValue(descriptor ?? [:], keys: ["size"])
        let sizeText = stringValue(dict, keys: ["fullSize", "full_size"])
        let annotations = descriptor?["annotations"] as? [String: Any]
        let createdAt = stringValue(annotations ?? [:], keys: ["org.opencontainers.image.created"])
            ?? stringValue(configuration ?? [:], keys: ["creationDate"])
        let resolvedId = digest ?? stringValue(dict, keys: ["id"]) ?? reference
        guard !resolvedId.isEmpty else { return nil }
        return ContainerImage(
            id: resolvedId,
            name: name.isEmpty ? reference : name,
            tag: tag,
            sizeBytes: sizeBytes,
            sizeText: sizeText,
            createdAt: createdAt
        )
    }

    // MARK: - Registry

    /// Parses the textual output of `container registry ls`, returning the
    /// list of authenticated hostnames. The header row (`Hostname`) is
    /// stripped and blank lines are ignored.
    static func parseRegistryHosts(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let columns = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isWhitespace)
                guard let firstColumn = columns.first else { return nil }
                let host = String(firstColumn)
                return host.lowercased() == "hostname" ? nil : host
            }
            .filter { !$0.isEmpty }
    }

    /// Expands Docker Hub aliases. `docker.io`, `index.docker.io` and
    /// `registry-1.docker.io` all refer to the same registry, so the CLI
    /// has to be tried with each variant for login / logout to succeed.
    static func registryLoginHosts(for host: String) -> [String] {
        let normalized = host.lowercased()
        if normalized == "registry-1.docker.io"
            || normalized == "docker.io"
            || normalized == "index.docker.io" {
            return ["registry-1.docker.io", "docker.io", "index.docker.io"]
        }
        return [host]
    }

    /// True when the message looks like an authentication failure from a
    /// container registry (401, "unauthorized", missing credentials, etc).
    static func isRegistryAuthError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("401 unauthorized")
            || lower.contains("unauthorized")
            || lower.contains("authentication required")
            || lower.contains("no credentials found for host")
            || lower.contains("insufficient_scope")
            || lower.contains("denied")
    }

    /// True when the message indicates a missing/invalid Docker Hub
    /// reference for an official library image — the typical signal that
    /// the user typed `alpine` instead of `docker.io/library/alpine`.
    static func isLikelyDockerHubImageReferenceError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("401 unauthorized")
            && lower.contains("registry-1.docker.io/v2/library/")
            && lower.contains("/manifests/")
    }

    /// True when stdout from a subcommand looks like the global `container`
    /// help banner — happens when the CLI doesn't recognise an alias and
    /// falls back to printing top-level usage.
    static func looksLikeTopLevelHelp(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("overview: a container platform for macos")
            && lower.contains("container subcommands:")
            && lower.contains("image subcommands:")
    }

    // MARK: - Inspect → editable settings

    /// Parses the JSON output of `container inspect <id>` into the subset
    /// of fields the edit-settings sheet can mutate. Returns `nil` if the
    /// payload is malformed.
    static func parseEditableSettings(_ raw: String) -> ContainerEditableSettings? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }

        let root: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            root = first
        } else if let object = json as? [String: Any] {
            root = object
        } else {
            return nil
        }

        let config = root["configuration"] as? [String: Any] ?? [:]
        let imageDict = config["image"] as? [String: Any] ?? [:]
        let initProcess = config["initProcess"] as? [String: Any] ?? [:]
        let networks = root["networks"] as? [[String: Any]] ?? []
        let configNetworks = config["networks"] as? [[String: Any]] ?? []
        let sockets = config["publishedSockets"] as? [[String: Any]] ?? []
        let publishedPorts = config["publishedPorts"] as? [[String: Any]] ?? []
        let mounts = config["mounts"] as? [[String: Any]] ?? []

        let image = stringValue(imageDict, keys: ["reference"]) ?? stringValue(root, keys: ["image"]) ?? ""
        let rawName = stringValue(config, keys: ["hostname"])
            ?? stringValue(networks.first ?? [:], keys: ["hostname"])
            ?? stringValue(configNetworks.first?["options"] as? [String: Any] ?? [:], keys: ["hostname"])
            ?? stringValue(config, keys: ["id"])
            ?? ""
        let name = normalizedContainerName(rawName)

        var ports = sockets.compactMap { socket -> String? in
            guard let host = intValueInt(socket, keys: ["hostPort"]),
                  let container = intValueInt(socket, keys: ["containerPort"]) else {
                return nil
            }
            return "\(host):\(container)"
        }
        ports += publishedPorts.compactMap { port -> String? in
            guard let host = intValueInt(port, keys: ["hostPort"]),
                  let container = intValueInt(port, keys: ["containerPort"]) else {
                return nil
            }
            return "\(host):\(container)"
        }
        ports = Array(Set(ports)).sorted()

        let volumes = mounts.compactMap { mount -> String? in
            guard let source = stringValue(mount, keys: ["source"]),
                  let destination = stringValue(mount, keys: ["destination"]) else {
                return nil
            }
            return "\(source):\(destination)"
        }

        return ContainerEditableSettings(
            image: image,
            name: name,
            ports: ports,
            volumes: volumes,
            environment: stringArrayValue(initProcess, keys: ["environment"])
        )
    }

    /// Normalises a hostname that may be a fully-qualified service name
    /// (e.g. `myapp.test.`) down to its first label (`myapp`). Inputs that
    /// don't end with a dot are returned trimmed but otherwise unchanged.
    static func normalizedContainerName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("."), let first = trimmed.split(separator: ".").first else {
            return trimmed
        }
        return String(first)
    }

    // MARK: - Service status

    /// Parses the textual output of `container system status` into a
    /// `ServiceDetails` value with whatever fields the parser could
    /// recognise. Unknown / missing fields stay `nil`.
    static func parseServiceDetails(_ output: String) -> ServiceDetails {
        var details = ServiceDetails()
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let lowercased = line.lowercased()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let keyValue = keyValuePair(from: trimmed) {
                let key = keyValue.key.lowercased()
                let value = keyValue.value

                if isDataRootKey(key) {
                    details.dataRoot = value
                    continue
                }
                if isInstallRootKey(key) {
                    details.installRoot = value
                    continue
                }
                if isVersionKey(key) {
                    let parsed = parseVersionAndCommit(from: value)
                    if let version = parsed.version {
                        details.version = version
                    }
                    if let commit = parsed.commit {
                        details.commit = commit
                    }
                    continue
                }
                if isCommitKey(key) {
                    details.commit = value
                    continue
                }
            }

            if lowercased.contains("data root") || lowercased.contains("data_root") || lowercased.contains("dataroot") {
                details.dataRoot = valueAfterColon(in: trimmed) ?? details.dataRoot
                continue
            }
            if lowercased.contains("install root") || lowercased.contains("install_root") || lowercased.contains("installroot") {
                details.installRoot = valueAfterColon(in: trimmed) ?? details.installRoot
                continue
            }

            if lowercased.contains("version") {
                if let version = regexFirstMatch(in: trimmed, pattern: #"version:\s*([^\s\)]+)"#) {
                    details.version = version
                } else if let version = valueAfterColon(in: trimmed) {
                    details.version = version
                }
            }

            if lowercased.contains("commit") {
                if let commit = regexFirstMatch(in: trimmed, pattern: #"commit:\s*([A-Fa-f0-9]+)"#) {
                    details.commit = commit
                } else if let commit = regexFirstMatch(in: trimmed, pattern: #"\(commit\s+([A-Fa-f0-9]+)\)"#) {
                    details.commit = commit
                } else if let commit = valueAfterColon(in: trimmed) {
                    details.commit = commit
                }
            }
        }

        return details
    }

    // MARK: - Log truncation

    /// Truncates a long log payload to the last `maxLines` lines, prefixing
    /// it with a notice that explains how many lines were dropped. Inputs
    /// shorter than `maxLines` are returned unchanged.
    static func limitedLogOutput(_ output: String, maxLines: Int = 500) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else {
            return output
        }
        let visibleLines = lines.suffix(maxLines).joined(separator: "\n")
        return "Showing the latest \(maxLines) of \(lines.count) log lines.\n\n\(visibleLines)"
    }

    // MARK: - Machines

    /// Parses `container machine list --format json` into `[Machine]`.
    /// Returns an empty array on malformed input.
    static func parseMachineList(_ output: String) -> [Machine] {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let array = json as? [[String: Any]] else {
            return []
        }
        return array.compactMap { mapMachine($0) }
    }

    private static func mapMachine(_ dict: [String: Any]) -> Machine? {
        guard let id = stringValue(dict, keys: ["id", "name"]), !id.isEmpty else { return nil }
        return Machine(
            id: id,
            status: MachineStatus(cliValue: stringValue(dict, keys: ["status", "state"])),
            cpus: intValueInt(dict, keys: ["cpus"]),
            memoryBytes: intValue(dict, keys: ["memory", "memoryInBytes"]),
            diskBytes: intValue(dict, keys: ["diskSize", "disk"]),
            isDefault: boolValue(dict, keys: ["default", "isDefault"]) ?? false,
            createdDate: stringValue(dict, keys: ["createdDate", "creationDate", "created"])
        )
    }

    /// Parses `container machine inspect <id>` (an array with one element, or a
    /// bare object) into `MachineDetails`. Returns nil on malformed input.
    static func parseMachineDetails(_ output: String) -> MachineDetails? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        let dict: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            dict = first
        } else if let object = json as? [String: Any] {
            dict = object
        } else {
            return nil
        }
        guard let id = stringValue(dict, keys: ["id", "name"]), !id.isEmpty else { return nil }
        let image = dict["image"] as? [String: Any]
        let platform = dict["platform"] as? [String: Any]
        let userSetup = dict["userSetup"] as? [String: Any]
        return MachineDetails(
            id: id,
            status: MachineStatus(cliValue: stringValue(dict, keys: ["status", "state"])),
            cpus: intValueInt(dict, keys: ["cpus"]),
            memoryBytes: intValue(dict, keys: ["memory", "memoryInBytes"]),
            diskBytes: intValue(dict, keys: ["diskSize", "disk"]),
            homeMount: stringValue(dict, keys: ["homeMount", "home-mount"]),
            imageReference: stringValue(image ?? [:], keys: ["reference"]),
            os: stringValue(platform ?? [:], keys: ["os"]),
            architecture: stringValue(platform ?? [:], keys: ["architecture"]),
            createdDate: stringValue(dict, keys: ["createdDate", "creationDate", "created"]),
            username: stringValue(userSetup ?? [:], keys: ["username"]),
            isDefault: boolValue(dict, keys: ["default", "isDefault"]) ?? false
        )
    }

    // MARK: - Helpers

    private static func keyValuePair(from line: String) -> (key: String, value: String)? {
        if line.isEmpty || line.lowercased() == "field value" {
            return nil
        }
        let pattern = #"^(\S+)\s+(.*)$"#
        guard let key = regexFirstMatch(in: line, pattern: pattern, group: 1),
              let value = regexFirstMatch(in: line, pattern: pattern, group: 2) else {
            return nil
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        return trimmedValue.isEmpty ? nil : (key, trimmedValue)
    }

    private static func isDataRootKey(_ key: String) -> Bool {
        key == "dataroot" || key == "data_root" || key == "approot"
    }

    private static func isInstallRootKey(_ key: String) -> Bool {
        key == "installroot" || key == "install_root"
    }

    private static func isVersionKey(_ key: String) -> Bool {
        key == "apiserver.version" || key == "container-apiserver.version" || key == "version"
    }

    private static func isCommitKey(_ key: String) -> Bool {
        key == "apiserver.commit" || key == "container-apiserver.commit" || key == "commit"
    }

    private static func parseVersionAndCommit(from value: String) -> (version: String?, commit: String?) {
        let version = regexFirstMatch(in: value, pattern: #"(\d+(?:\.\d+)+)"#)
        let commit = regexFirstMatch(in: value, pattern: #"commit:\s*([A-Fa-f0-9]+)"#)
        return (version, commit)
    }

    private static func valueAfterColon(in line: String) -> String? {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func regexFirstMatch(in line: String, pattern: String, group: Int = 1) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range) else {
                return nil
            }
            if match.numberOfRanges > group, let matchRange = Range(match.range(at: group), in: line) {
                return String(line[matchRange])
            }
            return nil
        } catch {
            return nil
        }
    }

    private static func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty {
                return value
            }
            if let value = dict[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private static func intValue(_ dict: [String: Any], keys: [String]) -> Int64? {
        for key in keys {
            if let value = dict[key] as? NSNumber {
                return value.int64Value
            }
            if let value = dict[key] as? String, let parsed = Int64(value) {
                return parsed
            }
        }
        return nil
    }

    private static func intValueInt(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int {
                return value
            }
            if let value = dict[key] as? NSNumber {
                return value.intValue
            }
            if let value = dict[key] as? String, let parsed = Int(value) {
                return parsed
            }
        }
        return nil
    }

    private static func stringArrayValue(_ dict: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let value = dict[key] as? [String] {
                return value
            }
        }
        return []
    }

    private static func boolValue(_ dict: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dict[key] as? Bool {
                return value
            }
            if let value = dict[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }
}
