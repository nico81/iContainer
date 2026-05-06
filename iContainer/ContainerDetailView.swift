import SwiftUI
import Charts
import Combine
import AppKit

struct ContainerDetailView: View {
    let containerId: String
    let initialTab: Int
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var details: ContainerDetails?
    @State private var isLoading = true
    @State private var rawInspectText: String = ""
    @State private var fallback: ContainerInspectFallback?
    @State private var selectedTab: Int

    init(containerId: String, initialTab: Int = 0) {
        self.containerId = containerId
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Stats").tag(1)
                    Text("Shell").tag(2)
                    Text("Logs").tag(3)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            ZStack {
                ContainerInfoView(
                    details: details,
                    fallback: fallback,
                    isLoading: isLoading,
                    formattedInspectOutput: formattedInspectOutput
                )
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)

                ContainerStatsView(
                    details: details,
                    containerId: containerId,
                    cpuLimit: fallback?.resources?.cpus
                )
                .opacity(selectedTab == 1 ? 1 : 0)
                .allowsHitTesting(selectedTab == 1)

                ContainerShellView(
                    details: details,
                    containerId: containerId
                )
                .opacity(selectedTab == 2 ? 1 : 0)
                .allowsHitTesting(selectedTab == 2)

                ContainerLogsView(
                    details: details,
                    containerId: containerId,
                    isActive: selectedTab == 3
                )
                .opacity(selectedTab == 3 ? 1 : 0)
                .allowsHitTesting(selectedTab == 3)
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

private struct ContainerInfoView: View {
    let details: ContainerDetails?
    let fallback: ContainerInspectFallback?
    let isLoading: Bool
    let formattedInspectOutput: String

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

                        VStack(alignment: .leading, spacing: 16) {
                            DetailSection(title: "Network", icon: "network") {
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
                                            MountDisplay(source: $0.source, destination: $0.destination)
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

private struct MountDisplay: Hashable {
    let source: String
    let destination: String
}

private struct MountLinksView: View {
    let mounts: [MountDisplay]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(mounts, id: \.self) { mount in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        MountPathColumn(title: "Host Path", value: mount.source)
                        Button {
                            openHostPath(mount.source)
                        } label: {
                            Image(systemName: hostPathIsDirectory(mount.source) ? "folder" : "doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(mount.source == "-")
                        .help(hostPathIsDirectory(mount.source) ? "Open folder" : "Open file")
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

private struct ContainerHeaderView: View {
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

private final class ContainerShellSession: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    private let containerId: String
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    private static var cache: [String: ContainerShellSession] = [:]

    static func shared(for containerId: String) -> ContainerShellSession {
        if let existing = cache[containerId] {
            return existing
        }
        let created = ContainerShellSession(containerId: containerId)
        cache[containerId] = created
        return created
    }

    private init(containerId: String) {
        self.containerId = containerId
    }

    func startIfNeeded() {
        guard !isRunning else { return }
        guard let cliPath = resolveContainerCLIPath() else {
            lastError = "CLI tool 'container' not found."
            return
        }

        let candidates: [[String]] = [
            ["exec", "-i", containerId, "/bin/sh"],
            ["exec", containerId, "/bin/sh"]
        ]

        for args in candidates {
            if startProcess(cliPath: cliPath, arguments: args) {
                return
            }
        }

        lastError = "Unable to start shell session."
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        isRunning = false
    }

    func send(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isRunning {
            startIfNeeded()
        }
        guard let data = (trimmed + "\n").data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
    }

    func clear() {
        output = ""
    }

    private func startProcess(cliPath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.output.append(contentsOf: chunk)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                if self?.output.isEmpty == true {
                    self?.lastError = "Shell session ended without output."
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = input
            self.outputPipe = output
            self.lastError = nil
            self.isRunning = true
            if self.output.isEmpty {
                self.output = "[shell started]\n"
            } else {
                self.output.append("\n[shell restarted]\n")
            }
            return true
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return false
        }
    }

    private func resolveContainerCLIPath() -> String? {
        let candidates = [
            "/usr/local/bin/container",
            "/opt/homebrew/bin/container"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for entry in pathEnv.split(separator: ":") {
                let path = String(entry) + "/container"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }
}

private struct ContainerShellView: View {
    let details: ContainerDetails?
    let containerId: String
    @StateObject private var session: ContainerShellSession
    @State private var command: String = ""
    @State private var autoScroll = true

    init(details: ContainerDetails?, containerId: String) {
        self.details = details
        self.containerId = containerId
        _session = StateObject(wrappedValue: ContainerShellSession.shared(for: containerId))
    }

    var body: some View {
        GeometryReader { proxy in
            let shellHeight = max(280, proxy.size.height - 240)
            VStack(alignment: .leading, spacing: 24) {
                if let details = details {
                    ContainerHeaderView(details: details)
                } else {
                    ProgressView("Loading Details...")
                        .padding(.top, 12)
                }

                DetailSection(title: "Shell", icon: "terminal") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Toggle("Auto Scroll", isOn: $autoScroll)
                                .toggleStyle(.switch)
                            Spacer()
                            Button("Clear") {
                                session.clear()
                            }
                        }

                        ScrollViewReader { scrollProxy in
                            ScrollView {
                                Text(session.output.isEmpty ? "Shell output will appear here." : session.output)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Color.clear
                                    .frame(height: 1)
                                    .id("SHELL_BOTTOM")
                            }
                            .frame(height: shellHeight)
                            .onChange(of: session.output) { _, _ in
                                guard autoScroll else { return }
                                withAnimation(.easeOut(duration: 0.15)) {
                                    scrollProxy.scrollTo("SHELL_BOTTOM", anchor: .bottom)
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            TextField("Command", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    let toSend = command
                                    command = ""
                                    session.send(toSend)
                                }
                            Button("Send") {
                                let toSend = command
                                command = ""
                                session.send(toSend)
                            }
                            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if let error = session.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            session.startIfNeeded()
        }
    }
}

private struct ContainerLogsView: View {
    let details: ContainerDetails?
    let containerId: String
    let isActive: Bool
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var logsText: String = ""
    @State private var isLoadingLogs = false
    @State private var autoRefresh = true
    @State private var autoScroll = true
    @State private var filterText = ""
    @State private var lastClearDate: Date = .distantPast
    @State private var lastSnapshotLines: [String] = []
    @State private var refreshTask: Task<Void, Never>?
    private let tailLines: Int = 200

    private let refreshIntervalNanos: UInt64 = 3_000_000_000

    var body: some View {
        GeometryReader { proxy in
            let logAreaHeight = max(240, proxy.size.height - 220)
            VStack(alignment: .leading, spacing: 24) {
                if let details = details {
                    ContainerHeaderView(details: details)
                } else {
                    ProgressView("Loading Details...")
                        .padding(.top, 12)
                }
                DetailSection(title: "Logs", icon: "doc.plaintext") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Filter", text: $filterText)
                                .textFieldStyle(.roundedBorder)
                            Toggle("Auto Refresh", isOn: $autoRefresh)
                                .toggleStyle(.switch)
                            Toggle("Auto Scroll", isOn: $autoScroll)
                                .toggleStyle(.switch)
                            Button("Refresh") {
                                Task { await refreshLogs() }
                            }
                            Button("Clear") {
                                logsText = ""
                                lastClearDate = Date()
                                lastSnapshotLines.removeAll()
                            }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(filteredLogs, forType: .string)
                            }
                        }

                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(filteredLogs.isEmpty ? "No logs yet." : filteredLogs)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Color.clear
                                    .frame(height: 1)
                                    .id("BOTTOM")
                            }
                            .frame(height: logAreaHeight)
                            .onChange(of: logsText) { _, _ in
                                if autoScroll {
                                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { startAutoRefresh() }
        .onDisappear { stopAutoRefresh() }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }

    private var filteredLogs: String {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return logsText }
        return logsText
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .joined(separator: "\n")
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        guard isActive else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                if autoRefresh {
                    await refreshLogs()
                }
                try? await Task.sleep(nanoseconds: refreshIntervalNanos)
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refreshLogs() async {
        isLoadingLogs = true
        if let output = await containerManager.fetchContainerLogs(containerId: containerId, tail: tailLines) {
            let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = cleaned
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .filter { line in
                    lineTimestamp(line) >= lastClearDate
                }
            if lastSnapshotLines.isEmpty && logsText.isEmpty {
                lastSnapshotLines = lines
                return
            }
            let delta = deltaLines(previous: lastSnapshotLines, current: lines)
            if !delta.isEmpty {
                if logsText.isEmpty {
                    logsText = delta.joined(separator: "\n")
                } else {
                    logsText += "\n" + delta.joined(separator: "\n")
                }
            }
            lastSnapshotLines = lines
        } else {
            logsText = "No logs available."
        }
        isLoadingLogs = false
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

private struct ContainerStatsView: View {
    let details: ContainerDetails?
    let containerId: String
    let cpuLimit: Int?
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var stats: ContainerStats?
    @State private var isLoading = false
    @State private var autoRefresh = true
    @State private var refreshTask: Task<Void, Never>?
    @State private var cpuSeries: [StatPoint] = []
    @State private var memorySeries: [StatPoint] = []
    @State private var netSeries: [StatPoint] = []
    @State private var lastNetTotalBytes: Int64?
    @State private var lastNetSampleDate: Date?

    private let refreshIntervalNanos: UInt64 = 3_000_000_000

    private struct StatsCache {
        var stats: ContainerStats?
        var cpuSeries: [StatPoint]
        var cpuSeriesIsRaw: Bool
        var memorySeries: [StatPoint]
        var netSeries: [StatPoint]
        var lastNetTotalBytes: Int64?
        var lastNetSampleDate: Date?
    }

    private static var cache: [String: StatsCache] = [:]
    private static var sharedTasks: [String: Task<Void, Never>] = [:]

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let sectionInnerPadding: CGFloat = 32
            let sectionContentWidth = max(0, proxy.size.width - (horizontalPadding * 2) - sectionInnerPadding)
            let statsHeight = max(420, proxy.size.height - 180)
            let chartHeight = max(90, (statsHeight - 48) / 3)
            let infoBoxHeight = max(150, chartHeight)
            ScrollView {
                if let details = details {
                    VStack(alignment: .leading, spacing: 24) {
                        ContainerHeaderView(details: details)
                        DetailSection(title: "Resource Stats", icon: "speedometer") {
                            if let stats = stats {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        DetailRow(label: "CPU %", value: normalizedCpuPercentText(for: stats))
                                        DetailRow(label: "Memory Usage", value: stats.memoryUsage)
                                        DetailRow(label: "Net Rx/Tx", value: stats.netRxTx)
                                        DetailRow(label: "Block I/O", value: stats.blockIo)
                                        DetailRow(label: "Pids", value: stats.pids)
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                                    .frame(width: sectionContentWidth * 0.33, alignment: .topLeading)
                                    .frame(minHeight: infoBoxHeight, alignment: .topLeading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                                    )

                                    VStack(alignment: .leading, spacing: 12) {
                                        ChartPanel(title: "CPU %") {
                                            Chart(cpuSeries) { point in
                                                LineMark(
                                                    x: .value("Time", point.time),
                                                    y: .value("CPU %", normalizedCpuPercentValue(raw: point.value))
                                                )
                                            }
                                            .chartXScale(domain: chartDomain)
                                            .chartYScale(domain: 0...100)
                                        }
                                        .frame(height: infoBoxHeight)

                                        ChartPanel(title: "Memory (MB)") {
                                            Chart(memorySeries) { point in
                                                LineMark(
                                                    x: .value("Time", point.time),
                                                    y: .value("Memory", point.value)
                                                )
                                            }
                                            .chartXScale(domain: chartDomain)
                                        }
                                        .frame(height: chartHeight)

                                        ChartPanel(title: "Network (KB/s)") {
                                            Chart(netSeries) { point in
                                                LineMark(
                                                    x: .value("Time", point.time),
                                                    y: .value("Net KB/s", point.value)
                                                )
                                            }
                                            .chartXScale(domain: chartDomain)
                                        }
                                        .frame(height: chartHeight)
                                    }
                                    .padding()
                                    .padding(.top, -16)
                                    .padding(.trailing, 4)
                                    .frame(width: sectionContentWidth * 0.67, alignment: .leading)
                                }
                                .padding(.top, -8)
                                .frame(width: sectionContentWidth, alignment: .leading)
                                .frame(height: statsHeight)
                            } else if isLoading {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .scaleEffect(1.1)
                                    Text("Loading")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 80)
                            } else {
                                Text("No stats available.")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, 16)
                } else {
                    ProgressView("Loading Details...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 50)
                }
            }
        }
        .onAppear {
            loadCache()
            ensureSharedPolling()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
            saveCache()
        }
    }

    private func normalizedCpuPercentText(for stats: ContainerStats) -> String {
        guard let normalized = normalizedCpuPercentValue(for: stats) else { return stats.cpuPercent }
        return String(format: "%.2f%%", normalized)
    }

    private func normalizedCpuPercentValue(for stats: ContainerStats) -> Double? {
        let rawValue = stats.cpuPercentValue ?? parsePercent(stats.cpuPercent)
        guard let cpu = rawValue else { return nil }
        let coreCount = effectiveCoreCount(for: cpu)
        return min(100, cpu / coreCount)
    }

    private func normalizedCpuPercentValue(raw cpuValue: Double) -> Double {
        let coreCount = effectiveCoreCount(for: cpuValue)
        return min(100, cpuValue / coreCount)
    }

    private func effectiveCoreCount(for cpuValue: Double) -> Double {
        if let cpuLimit, cpuLimit > 0 {
            return Double(cpuLimit)
        }
        if cpuValue > 100 {
            return Double(Int(ceil(cpuValue / 100.0)))
        }
        return 1
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                if autoRefresh {
                    await refreshStats()
                }
                try? await Task.sleep(nanoseconds: refreshIntervalNanos)
            }
        }
    }

    private func ensureSharedPolling() {
        if Self.sharedTasks[containerId] != nil { return }
        let manager = containerManager
        Self.sharedTasks[containerId] = Task {
            while !Task.isCancelled {
                if let output = await manager.fetchContainerStats(containerId: containerId) {
                    let parsed = parseContainerStats(output)
                    await MainActor.run {
                        if let parsed {
                            var cached = Self.cache[containerId] ?? StatsCache(
                                stats: nil,
                                cpuSeries: [],
                                cpuSeriesIsRaw: true,
                                memorySeries: [],
                                netSeries: [],
                                lastNetTotalBytes: nil,
                                lastNetSampleDate: nil
                            )
                            cached.stats = parsed
                            cached = updateCacheSeries(cached: cached, with: parsed)
                            Self.cache[containerId] = cached
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: refreshIntervalNanos)
            }
        }
    }

    private func loadCache() {
        guard var cached = Self.cache[containerId] else { return }
        stats = cached.stats
        if !cached.cpuSeriesIsRaw {
            let rawFactor = effectiveCoreCount(for: cached.stats?.cpuPercentValue ?? parsePercent(cached.stats?.cpuPercent ?? "") ?? 0)
            cached.cpuSeries = cached.cpuSeries.map { StatPoint(time: $0.time, value: $0.value * rawFactor) }
            cached.cpuSeriesIsRaw = true
            Self.cache[containerId] = cached
        }
        cpuSeries = cached.cpuSeries
        memorySeries = cached.memorySeries
        netSeries = cached.netSeries
        lastNetTotalBytes = cached.lastNetTotalBytes
        lastNetSampleDate = cached.lastNetSampleDate
    }

    private func saveCache() {
        Self.cache[containerId] = StatsCache(
            stats: stats,
            cpuSeries: cpuSeries,
            cpuSeriesIsRaw: true,
            memorySeries: memorySeries,
            netSeries: netSeries,
            lastNetTotalBytes: lastNetTotalBytes,
            lastNetSampleDate: lastNetSampleDate
        )
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refreshStats() async {
        isLoading = true
        if let output = await containerManager.fetchContainerStats(containerId: containerId) {
            if let parsed = parseContainerStats(output) {
                stats = parsed
                updateSeries(with: parsed)
            } else {
                stats = nil
            }
        } else {
            stats = nil
        }
        if let cached = Self.cache[containerId] {
            applyCache(cached)
        }
        isLoading = false
    }

    private func updateSeries(with parsed: ContainerStats) {
        let updated = updateCacheSeries(
            cached: StatsCache(
                stats: parsed,
                cpuSeries: cpuSeries,
                cpuSeriesIsRaw: true,
                memorySeries: memorySeries,
                netSeries: netSeries,
                lastNetTotalBytes: lastNetTotalBytes,
                lastNetSampleDate: lastNetSampleDate
            ),
            with: parsed
        )
        applyCache(updated)
        saveCache()
    }

    private func updateCacheSeries(cached: StatsCache, with parsed: ContainerStats) -> StatsCache {
        var updated = cached
        let now = Date()
        let rawCpu = parsed.cpuPercentValue ?? parsePercent(parsed.cpuPercent) ?? 0
        updated.cpuSeries.append(StatPoint(time: now, value: rawCpu))
        if let memBytes = parsed.memoryUsageBytes {
            updated.memorySeries.append(StatPoint(time: now, value: Double(memBytes) / 1_048_576.0))
        }
        if let rx = parsed.netRxBytes, let tx = parsed.netTxBytes {
            let total = rx + tx
            if let lastTotal = updated.lastNetTotalBytes, let lastTime = updated.lastNetSampleDate {
                let deltaBytes = max(0, total - lastTotal)
                let elapsed = max(1.0, now.timeIntervalSince(lastTime))
                let kbPerSec = (Double(deltaBytes) / 1024.0) / elapsed
                updated.netSeries.append(StatPoint(time: now, value: kbPerSec))
            } else {
                updated.netSeries.append(StatPoint(time: now, value: 0))
            }
            updated.lastNetTotalBytes = total
            updated.lastNetSampleDate = now
        }
        let retentionCutoff = now.addingTimeInterval(-600)
        updated.cpuSeries = updated.cpuSeries.filter { $0.time >= retentionCutoff }
        updated.memorySeries = updated.memorySeries.filter { $0.time >= retentionCutoff }
        updated.netSeries = updated.netSeries.filter { $0.time >= retentionCutoff }
        return updated
    }

    private func applyCache(_ cached: StatsCache) {
        stats = cached.stats
        cpuSeries = cached.cpuSeries
        memorySeries = cached.memorySeries
        netSeries = cached.netSeries
        lastNetTotalBytes = cached.lastNetTotalBytes
        lastNetSampleDate = cached.lastNetSampleDate
    }

    private var chartDomain: ClosedRange<Date> {
        let now = Date()
        let earliest = now.addingTimeInterval(-300)
        let minTime = [
            cpuSeries.first?.time,
            memorySeries.first?.time,
            netSeries.first?.time
        ].compactMap { $0 }.min() ?? now
        let start = max(earliest, minTime)
        return start...now
    }
}

private struct ChartPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            content
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.35))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct ContainerStats: Equatable {
    let cpuPercent: String
    let memoryUsage: String
    let pids: String
    let netRxTx: String
    let blockIo: String
    let cpuPercentValue: Double?
    let memoryUsageBytes: Int64?
    let netRxBytes: Int64?
    let netTxBytes: Int64?
}

private func parseContainerStats(_ output: String) -> ContainerStats? {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let data = trimmed.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data, options: []) {
        if let array = json as? [[String: Any]], let first = array.first {
            return statsFromDict(first)
        } else if let dict = json as? [String: Any] {
            return statsFromDict(dict)
        }
    }
    return statsFromTable(trimmed)
}

private func statsFromDict(_ dict: [String: Any]) -> ContainerStats? {
    let cpu = stringIn(dict, keys: ["cpu", "cpuPercent", "cpu_percent", "cpuPct"]) ?? "-"
    let cpuValue = parsePercent(cpu)
    let memUsageBytes = int64In(dict, keys: ["memoryUsageBytes", "memUsageBytes"])
    let memLimitBytes = int64In(dict, keys: ["memoryLimitBytes", "memLimitBytes"])
    let memUsage = formatUsageAndLimit(usageBytes: memUsageBytes, limitBytes: memLimitBytes)
        ?? stringIn(dict, keys: ["memUsage", "memoryUsage", "mem_usage", "memory"])
        ?? "-"
    let pids = stringIn(dict, keys: ["pids", "numProcesses", "processes"]) ?? "-"
    let netRxBytes = int64In(dict, keys: ["networkRxBytes", "netRxBytes", "rxBytes"])
    let netTxBytes = int64In(dict, keys: ["networkTxBytes", "netTxBytes", "txBytes"])
    let netRxTx = formatRxTx(rxBytes: netRxBytes, txBytes: netTxBytes)
        ?? stringIn(dict, keys: ["netRx", "networkRx", "rx", "net_rx"])
        ?? "-"
    let blkReadBytes = int64In(dict, keys: ["blockReadBytes", "blkReadBytes", "readBytes"])
    let blkWriteBytes = int64In(dict, keys: ["blockWriteBytes", "blkWriteBytes", "writeBytes"])
    let blockIo = formatRxTx(rxBytes: blkReadBytes, txBytes: blkWriteBytes)
        ?? stringIn(dict, keys: ["blockRead", "blkRead", "block_read"])
        ?? "-"
    return ContainerStats(
        cpuPercent: cpu,
        memoryUsage: memUsage,
        pids: pids,
        netRxTx: netRxTx,
        blockIo: blockIo,
        cpuPercentValue: cpuValue,
        memoryUsageBytes: memUsageBytes,
        netRxBytes: netRxBytes,
        netTxBytes: netTxBytes
    )
}

private func statsFromTable(_ output: String) -> ContainerStats? {
    let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard lines.count >= 2 else { return nil }
    let header = lines[0]
    let valueLine = lines[1]
    let columnNames = ["Container ID", "Cpu %", "Memory Usage", "Net Rx/Tx", "Block I/O", "Pids"]
    let ranges = columnRanges(in: header, columns: columnNames)
    guard !ranges.isEmpty else { return nil }
    var map: [String: String] = [:]
    for (name, range) in ranges {
        let value = substring(valueLine, startOffset: range.start, endOffset: range.end)
            .trimmingCharacters(in: .whitespaces)
        map[name.lowercased()] = value
    }
    let cpu = map["cpu %"] ?? map["cpu%"] ?? "-"
    let cpuValue = parsePercent(cpu)
    let mem = map["memory usage"] ?? map["memusage"] ?? "-"
    let net = map["net rx/tx"] ?? map["netrx/tx"] ?? "-"
    let block = map["block i/o"] ?? map["block i/o"] ?? "-"
    let pids = map["pids"] ?? "-"
    let memBytes = parseUsageAndLimit(mem)?.usage
    let netBytes = parseRxTx(net)
    return ContainerStats(
        cpuPercent: cpu,
        memoryUsage: mem,
        pids: pids,
        netRxTx: net,
        blockIo: block,
        cpuPercentValue: cpuValue,
        memoryUsageBytes: memBytes,
        netRxBytes: netBytes?.rx,
        netTxBytes: netBytes?.tx
    )
}

private struct ColumnRange {
    let start: Int
    let end: Int
}

private func columnRanges(in header: String, columns: [String]) -> [String: ColumnRange] {
    var starts: [(name: String, offset: Int)] = []
    for name in columns {
        if let range = header.range(of: name) {
            let offset = header.distance(from: header.startIndex, to: range.lowerBound)
            starts.append((name, offset))
        }
    }
    let sorted = starts.sorted { $0.offset < $1.offset }
    var result: [String: ColumnRange] = [:]
    for (idx, item) in sorted.enumerated() {
        let start = item.offset
        let end = (idx + 1 < sorted.count) ? sorted[idx + 1].offset : header.count
        result[item.name] = ColumnRange(start: start, end: end)
    }
    return result
}

private func substring(_ text: String, startOffset: Int, endOffset: Int) -> String {
    let safeStart = max(0, min(startOffset, text.count))
    let safeEnd = max(safeStart, min(endOffset, text.count))
    let startIndex = text.index(text.startIndex, offsetBy: safeStart)
    let endIndex = text.index(text.startIndex, offsetBy: safeEnd)
    return String(text[startIndex..<endIndex])
}

private func formatUsageAndLimit(usageBytes: Int64?, limitBytes: Int64?) -> String? {
    guard let usageBytes else { return nil }
    let usage = ByteCountFormatter.string(fromByteCount: usageBytes, countStyle: .memory)
    if let limitBytes {
        let limit = ByteCountFormatter.string(fromByteCount: limitBytes, countStyle: .memory)
        return "\(usage) / \(limit)"
    }
    return usage
}

private func formatRxTx(rxBytes: Int64?, txBytes: Int64?) -> String? {
    guard let rxBytes, let txBytes else { return nil }
    let rx = ByteCountFormatter.string(fromByteCount: rxBytes, countStyle: .file)
    let tx = ByteCountFormatter.string(fromByteCount: txBytes, countStyle: .file)
    return "\(rx) / \(tx)"
}

private struct StatPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

private func parsePercent(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleaned = trimmed.replacingOccurrences(of: "%", with: "")
    return Double(cleaned)
}

private func parseUsageAndLimit(_ text: String) -> (usage: Int64, limit: Int64?)? {
    let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard let usage = parseSizeToBytes(parts.first) else { return nil }
    let limit = parts.count > 1 ? parseSizeToBytes(parts[1]) : nil
    return (usage, limit)
}

private func parseRxTx(_ text: String) -> (rx: Int64, tx: Int64)? {
    let parts = text.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count >= 2,
          let rx = parseSizeToBytes(parts[0]),
          let tx = parseSizeToBytes(parts[1]) else { return nil }
    return (rx, tx)
}

private func parseSizeToBytes(_ text: String?) -> Int64? {
    guard let text else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = trimmed.split(separator: " ")
    guard let numberPart = tokens.first, let value = Double(numberPart) else { return nil }
    let unit = tokens.count > 1 ? tokens[1].lowercased() : "b"
    let multiplier: Double
    switch unit {
    case "kb", "kib":
        multiplier = 1024
    case "mb", "mib":
        multiplier = 1024 * 1024
    case "gb", "gib":
        multiplier = 1024 * 1024 * 1024
    case "tb", "tib":
        multiplier = 1024 * 1024 * 1024 * 1024
    default:
        multiplier = 1
    }
    return Int64(value * multiplier)
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

private enum InfoTextStyle {
    static let labelFont = Font.caption
    static let valueFont = Font.body
    static let monospacedValueFont = Font.caption.monospaced()
}

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
                .font(InfoTextStyle.labelFont)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(value)
                .font(isMonospaced ? InfoTextStyle.monospacedValueFont : InfoTextStyle.valueFont)
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
