import SwiftUI
import AppKit

struct ServiceDetailView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var statsStore: ContainerStatsStore
    @EnvironmentObject var releaseChecker: ContainerReleaseChecker
    @State private var selectedTab = 0
    @State private var isRemovingRegistryCredentials = false
    @State private var showingRemoveRegistryCredentialsConfirmation = false
    @State private var serviceStatsRefreshTask: Task<Void, Never>?
    @State private var serviceLogsFilter = ""

    private let serviceStatsRefreshNanos: UInt64 = 3_000_000_000
    private let serviceStatsChartWindow: TimeInterval = 300
    
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0:
                    serviceInfoView
                case 1:
                    serviceStatsView
                case 2:
                    serviceLogsView
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Apple container service")
        // Match the container detail view: the tab switcher lives in the
        // toolbar (Liquid Glass control layer), not in the content.
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Stats").tag(1)
                    Text("Logs").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
        }
        .task {
            await serviceManager.checkServiceStatus()
            await releaseChecker.checkForUpdateIfNeeded()
        }
        .task(id: selectedTab) {
            if selectedTab == 2 && serviceManager.serviceLogs.isEmpty {
                await serviceManager.refreshServiceLogs()
            }
        }
        .confirmationDialog(
            "Remove saved registry credentials?",
            isPresented: $showingRemoveRegistryCredentialsConfirmation,
            titleVisibility: .visible
        ) {
            if let host = registryPrimaryHost {
                Button("Remove Credentials for \(host)", role: .destructive) {
                    removeRegistryCredentials(host: host)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can log in again later from the Registry Login action.")
        }
    }

    private var serviceInfoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apple container service")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        StatusBadge(status: serviceManager.isServiceRunning ? "Running" : "Stopped")
                    }
                    Text(serviceManager.serviceStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Last check: \(lastCheckedAtText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                if let details = serviceManager.serviceDetails {
                    // Version Info
                    DetailSection(title: "Version Information", icon: "info.circle") {
                        DetailRow(label: "Version", value: details.version ?? "-")
                        DetailRow(label: "Commit", value: details.commit ?? "-", isMonospaced: true)
                        DetailRow(label: "Latest release", value: latestReleaseText)
                        if releaseChecker.isUpdateAvailable {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.accentColor)
                                Text("A newer version is available.")
                                    .font(.caption)
                                Link(
                                    "Download",
                                    destination: releaseChecker.latestReleaseURL ?? ContainerReleaseChecker.releasesPageURL
                                )
                                .font(.caption)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Paths
                    DetailSection(title: "System Paths", icon: "folder") {
                        DetailRow(label: "Install Root", value: details.installRoot ?? "-", isMonospaced: true)
                        DetailRow(label: "Data Root", value: details.dataRoot ?? "-", isMonospaced: true)
                    }

                    DetailSection(title: "Status Output", icon: "terminal") {
                        Text(serviceManager.lastStatusOutput.isEmpty ? "No status output available." : serviceManager.lastStatusOutput)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundColor(.secondary)
                    }

                    DetailSection(title: "Build Infrastructure", icon: "hammer") {
                        if containerManager.systemContainers.isEmpty {
                            Text("No build workers are currently running. Apple's `container` CLI starts one automatically on the first image build.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(containerManager.systemContainers) { container in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(container.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Spacer()
                                        StatusBadge(status: container.status == .running ? "Running" : "Stopped")
                                    }
                                    if let image = container.image {
                                        DetailRow(label: "Image", value: image, isMonospaced: true)
                                    }
                                    if let ip = container.ipAddress {
                                        DetailRow(label: "Address", value: ip, isMonospaced: true)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            Text("Managed automatically by the `container` CLI. These workers don't appear in the sidebar; they spin up on `container build` and stay running to speed up subsequent builds.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }

                    DetailSection(title: "Registry Authentication", icon: "person.badge.key") {
                        DetailRow(label: "Status", value: registryStatusText)
                        if let host = registryPrimaryHost {
                            DetailRow(label: "Host", value: host)
                        }
                        Text(registryStatusDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        if registryPrimaryHost != nil {
                            HStack {
                                Button(role: .destructive) {
                                    showingRemoveRegistryCredentialsConfirmation = true
                                } label: {
                                    if isRemovingRegistryCredentials {
                                        ProgressView()
                                            .scaleEffect(0.75)
                                    } else {
                                        Label("Remove Credentials", systemImage: "key.slash")
                                    }
                                }
                                .disabled(isRemovingRegistryCredentials)
                                Spacer()
                            }
                            .padding(.top, 4)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        if serviceManager.isServiceRunning {
                            ProgressView()
                            Text("Fetching service details...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text("Service is not running.")
                                .font(.headline)
                            Text("Start the service to view details.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
            }
            .padding()
        }
    }

    private var serviceStatsView: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 24
            let sectionInnerPadding: CGFloat = 32
            let sectionContentWidth = max(0, proxy.size.width - (horizontalPadding * 2) - sectionInnerPadding)
            let statsHeight = max(420, proxy.size.height - 180)
            let chartHeight = max(90, (statsHeight - 48) / 3)
            let infoBoxHeight = max(150, chartHeight)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    serviceStatsHeader
                    DetailSection(title: "Aggregate Resource Usage", icon: "speedometer") {
                        if let snapshot = statsStore.serviceHistory.latest {
                            HStack(alignment: .top, spacing: 16) {
                                serviceStatsNumeric(snapshot)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                                    .frame(width: sectionContentWidth * 0.33, alignment: .topLeading)
                                    .frame(minHeight: infoBoxHeight, alignment: .topLeading)
                                    .background(Color(nsColor: .controlBackgroundColor))
                                    .cornerRadius(AppRadius.card)
                                    .cardOutline(AppRadius.card)
                                VStack(alignment: .leading, spacing: 12) {
                                    ChartPanel(title: "CPU % of host (\(hostCoreCount) cores)") {
                                        StatTimelineChart(
                                            points: statsStore.serviceHistory.cpuSeries.map {
                                                StatPoint(time: $0.time, value: normalizedHostCpu($0.value))
                                            },
                                            domain: serviceChartDomain,
                                            yDomain: 0...100
                                        )
                                    }
                                    .frame(height: infoBoxHeight)
                                    ChartPanel(title: "Memory (MB)") {
                                        StatTimelineChart(
                                            points: statsStore.serviceHistory.memorySeries,
                                            domain: serviceChartDomain
                                        )
                                    }
                                    .frame(height: chartHeight)
                                    ChartPanel(title: "Network (KB/s)") {
                                        StatTimelineChart(
                                            points: statsStore.serviceHistory.netSeries,
                                            domain: serviceChartDomain
                                        )
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
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "pause.circle")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No running containers")
                                    .font(.headline)
                                Text("Start a container to begin collecting service-wide stats.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 60)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 16)
            }
        }
        .onAppear { startServiceStatsRefresh() }
        .onDisappear { stopServiceStatsRefresh() }
    }

    private var serviceStatsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Service-wide Stats")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Aggregate of every running container in the `container` service, including build workers. CPU is normalized against the host's \(hostCoreCount) cores (Activity-Monitor-style: 100% = host fully busy). Sourced from `container stats --no-stream`.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func serviceStatsNumeric(_ snapshot: ServiceStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailRow(label: "Running", value: "\(snapshot.runningContainerCount)")
            DetailRow(
                label: "CPU %",
                value: String(format: "%.2f%% of host", normalizedHostCpu(snapshot.cpuPercentValue))
            )
            DetailRow(
                label: "Memory",
                value: formatBytesPair(used: snapshot.memoryUsageBytes, limit: snapshot.memoryLimitBytes)
            )
            DetailRow(
                label: "Net Rx/Tx",
                value: formatBytesPair(used: snapshot.netRxBytes, limit: snapshot.netTxBytes)
            )
            DetailRow(
                label: "Block I/O",
                value: formatBytesPair(used: snapshot.blockReadBytes, limit: snapshot.blockWriteBytes)
            )
        }
    }

    private func formatBytesPair(used: Int64, limit: Int64) -> String {
        let usedStr = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
        if limit > 0 {
            let limitStr = ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
            return "\(usedStr) / \(limitStr)"
        }
        return usedStr
    }

    /// Number of host CPU cores. Used to normalize the raw cores-equivalent
    /// % returned by `container stats` into "% of host capacity",
    /// Activity-Monitor-style: 100% = the host is fully busy.
    private var hostCoreCount: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount)
    }

    private func normalizedHostCpu(_ raw: Double) -> Double {
        min(100, raw / Double(hostCoreCount))
    }

    private var serviceChartDomain: ClosedRange<Date> {
        let history = statsStore.serviceHistory
        let end = [
            history.cpuSeries.last?.time,
            history.memorySeries.last?.time,
            history.netSeries.last?.time
        ].compactMap { $0 }.max() ?? Date()
        return end.addingTimeInterval(-serviceStatsChartWindow)...end
    }

    private func startServiceStatsRefresh() {
        stopServiceStatsRefresh()
        serviceStatsRefreshTask = Task {
            while !Task.isCancelled {
                await containerManager.sampleServiceStats()
                try? await Task.sleep(nanoseconds: serviceStatsRefreshNanos)
            }
        }
    }

    private func stopServiceStatsRefresh() {
        serviceStatsRefreshTask?.cancel()
        serviceStatsRefreshTask = nil
    }

    private var serviceLogsView: some View {
        GeometryReader { proxy in
            let logAreaHeight = max(240, proxy.size.height - 220)
            VStack(alignment: .leading, spacing: 24) {
                DetailSection(title: "Logs", icon: "doc.plaintext") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Filter", text: $serviceLogsFilter)
                                .textFieldStyle(.roundedBorder)
                            if serviceManager.isLoadingServiceLogs {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Toggle("Follow", isOn: Binding(
                                get: { serviceManager.isFollowingServiceLogs },
                                set: { shouldFollow in
                                    if shouldFollow {
                                        serviceManager.startFollowingServiceLogs()
                                    } else {
                                        serviceManager.stopFollowingServiceLogs()
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            Button("Refresh") {
                                Task { await serviceManager.refreshServiceLogs() }
                            }
                            .disabled(serviceManager.isLoadingServiceLogs || serviceManager.isFollowingServiceLogs)
                            Button("Clear") {
                                serviceManager.clearServiceLogs()
                            }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(filteredServiceLogs, forType: .string)
                            }
                            .disabled(serviceManager.serviceLogs.isEmpty)
                        }

                        ScrollViewReader { proxy in
                            let s = SettingsManager.shared
                            ScrollView {
                                Text(filteredServiceLogs.isEmpty ? "No logs yet." : filteredServiceLogs)
                                    .font(.custom(s.terminalFontName, size: s.terminalFontSize, relativeTo: .body).monospaced())
                                    .foregroundColor(s.forceBlackTerminal ? .white : nil)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(s.forceBlackTerminal ? 8 : 0)
                                Color.clear
                                    .frame(height: 1)
                                    .id("SERVICE_LOGS_BOTTOM")
                            }
                            .frame(height: logAreaHeight)
                            .background(s.forceBlackTerminal ? Color.black : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: s.forceBlackTerminal ? AppRadius.small : 0))
                            .onChange(of: serviceManager.serviceLogs) { _, _ in
                                guard serviceManager.isFollowingServiceLogs else { return }
                                proxy.scrollTo("SERVICE_LOGS_BOTTOM", anchor: .bottom)
                            }
                        }

                        Text(serviceLogsCheckedAtText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if !serviceManager.isFollowingServiceLogs {
                serviceManager.startFollowingServiceLogs()
            }
        }
        .onDisappear {
            serviceManager.stopFollowingServiceLogs()
        }
    }

    private var filteredServiceLogs: String {
        let trimmed = serviceLogsFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let hideXPCNoise = SettingsManager.shared.hideXPCNoiseInLogs
        if trimmed.isEmpty && !hideXPCNoise { return serviceManager.serviceLogs }
        return serviceManager.serviceLogs
            .components(separatedBy: .newlines)
            .filter { line in
                if hideXPCNoise, Self.isXPCNoise(line) { return false }
                if trimmed.isEmpty { return true }
                return line.localizedCaseInsensitiveContains(trimmed)
            }
            .joined(separator: "\n")
    }

    /// Lines emitted by Apple's `container` daemons when a short-lived CLI
    /// client disconnects (e.g. after `container list`). iContainer's poll
    /// cycle triggers several of these per second, so hiding them is
    /// almost always what the user wants. Matched as a substring so the
    /// timestamp/logger prefix in front doesn't matter.
    private static func isXPCNoise(_ line: String) -> Bool {
        line.localizedCaseInsensitiveContains("xpc client handler")
    }

    private var latestReleaseText: String {
        if let latest = releaseChecker.latestVersion {
            return "v\(latest)"
        }
        return releaseChecker.isChecking ? "Checking..." : "-"
    }

    private var lastCheckedAtText: String {
        guard let date = serviceManager.lastCheckedAt else {
            return "Not checked yet"
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private var registryStatusText: String {
        switch containerManager.registryAuthState {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking..."
        case .authenticated:
            return "Credentials saved"
        case .notAuthenticated:
            return "No saved credentials"
        }
    }

    private var registryStatusDescription: String {
        switch containerManager.registryAuthState {
        case .authenticated:
            return "Saved registry credentials were found. Image pulls can still fail if the image reference is wrong, the repository is private, or the saved token is expired or lacks access."
        case .notAuthenticated:
            return "No saved registry credentials were found."
        case .checking:
            return "Checking saved registry credentials."
        case .unknown:
            return "Registry credential status could not be determined."
        }
    }

    private var serviceLogsCheckedAtText: String {
        guard let date = serviceManager.serviceLogsCheckedAt else {
            return "Last 15 minutes"
        }
        if serviceManager.isFollowingServiceLogs {
            return "Following live output since \(date.formatted(date: .omitted, time: .standard))"
        }
        return "Last 15 minutes, refreshed \(date.formatted(date: .omitted, time: .standard))"
    }

    private var registryPrimaryHost: String? {
        if case .authenticated(let hosts) = containerManager.registryAuthState {
            return hosts.first
        }
        return nil
    }

    private func removeRegistryCredentials(host: String) {
        guard !isRemovingRegistryCredentials else { return }
        isRemovingRegistryCredentials = true
        Task {
            _ = await containerManager.logoutRegistry(host: host)
            isRemovingRegistryCredentials = false
        }
    }
}
