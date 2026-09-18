import Foundation

// MARK: - Models

/// One entry of `container network list --format json` (CLI ≥ 1.0 shape:
/// `{configuration: {name, mode, plugin, labels, creationDate}, id,
/// status: {ipv4Subnet, ipv4Gateway, ipv6Subnet}}`).
nonisolated struct ContainerNetwork: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mode: String?
    let plugin: String?
    let creationDate: String?
    let labels: [String: String]
    let ipv4Subnet: String?
    let ipv4Gateway: String?
    let ipv6Subnet: String?

    /// The CLI-managed `default` network (label
    /// `com.apple.container.resource.role = builtin`). Can't be deleted.
    var isBuiltin: Bool {
        labels["com.apple.container.resource.role"] == "builtin" || name == "default"
    }
}

/// One entry of `container volume list --format json`
/// (`{configuration: {name, driver, format, labels, options, sizeInBytes,
/// source, creationDate}, id}`).
nonisolated struct ContainerVolume: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let driver: String?
    let format: String?
    let creationDate: String?
    let labels: [String: String]
    /// Provisioned capacity of the backing image, not the space in use.
    let capacityBytes: Int64?
    /// Path of the backing `volume.img` on the host.
    let source: String?
    /// Blocks actually allocated to the sparse backing image — the real
    /// disk usage. Filled by the wrapper from the file system (not part of
    /// the CLI output); `nil` when the file can't be read.
    var allocatedBytes: Int64? = nil

    /// Volumes the CLI created implicitly for an image `VOLUME` directive
    /// (UUID names, label `com.apple.container.resource.anonymous`).
    var isAnonymous: Bool {
        labels["com.apple.container.resource.anonymous"] != nil
    }

    /// Short display name: anonymous UUIDs are cut to their first block.
    var displayName: String {
        guard isAnonymous, name.count > 12, let dash = name.firstIndex(of: "-") else { return name }
        return String(name[..<dash]) + "…"
    }

    /// Provisioned capacity, base-2 (a 512 GiB image reads "512 GB", not
    /// "549.76 GB").
    var displayCapacity: String {
        guard let capacityBytes, capacityBytes > 0 else { return "-" }
        return ByteCountFormatter.string(fromByteCount: capacityBytes, countStyle: .binary)
    }

    var displayAllocated: String? {
        guard let allocatedBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: allocatedBytes, countStyle: .binary)
    }

    /// `"68 MB used of 512 GB"` when the backing file is readable, else the
    /// capacity alone.
    var displayUsage: String {
        if let used = displayAllocated { return "\(used) used of \(displayCapacity)" }
        return "\(displayCapacity) capacity"
    }
}

// MARK: - Parsers

nonisolated extension CLIParsers {
    /// Parses `container network list --format json`. Malformed input → `[]`.
    static func parseNetworkList(_ output: String) -> [ContainerNetwork] {
        guard let array = jsonArray(output) else { return [] }
        return array.compactMap { dict in
            let configuration = dict["configuration"] as? [String: Any] ?? [:]
            let status = dict["status"] as? [String: Any] ?? [:]
            guard let id = stringValue(dict, keys: ["id"]) ?? stringValue(configuration, keys: ["name"]), !id.isEmpty else { return nil }
            return ContainerNetwork(
                id: id,
                name: stringValue(configuration, keys: ["name"]) ?? id,
                mode: stringValue(configuration, keys: ["mode"]),
                plugin: stringValue(configuration, keys: ["plugin"]),
                creationDate: stringValue(configuration, keys: ["creationDate", "created"]),
                labels: stringDictionary(configuration["labels"]),
                ipv4Subnet: stringValue(status, keys: ["ipv4Subnet"]),
                ipv4Gateway: stringValue(status, keys: ["ipv4Gateway"]),
                ipv6Subnet: stringValue(status, keys: ["ipv6Subnet"])
            )
        }
    }

    /// Parses `container volume list --format json`. Malformed input → `[]`.
    static func parseVolumeList(_ output: String) -> [ContainerVolume] {
        guard let array = jsonArray(output) else { return [] }
        return array.compactMap { dict in
            let configuration = dict["configuration"] as? [String: Any] ?? [:]
            guard let id = stringValue(dict, keys: ["id"]) ?? stringValue(configuration, keys: ["name"]), !id.isEmpty else { return nil }
            return ContainerVolume(
                id: id,
                name: stringValue(configuration, keys: ["name"]) ?? id,
                driver: stringValue(configuration, keys: ["driver"]),
                format: stringValue(configuration, keys: ["format"]),
                creationDate: stringValue(configuration, keys: ["creationDate", "created"]),
                labels: stringDictionary(configuration["labels"]),
                capacityBytes: intValue(configuration, keys: ["sizeInBytes", "size"]),
                source: stringValue(configuration, keys: ["source"])
            )
        }
    }

    /// Extracts the network names and named volumes a container is attached
    /// to from one `container list --format json` entry (CLI ≥ 1.0:
    /// `configuration.networks[].network`, `configuration.mounts[].type.volume.name`).
    static func parseContainerAttachments(_ dict: [String: Any]) -> (networks: [String], volumes: [String]) {
        let configuration = dict["configuration"] as? [String: Any] ?? [:]
        let networks = (configuration["networks"] as? [[String: Any]] ?? []).compactMap { stringValue($0, keys: ["network", "name"]) }
        let volumes = (configuration["mounts"] as? [[String: Any]] ?? []).compactMap { mount -> String? in
            guard let type = mount["type"] as? [String: Any], let volume = type["volume"] as? [String: Any] else { return nil }
            return stringValue(volume, keys: ["name"])
        }
        return (networks, volumes)
    }

    private static func jsonArray(_ output: String) -> [[String: Any]]? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        return json as? [[String: Any]]
    }

    private static func stringDictionary(_ value: Any?) -> [String: String] {
        guard let dict = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in dict {
            if let s = raw as? String { result[key] = s } else if let n = raw as? NSNumber { result[key] = n.stringValue }
        }
        return result
    }
}
