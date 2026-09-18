import Foundation

/// Best-effort decoded view of `container inspect <id>` for fields that
/// the `Decodable`-based `ContainerDetails` doesn't expose.
///
/// The shape of the inspect blob varies between CLI versions, so this
/// parser walks the JSON as untyped dictionaries and probes multiple
/// possible key names per field. Anything it can't find is left `nil` /
/// empty; the Info tab degrades gracefully.
struct ContainerInspectFallback: Hashable {
    struct Mount: Hashable {
        let source: String
        let destination: String
        /// `volume` / `virtiofs` (bind) / `tmpfs` — the key of the `type` object.
        var kind: String? = nil
        /// Named volume backing this mount, when `kind == "volume"`.
        var volumeName: String? = nil
    }
    struct Resources: Hashable {
        let cpus: Int?
        let memoryBytes: Int64?
    }
    struct DNS: Hashable {
        let domain: String?
        let nameservers: [String]
        let options: [String]
        let searchDomains: [String]
    }

    let id: String?
    let status: String?
    let image: String?
    let ipv4Address: String?
    let ipv4Gateway: String?
    let ipv6Address: String?
    let macAddress: String?
    let hostname: String?
    let ports: [String]
    let mounts: [Mount]
    let command: String?
    let environment: [String]
    let created: String?
    let workingDir: String?
    let platform: String?
    let runtimeHandler: String?
    let rosetta: Bool?
    let ssh: Bool?
    let readOnly: Bool?
    let resources: Resources?
    let dns: DNS?
    // CLI ≥ 1.x extras
    var startedDate: String? = nil
    var labels: [String: String] = [:]
    /// `uid:gid` or the raw user string the container was created with.
    var user: String? = nil
    var stopSignal: String? = nil
    var capabilitiesAdded: [String] = []
    var capabilitiesDropped: [String] = []
    var sysctls: [String: String] = [:]
    var useInit: Bool? = nil
    var virtualization: Bool? = nil
    var imageDigest: String? = nil
    /// Name of the (first) network the container is attached to.
    var networkName: String? = nil
    var mtu: Int? = nil
}

