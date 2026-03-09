import SwiftUI

struct ContainerDetailView: View {
    let containerId: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var details: ContainerDetails?
    @State private var isLoading = true
    @State private var rawInspectText: String = ""
    @State private var fallback: ContainerInspectFallback?

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading Details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
            } else if let details = details {
                VStack(alignment: .leading, spacing: 24) {
                    // Header Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(details.name)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            Spacer()
                            StatusBadge(status: details.status ?? "unknown")
                        }
                        Text("ID: \(details.configuration?.id ?? "-")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }
                    .padding(.bottom, 8)

                    // Basic Info
                    DetailSection(title: "Basic Information", icon: "info.circle") {
                        DetailRow(label: "Image", value: details.configuration?.image?.reference ?? fallback?.image ?? "-")
                        DetailRow(label: "Command", value: details.command != "-" ? details.command : (fallback?.command ?? "-"), isMonospaced: true)
                        if let resources = fallback?.resources {
                            if let cpus = resources.cpus {
                                DetailRow(label: "CPUs", value: "\(cpus)")
                            }
                            if let memoryBytes = resources.memoryBytes {
                                DetailRow(label: "Memory", value: ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory))
                            }
                        }
                        if let created = fallback?.created {
                            DetailRow(label: "Created", value: created)
                        }
                        if let workingDir = fallback?.workingDir {
                            DetailRow(label: "Working Dir", value: workingDir, isMonospaced: true)
                        }
                        if let platform = fallback?.platform {
                            DetailRow(label: "Platform", value: platform)
                        }
                        if let runtime = fallback?.runtimeHandler {
                            DetailRow(label: "Runtime", value: runtime)
                        }
                        if let rosetta = fallback?.rosetta {
                            DetailRow(label: "Rosetta", value: rosetta ? "Enabled" : "Disabled")
                        }
                        if let ssh = fallback?.ssh {
                            DetailRow(label: "SSH", value: ssh ? "Enabled" : "Disabled")
                        }
                        if let readOnly = fallback?.readOnly {
                            DetailRow(label: "Read Only FS", value: readOnly ? "Yes" : "No")
                        }
                    }

                    // Network
                    DetailSection(title: "Network", icon: "network") {
                        DetailRow(label: "IPv4", value: details.networks?.first?.address ?? fallback?.ipv4Address ?? "-")
                        DetailRow(label: "IPv4 Gateway", value: fallback?.ipv4Gateway ?? "-")
                        DetailRow(label: "IPv6", value: fallback?.ipv6Address ?? "-")
                        DetailRow(label: "MAC", value: fallback?.macAddress ?? "-")
                        let ports = !details.portBindings.isEmpty ? details.portBindings : (fallback?.ports ?? [])
                        DetailRow(label: "Ports", value: ports.isEmpty ? "None" : ports.joined(separator: ", "))
                        if let hostname = fallback?.hostname {
                            DetailRow(label: "Hostname", value: hostname)
                        }
                    }

                    // Mounts
                    DetailSection(title: "Mounts", icon: "externaldrive") {
                        let mounts = details.configuration?.mounts
                        if let mounts, !mounts.isEmpty {
                            ForEach(mounts, id: \.self) { mount in
                                DetailRow(label: mount.source ?? "-", value: mount.destination ?? "-")
                            }
                        } else if let fallbackMounts = fallback?.mounts, !fallbackMounts.isEmpty {
                            ForEach(fallbackMounts, id: \.self) { mount in
                                DetailRow(label: mount.source, value: mount.destination)
                            }
                        } else {
                            Text("No volumes mounted.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }

                    // Environment
                    DetailSection(title: "Environment Variables", icon: "scroll") {
                        let env = details.configuration?.initProcess?.environment ?? fallback?.environment ?? []
                        if !env.isEmpty {
                            ForEach(env, id: \.self) { envVar in
                                let parts = envVar.split(separator: "=", maxSplits: 1)
                                if parts.count == 2 {
                                    DetailRow(label: String(parts[0]), value: String(parts[1]), isMonospaced: true)
                                } else {
                                    Text(envVar)
                                        .font(.caption)
                                        .monospaced()
                                }
                            }
                        } else {
                            Text("No environment variables set.")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                    }

                    if let dns = fallback?.dns {
                        DetailSection(title: "DNS", icon: "globe") {
                            if let domain = dns.domain {
                                DetailRow(label: "Domain", value: domain)
                            }
                            if !dns.nameservers.isEmpty {
                                DetailRow(label: "Nameservers", value: dns.nameservers.joined(separator: ", "))
                            }
                            if !dns.searchDomains.isEmpty {
                                DetailRow(label: "Search", value: dns.searchDomains.joined(separator: ", "))
                            }
                            if !dns.options.isEmpty {
                                DetailRow(label: "Options", value: dns.options.joined(separator: ", "))
                            }
                        }
                    }

                    DetailSection(title: "Raw Inspect Output", icon: "terminal") {
                        Text(formattedInspectOutput)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Could not load container details.")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 50)
            }
        }
        .navigationTitle(details?.name ?? "Details")
        .task(id: containerId) {
            await loadDetails()
        }
        .onChange(of: containerManager.containers) { _, _ in
            updateDetailsFromList()
        }
    }

    private func loadDetails() async {
        if details == nil {
            details = await containerManager.inspectContainer(containerId: containerId)
        }
        if let raw = await containerManager.inspectContainerRaw(containerId: containerId) {
            rawInspectText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            fallback = parseContainerInspect(rawInspectText)
        } else {
            rawInspectText = ""
            fallback = nil
        }
        isLoading = false
        updateDetailsFromList()
    }

    private func updateDetailsFromList() {
        guard let current = details,
              let match = containerManager.containers.first(where: { $0.id == containerId }) else {
            return
        }
        let statusText = match.status == .running ? "running" : "stopped"
        let updatedNetworks: [ContainerDetails.NetworkInfo]? = match.ipAddress != nil
            ? [ContainerDetails.NetworkInfo(address: match.ipAddress)]
            : current.networks
        let updatedImage: ContainerDetails.ImageInfo? = match.image != nil
            ? ContainerDetails.ImageInfo(reference: match.image)
            : current.configuration?.image
        let updatedConfiguration = ContainerDetails.ConfigurationData(
            id: current.configuration?.id,
            hostname: current.configuration?.hostname,
            image: updatedImage,
            mounts: current.configuration?.mounts,
            initProcess: current.configuration?.initProcess,
            publishedSockets: current.configuration?.publishedSockets
        )
        let updated = ContainerDetails(
            status: statusText,
            networks: updatedNetworks,
            configuration: updatedConfiguration
        )
        if updated != current {
            details = updated
        }
    }

    private var formattedInspectOutput: String {
        let trimmed = rawInspectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No details available." }
        guard let data = trimmed.data(using: .utf8) else { return trimmed }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8) ?? trimmed
        } catch {
            return trimmed
        }
    }
}

