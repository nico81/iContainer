import SwiftUI
import AppKit

/// "Info" tab of the container detail view.
///
/// Renders inspect output as a series of `DetailSection`s. Falls back to
/// `ContainerInspectFallback` for fields not surfaced by the JSON decoder
/// — that struct comes from parsing the raw inspect blob as a generic
/// dictionary, which covers fields that change shape across CLI versions.
struct ContainerInfoView: View {
    let details: ContainerDetails?
    let fallback: ContainerInspectFallback?
    let isLoading: Bool
    let formattedInspectOutput: String
    @EnvironmentObject var appNavigation: AppNavigation

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading Details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
            } else if let details = details {
                VStack(alignment: .leading, spacing: 24) {
                    ContainerHeaderView(details: details)

                    let columns = [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        DetailSection(title: "Basic Information", icon: "info.circle") {
                            DetailRow(label: "Image", value: details.configuration?.image?.reference ?? fallback?.image ?? "-")
                            if let digest = fallback?.imageDigest {
                                DetailRow(label: "Image Digest", value: digest, isMonospaced: true)
                            }
                            DetailRow(label: "Command", value: details.command != "-" ? details.command : (fallback?.command ?? "-"), isMonospaced: true)
                            if let user = fallback?.user {
                                DetailRow(label: "User", value: user, isMonospaced: true)
                            }
                            if let resources = fallback?.resources {
                                if let cpus = resources.cpus {
                                    DetailRow(label: "CPUs", value: "\(cpus)")
                                }
                                if let memoryBytes = resources.memoryBytes {
                                    DetailRow(label: "Memory", value: ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory))
                                }
                            }
                            if let created = fallback?.created {
                                DetailRow(label: "Created", value: Self.formatDate(created))
                            }
                            if let started = fallback?.startedDate, details.status?.lowercased() == "running" {
                                DetailRow(label: "Started", value: Self.formatDate(started) + Self.uptimeSuffix(started))
                            }
                            if let stopSignal = fallback?.stopSignal {
                                DetailRow(label: "Stop Signal", value: stopSignal, isMonospaced: true)
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
                            if fallback?.useInit == true {
                                DetailRow(label: "Init Process", value: "Enabled")
                            }
                            if fallback?.virtualization == true {
                                DetailRow(label: "Nested Virtualization", value: "Enabled")
                            }
                            if let fb = fallback, !fb.capabilitiesAdded.isEmpty || !fb.capabilitiesDropped.isEmpty {
                                DetailRow(
                                    label: "Capabilities",
                                    value: [fb.capabilitiesAdded.isEmpty ? nil : "+ " + fb.capabilitiesAdded.joined(separator: ", "),
                                            fb.capabilitiesDropped.isEmpty ? nil : "− " + fb.capabilitiesDropped.joined(separator: ", ")]
                                        .compactMap { $0 }.joined(separator: "\n"),
                                    isMonospaced: true
                                )
                            }
                            if let fb = fallback, !fb.sysctls.isEmpty {
                                DetailRow(label: "Sysctls", value: fb.sysctls.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"), isMonospaced: true)
                            }
                        }

                        if let fb = fallback, !fb.labels.isEmpty {
                            DetailSection(title: "Labels", icon: "tag") {
                                ForEach(fb.labels.keys.sorted(), id: \.self) { key in
                                    DetailRow(label: key, value: fb.labels[key] ?? "", isMonospaced: true)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            DetailSection(title: "Network", icon: "network") {
                                if let networkName = fallback?.networkName {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Network")
                                            .font(InfoTextStyle.labelFont)
                                            .foregroundColor(.secondary)
                                            .fontWeight(.medium)
                                        Button {
                                            appNavigation.showNetwork(name: networkName)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(networkName).font(InfoTextStyle.valueFont)
                                                Image(systemName: "chevron.right").font(.caption2)
                                            }
                                        }
                                        .buttonStyle(.link)
                                        .help("Show network")
                                    }
                                    .padding(.vertical, 2)
                                }
                                DetailRow(label: "IPv4", value: details.networks?.first?.address ?? fallback?.ipv4Address ?? "-")
                                DetailRow(label: "IPv4 Gateway", value: fallback?.ipv4Gateway ?? "-")
                                DetailRow(label: "IPv6", value: fallback?.ipv6Address ?? "-")
                                DetailRow(label: "MAC", value: fallback?.macAddress ?? "-")
                                let ports = !details.portBindings.isEmpty ? details.portBindings : (fallback?.ports ?? [])
                                if ports.isEmpty {
                                    DetailRow(label: "Ports", value: "None")
                                } else {
                                    PortLinksView(ports: ports)
                                }
                                if let hostname = fallback?.hostname {
                                    DetailRow(label: "Hostname", value: hostname)
                                }
                                if let mtu = fallback?.mtu {
                                    DetailRow(label: "MTU", value: "\(mtu)")
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
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            DetailSection(title: "Mounts", icon: "externaldrive") {
                                let mounts = details.configuration?.mounts
                                if let mounts, !mounts.isEmpty {
                                    MountLinksView(
                                        mounts: mounts.map {
                                            MountDisplay(source: $0.source ?? "-", destination: $0.destination ?? "-")
                                        }
                                    )
                                } else if let fallbackMounts = fallback?.mounts, !fallbackMounts.isEmpty {
                                    MountLinksView(
                                        mounts: fallbackMounts.map {
                                            MountDisplay(source: $0.source, destination: $0.destination, kind: $0.kind, volumeName: $0.volumeName)
                                        }
                                    )
                                } else {
                                    Text("No volumes mounted.")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }

                            DetailSection(title: "Environment Variables", icon: "scroll") {
                                let env = details.configuration?.initProcess?.environment ?? fallback?.environment ?? []
                                if !env.isEmpty {
                                    ForEach(env, id: \.self) { envVar in
                                        let parts = envVar.split(separator: "=", maxSplits: 1)
                                        if parts.count == 2 {
                                            DetailRow(label: String(parts[0]), value: String(parts[1]), isMonospaced: true)
                                        } else {
                                            Text(envVar)
                                                .font(InfoTextStyle.monospacedValueFont)
                                                .textSelection(.enabled)
                                        }
                                    }
                                } else {
                                    Text("No environment variables set.")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
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
    }
}

// MARK: - Port links

/// Renders a list of `host:container[/proto]` mappings with an "Open in
/// browser" button next to each one. The button parses the host port out
/// of the textual mapping with a regex.
private struct PortLinksView: View {
    let ports: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ports")
                .font(InfoTextStyle.labelFont)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            ForEach(ports, id: \.self) { port in
                HStack(spacing: 14) {
                    Text(port)
                        .font(InfoTextStyle.monospacedValueFont)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let hostPort = hostPort(from: port),
                       let url = URL(string: "http://localhost:\(hostPort)") {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            Label("Open", systemImage: "safari")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open http://localhost:\(hostPort)")
                    }
                }
            }
        }
    }

    private func hostPort(from mapping: String) -> String? {
        let patterns = [
            #"^\s*(?:\d{1,3}(?:\.\d{1,3}){3}:)?(\d+)\s*(?:->|:)"#,
            #"hostPort[^\d]*(\d+)"#
        ]
        for pattern in patterns {
            if let match = firstRegexGroup(in: mapping, pattern: pattern) {
                return match
            }
        }
        return nil
    }

    private func firstRegexGroup(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[groupRange])
    }
}

// MARK: - Mounts

/// A `host:container` mount pair; `Hashable` for use as a `ForEach` id.
struct MountDisplay: Hashable {
    let source: String
    let destination: String
    var kind: String? = nil
    var volumeName: String? = nil

    var isVolume: Bool { volumeName != nil }
    var kindLabel: String {
        switch kind {
        case "volume": return "Volume"
        case "virtiofs", "bind": return "Host Path"
        case "tmpfs": return "tmpfs"
        default: return "Host Path"
        }
    }
}

/// Renders mount pairs with an inline "open in Finder" button per host
/// path. Used by both the strongly-typed `mounts` and the dictionary
/// `fallback?.mounts` paths in `ContainerInfoView`.
private struct MountLinksView: View {
    let mounts: [MountDisplay]
    @EnvironmentObject var appNavigation: AppNavigation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mounts, id: \.self) { mount in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        if let volumeName = mount.volumeName {
                            MountPathColumn(title: "Volume", value: volumeName)
                            Button {
                                appNavigation.showVolume(name: volumeName)
                            } label: {
                                Image(systemName: "internaldrive")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Show volume")
                        } else if mount.kind == "tmpfs" {
                            MountPathColumn(title: "tmpfs", value: "in-memory")
                        } else {
                            MountPathColumn(title: mount.kindLabel, value: mount.source)
                            Button {
                                openHostPath(mount.source)
                            } label: {
                                Image(systemName: hostPathIsDirectory(mount.source) ? "folder" : "doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(mount.source == "-" || mount.source.isEmpty)
                            .help(hostPathIsDirectory(mount.source) ? "Open folder" : "Open file")
                        }
                    }

                    Divider()
                        .opacity(0.6)

                    MountPathColumn(title: "Container Path", value: mount.destination)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func openHostPath(_ path: String) {
        guard path != "-" else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func hostPathIsDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct MountPathColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(InfoTextStyle.labelFont)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(value)
                .font(InfoTextStyle.monospacedValueFont)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Date helpers

extension ContainerInfoView {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let isoFractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parseDate(_ raw: String) -> Date? {
        isoFormatter.date(from: raw) ?? isoFractionalFormatter.date(from: raw)
    }

    /// ISO timestamp → local `18 Sep 2026, 23:27`; unparseable input is shown as-is.
    static func formatDate(_ raw: String) -> String {
        guard let date = parseDate(raw) else { return raw }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// `" · up 2h 14m"` for a running container's start time.
    static func uptimeSuffix(_ raw: String, now: Date = Date()) -> String {
        guard let date = parseDate(raw) else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3_600, minutes = (seconds % 3_600) / 60
        let text = days > 0 ? "\(days)d \(hours)h" : hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return " · up \(text)"
    }
}

// MARK: - Header

/// Big title + status badge shown at the top of the Info / Shell / Logs /
/// Stats tabs. Internal (not file-private) so the other tab files can
/// reuse it.
struct ContainerHeaderView: View {
    let details: ContainerDetails

    var body: some View {
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
    }
}