func parseContainerInspect(_ raw: String) -> ContainerInspectFallback? {
    guard let data = raw.data(using: .utf8) else { return nil }
    do {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let dict: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            dict = first
        } else if let object = json as? [String: Any] {
            dict = object
        } else {
            return nil
        }

        let config = dict["configuration"] as? [String: Any]
        let initProcess = config?["initProcess"] as? [String: Any]
        let imageDict = config?["image"] as? [String: Any]
        // container CLI ≥ 1.0 nests runtime networks inside the status
        // object; ≤ 0.x kept them at the top level.
        let statusDict = dict["status"] as? [String: Any]
        let networks = dict["networks"] as? [[String: Any]]
            ?? statusDict?["networks"] as? [[String: Any]]
            ?? []
        let sockets = config?["publishedSockets"] as? [[String: Any]] ?? []
        let publishedPorts = config?["publishedPorts"] as? [[String: Any]] ?? []
        let mountsArray = config?["mounts"] as? [[String: Any]] ?? []
        let configNetworks = config?["networks"] as? [[String: Any]] ?? []
        let platformDict = config?["platform"] as? [String: Any]
        let resourcesDict = config?["resources"] as? [String: Any]
        let dnsDict = config?["dns"] as? [String: Any]

        let id = inspectStringIn(dict, keys: ["id"]) ?? inspectStringIn(config ?? [:], keys: ["id"])
        let status = inspectStringIn(dict, keys: ["status"])
            ?? inspectStringIn(statusDict ?? [:], keys: ["state"])
        let image = inspectStringIn(imageDict ?? [:], keys: ["reference"]) ?? inspectStringIn(dict, keys: ["image"])
        let ipv4Address = inspectStringIn(networks.first ?? [:], keys: ["ipv4Address", "ipv4_address"])
        let ipv4Gateway = inspectStringIn(networks.first ?? [:], keys: ["ipv4Gateway", "ipv4_gateway"])
        let ipv6Address = inspectStringIn(networks.first ?? [:], keys: ["ipv6Address", "ipv6_address"])
        let macAddress = inspectStringIn(networks.first ?? [:], keys: ["macAddress", "mac_address"])
        let hostname = inspectStringIn(networks.first ?? [:], keys: ["hostname"])
            ?? inspectStringIn(configNetworks.first?["options"] as? [String: Any] ?? [:], keys: ["hostname"])

        let exec = inspectStringIn(initProcess ?? [:], keys: ["executable"]) ?? ""
        let args = (initProcess?["arguments"] as? [String]) ?? []
        let command = exec.isEmpty ? nil : ([exec] + args).joined(separator: " ")
        let environment = (initProcess?["environment"] as? [String]) ?? []
        let workingDir = inspectStringIn(initProcess ?? [:], keys: ["workingDirectory", "workingDir"])
            ?? inspectStringIn(config ?? [:], keys: ["workingDirectory", "workingDir"])
        let created = inspectStringIn(dict, keys: ["created", "creationDate"])
            ?? inspectStringIn(config ?? [:], keys: ["creationDate", "created"])
        let platformOS = inspectStringIn(platformDict ?? [:], keys: ["os"])
        let platformArch = inspectStringIn(platformDict ?? [:], keys: ["architecture"])
        let platform = (platformOS != nil && platformArch != nil) ? "\(platformOS!)/\(platformArch!)" : nil
        let runtimeHandler = inspectStringIn(config ?? [:], keys: ["runtimeHandler"])
        let rosetta = inspectBoolIn(config ?? [:], keys: ["rosetta"])
        let ssh = inspectBoolIn(config ?? [:], keys: ["ssh"])
        let readOnly = inspectBoolIn(config ?? [:], keys: ["readOnly", "readonly"])

        let resources = ContainerInspectFallback.Resources(
            cpus: inspectIntIn(resourcesDict ?? [:], keys: ["cpus"]),
            memoryBytes: inspectInt64In(resourcesDict ?? [:], keys: ["memoryInBytes", "memory"])
        )

        let dns = ContainerInspectFallback.DNS(
            domain: inspectStringIn(dnsDict ?? [:], keys: ["domain"]),
            nameservers: inspectStringArrayIn(dnsDict ?? [:], keys: ["nameservers"]),
            options: inspectStringArrayIn(dnsDict ?? [:], keys: ["options"]),
            searchDomains: inspectStringArrayIn(dnsDict ?? [:], keys: ["searchDomains", "search_domains"])
        )

        var ports: [String] = sockets.compactMap { socket in
            let host = inspectIntIn(socket, keys: ["hostPort"])
            let container = inspectIntIn(socket, keys: ["containerPort"])
            let proto = inspectStringIn(socket, keys: ["proto"])
            guard let host, let container, let proto else { return nil }
            return "\(host):\(container)/\(proto)"
        }
        let published = publishedPorts.compactMap { port -> String? in
            let hostAddress = inspectStringIn(port, keys: ["hostAddress"]) ?? "0.0.0.0"
            let hostPort = inspectIntIn(port, keys: ["hostPort"])
            let containerPort = inspectIntIn(port, keys: ["containerPort"])
            let proto = inspectStringIn(port, keys: ["proto"])
            guard let hostPort, let containerPort, let proto else { return nil }
            return "\(hostAddress):\(hostPort)->\(containerPort)/\(proto)"
        }
        ports.append(contentsOf: published)
        ports = Array(Set(ports)).sorted()

        let mounts = mountsArray.compactMap { mount -> ContainerInspectFallback.Mount? in
            guard let destination = inspectStringIn(mount, keys: ["destination"]) else { return nil }
            let source = inspectStringIn(mount, keys: ["source"]) ?? ""
            var kind: String?
            var volumeName: String?
            if let type = mount["type"] as? [String: Any], let first = type.keys.sorted().first {
                kind = first
                volumeName = inspectStringIn(type[first] as? [String: Any] ?? [:], keys: ["name"])
            } else if let type = mount["type"] as? String {
                kind = type
            }
            return ContainerInspectFallback.Mount(source: source, destination: destination, kind: kind, volumeName: volumeName)
        }

        // CLI ≥ 1.x extras.
        let labels = (config?["labels"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) { acc, kv in
            if let v = kv.value as? String { acc[kv.key] = v } else if let n = kv.value as? NSNumber { acc[kv.key] = n.stringValue }
        }
        let sysctls = (config?["sysctls"] as? [String: Any] ?? [:]).reduce(into: [String: String]()) { acc, kv in
            if let v = kv.value as? String { acc[kv.key] = v } else if let n = kv.value as? NSNumber { acc[kv.key] = n.stringValue }
        }
        var user: String?
        if let userDict = initProcess?["user"] as? [String: Any] {
            if let idDict = userDict["id"] as? [String: Any], let uid = inspectIntIn(idDict, keys: ["uid"]) {
                user = inspectIntIn(idDict, keys: ["gid"]).map { "\(uid):\($0)" } ?? "\(uid)"
            } else if let raw = userDict["raw"] as? [String: Any] {
                user = inspectStringIn(raw, keys: ["userString", "user"])
            } else {
                user = inspectStringIn(userDict, keys: ["userString", "user", "name"])
            }
        }
        let firstNetwork = networks.first ?? configNetworks.first ?? [:]
        let networkName = inspectStringIn(firstNetwork, keys: ["network", "name"])
            ?? inspectStringIn(configNetworks.first ?? [:], keys: ["network", "name"])
        let mtu = inspectIntIn(firstNetwork, keys: ["mtu"])
            ?? inspectIntIn(configNetworks.first?["options"] as? [String: Any] ?? [:], keys: ["mtu"])

        var result = ContainerInspectFallback(
            id: id,
            status: status,
            image: image,
            ipv4Address: ipv4Address,
            ipv4Gateway: ipv4Gateway,
            ipv6Address: ipv6Address,
            macAddress: macAddress,
            hostname: hostname,
            ports: ports,
            mounts: mounts,
            command: command,
            environment: environment,
            created: created,
            workingDir: workingDir,
            platform: platform,
            runtimeHandler: runtimeHandler,
            rosetta: rosetta,
            ssh: ssh,
            readOnly: readOnly,
            resources: resources,
            dns: dns
        )
        result.startedDate = inspectStringIn(statusDict ?? [:], keys: ["startedDate", "started"])
        result.labels = labels
        result.user = user
        result.stopSignal = inspectStringIn(config ?? [:], keys: ["stopSignal"])
        result.capabilitiesAdded = inspectStringArrayIn(config ?? [:], keys: ["capAdd"])
        result.capabilitiesDropped = inspectStringArrayIn(config ?? [:], keys: ["capDrop"])
        result.sysctls = sysctls
        result.useInit = inspectBoolIn(config ?? [:], keys: ["useInit"])
        result.virtualization = inspectBoolIn(config ?? [:], keys: ["virtualization"])
        result.imageDigest = inspectStringIn(imageDict?["descriptor"] as? [String: Any] ?? [:], keys: ["digest"])
        result.networkName = networkName
        result.mtu = mtu
        return result
    } catch {
        return nil
    }
}

