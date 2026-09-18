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
    /// Number of files and directories inside the ext4 image (inodes in
    /// use minus the 11 reserved ones), read from the superblock by the
    /// wrapper. `0` means a freshly formatted, never-written filesystem.
    var ext4ItemCount: Int? = nil

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

    /// `"empty"` / `"3 items"` from the ext4 superblock, `nil` if unreadable.
    var displayContents: String? {
        guard let ext4ItemCount else { return nil }
        return ext4ItemCount <= 0 ? "empty" : "\(ext4ItemCount) item\(ext4ItemCount == 1 ? "" : "s")"
    }
}

/// The few ext4 superblock fields we care about. Pure; the wrapper feeds it
/// the 1024 bytes at offset 1024 of a `volume.img`.
nonisolated struct Ext4Superblock: Equatable, Sendable {
    static let magic: UInt16 = 0xEF53
    /// Inodes ext4 reserves for itself (root, journal, …) on every fresh fs.
    static let reservedInodes = 11

    let inodesTotal: UInt32
    let inodesFree: UInt32
    let blocksTotal: UInt32
    let blocksFree: UInt32
    let blockSize: Int
    let lastWriteTime: Date?
    let mountCount: Int

    var inodesInUse: Int { Int(inodesTotal) - Int(inodesFree) }
    /// Files + directories created by users of the volume.
    var itemCount: Int { max(0, inodesInUse - Self.reservedInodes) }
    var isEmpty: Bool { itemCount == 0 }

    /// Parses a superblock; `nil` when the magic doesn't match or the data
    /// is too short.
    init?(superblockData data: Data) {
        guard data.count >= 0x3A else { return nil }
        func u32(_ offset: Int) -> UInt32 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }.littleEndian
        }
        func u16(_ offset: Int) -> UInt16 {
            data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }.littleEndian
        }
        guard u16(0x38) == Self.magic else { return nil }
        inodesTotal = u32(0x00)
        blocksTotal = u32(0x04)
        blocksFree = u32(0x0C)
        inodesFree = u32(0x10)
        blockSize = 1024 << Int(u32(0x18))
        let wtime = u32(0x30)
        lastWriteTime = wtime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(wtime))
        mountCount = Int(u16(0x34))
    }

    /// Reads the superblock of an ext2/3/4 image file at `path`.
    static func read(fromImageAt path: String) -> Ext4Superblock? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: 1024)
            guard let data = try handle.read(upToCount: 1024) else { return nil }
            return Ext4Superblock(superblockData: data)
        } catch {
            return nil
        }
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