private struct ContainerInspectFallback: Hashable {
    struct Mount: Hashable {
        let source: String
        let destination: String
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
}

private func parseContainerInspect(_ raw: String) -> ContainerInspectFallback? {
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
        let networks = dict["networks"] as? [[String: Any]] ?? []
        let sockets = config?["publishedSockets"] as? [[String: Any]] ?? []
        let publishedPorts = config?["publishedPorts"] as? [[String: Any]] ?? []
        let mountsArray = config?["mounts"] as? [[String: Any]] ?? []
        let configNetworks = config?["networks"] as? [[String: Any]] ?? []
        let platformDict = config?["platform"] as? [String: Any]
        let resourcesDict = config?["resources"] as? [String: Any]
        let dnsDict = config?["dns"] as? [String: Any]

        let id = stringIn(dict, keys: ["id"]) ?? stringIn(config ?? [:], keys: ["id"])
        let status = stringIn(dict, keys: ["status"])
        let image = stringIn(imageDict ?? [:], keys: ["reference"]) ?? stringIn(dict, keys: ["image"])
        let ipv4Address = stringIn(networks.first ?? [:], keys: ["ipv4Address", "ipv4_address"])
        let ipv4Gateway = stringIn(networks.first ?? [:], keys: ["ipv4Gateway", "ipv4_gateway"])
        let ipv6Address = stringIn(networks.first ?? [:], keys: ["ipv6Address", "ipv6_address"])
        let macAddress = stringIn(networks.first ?? [:], keys: ["macAddress", "mac_address"])
        let hostname = stringIn(networks.first ?? [:], keys: ["hostname"])
            ?? stringIn(configNetworks.first?["options"] as? [String: Any] ?? [:], keys: ["hostname"])

        let exec = stringIn(initProcess ?? [:], keys: ["executable"]) ?? ""
        let args = (initProcess?["arguments"] as? [String]) ?? []
        let command = exec.isEmpty ? nil : ([exec] + args).joined(separator: " ")
        let environment = (initProcess?["environment"] as? [String]) ?? []
        let workingDir = stringIn(initProcess ?? [:], keys: ["workingDirectory", "workingDir"])
            ?? stringIn(config ?? [:], keys: ["workingDirectory", "workingDir"])
        let created = stringIn(dict, keys: ["created"])
            ?? stringIn(config ?? [:], keys: ["created"])
        let platformOS = stringIn(platformDict ?? [:], keys: ["os"])
        let platformArch = stringIn(platformDict ?? [:], keys: ["architecture"])
        let platform = (platformOS != nil && platformArch != nil) ? "\(platformOS!)/\(platformArch!)" : nil
        let runtimeHandler = stringIn(config ?? [:], keys: ["runtimeHandler"])
        let rosetta = boolIn(config ?? [:], keys: ["rosetta"])
        let ssh = boolIn(config ?? [:], keys: ["ssh"])
        let readOnly = boolIn(config ?? [:], keys: ["readOnly", "readonly"])

        let resources = ContainerInspectFallback.Resources(
            cpus: intIn(resourcesDict ?? [:], keys: ["cpus"]),
            memoryBytes: int64In(resourcesDict ?? [:], keys: ["memoryInBytes", "memory"])
        )

        let dns = ContainerInspectFallback.DNS(
            domain: stringIn(dnsDict ?? [:], keys: ["domain"]),
            nameservers: stringArrayIn(dnsDict ?? [:], keys: ["nameservers"]),
            options: stringArrayIn(dnsDict ?? [:], keys: ["options"]),
            searchDomains: stringArrayIn(dnsDict ?? [:], keys: ["searchDomains", "search_domains"])
        )

        var ports: [String] = sockets.compactMap { socket in
            let host = intIn(socket, keys: ["hostPort"])
            let container = intIn(socket, keys: ["containerPort"])
            let proto = stringIn(socket, keys: ["proto"])
            guard let host, let container, let proto else { return nil }
            return "\(host):\(container)/\(proto)"
        }
        let published = publishedPorts.compactMap { port -> String? in
            let hostAddress = stringIn(port, keys: ["hostAddress"]) ?? "0.0.0.0"
            let hostPort = intIn(port, keys: ["hostPort"])
            let containerPort = intIn(port, keys: ["containerPort"])
            let proto = stringIn(port, keys: ["proto"])
            guard let hostPort, let containerPort, let proto else { return nil }
            return "\(hostAddress):\(hostPort)->\(containerPort)/\(proto)"
        }
        ports.append(contentsOf: published)
        ports = Array(Set(ports)).sorted()

        let mounts = mountsArray.compactMap { mount -> ContainerInspectFallback.Mount? in
            guard let source = stringIn(mount, keys: ["source"]),
                  let destination = stringIn(mount, keys: ["destination"]) else {
                return nil
            }
            return ContainerInspectFallback.Mount(source: source, destination: destination)
        }

        return ContainerInspectFallback(
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
    } catch {
        return nil
    }
}

private func stringIn(_ dict: [String: Any], keys: [String]) -> String? {
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

private func intIn(_ dict: [String: Any], keys: [String]) -> Int? {
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

private func int64In(_ dict: [String: Any], keys: [String]) -> Int64? {
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

private func boolIn(_ dict: [String: Any], keys: [String]) -> Bool? {
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

private func stringArrayIn(_ dict: [String: Any], keys: [String]) -> [String] {
    for key in keys {
        if let value = dict[key] as? [String] {
            return value
        }
    }
    return []
}

// MARK: - UI Components

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(value)
                .font(isMonospaced ? .caption.monospaced() : .body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

struct StatusBadge: View {
    let status: String
    
    var color: Color {
        status.lowercased() == "running" ? .green : .red
    }
    
    var body: some View {
        Text(status.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(8)
    }
}