// MARK: - Untyped dictionary helpers
//
// These are intentionally permissive: they accept both native types and
// `NSNumber` / `String` representations, because the same field can come
// back in different shapes from different CLI versions. They're shared
// with the stats parser (`parseContainerStats`).

func inspectStringIn(_ dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dict[key] as? String {
            return value
        }
        if let value = dict[key] as? NSNumber {
            return value.stringValue
        }
    }
    return nil
}

func inspectIntIn(_ dict: [String: Any], keys: [String]) -> Int? {
    for key in keys {
        if let value = dict[key] as? NSNumber {
            return value.intValue
        }
        if let value = dict[key] as? String, let parsed = Int(value) {
            return parsed
        }
    }
    return nil
}

func inspectInt64In(_ dict: [String: Any], keys: [String]) -> Int64? {
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

func inspectBoolIn(_ dict: [String: Any], keys: [String]) -> Bool? {
    for key in keys {
        if let value = dict[key] as? Bool {
            return value
        }
        if let value = dict[key] as? NSNumber {
            return value.boolValue
        }
        if let value = dict[key] as? String {
            if value.lowercased() == "true" { return true }
            if value.lowercased() == "false" { return false }
        }
    }
    return nil
}

func inspectStringArrayIn(_ dict: [String: Any], keys: [String]) -> [String] {
    for key in keys {
        if let value = dict[key] as? [String] {
            return value
        }
    }
    return []
}
