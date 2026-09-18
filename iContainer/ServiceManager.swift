
import Foundation
import Combine
import Containerization
import Logging

@MainActor
class ServiceManager: ObservableObject {
    @Published var isServiceRunning: Bool = false
    @Published var serviceStatus: String = "Unknown"
    @Published var lastStatusOutput: String = ""
    @Published var lastCheckedAt: Date?
    @Published var serviceLogs: String = ""
    @Published var serviceLogsCheckedAt: Date?
    @Published var isLoadingServiceLogs: Bool = false
    @Published var isFollowingServiceLogs: Bool = false
    private var timer: Timer?
    private let logger = Logger(label: "ServiceManager")
    private var isCheckingStatus = false
    private var serviceLogsFollowProcess: Process?
    private var serviceLogsFollowPipe: Pipe?

    init() {
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = nil
        let interval = SettingsManager.storedRefreshIntervalSeconds()
        if interval > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task { await self?.checkServiceStatus() }
            }
        }
        Task { await checkServiceStatus() }
    }

    func checkServiceStatus() async {
        guard !isCheckingStatus else { return }
        isCheckingStatus = true
        defer { isCheckingStatus = false }

        let running = await isContainerServiceRunning()
        await MainActor.run {
            self.isServiceRunning = running
            self.serviceStatus = running ? "Service running" : "Service not running"
            logger.info("Container service status: \(self.serviceStatus)")
        }
    }

    @Published var serviceDetails: ServiceDetails?
    /// `container system property list` as `[section: [key: value]]`,
    /// refreshed with every status check (cheap). Feeds the "Service
    /// Defaults" section of the Info tab.
    @Published var systemProperties: [String: [String: String]] = [:]
    /// `container system df` — fetched on demand (it walks the image store,
    /// ~1 s), not on every poll.
    @Published var diskUsage: SystemDiskUsage?
    @Published var diskUsageCheckedAt: Date?
    @Published var isLoadingDiskUsage = false

    func isContainerServiceRunning() async -> Bool {
        guard Self.resolveCLIPath() != nil else {
            return false
        }

        do {
            let result = try await Task.detached(priority: .utility) {
                try Self.runCommandBlocking(["system", "status"])
            }.value
            if !result.output.isEmpty {
                await parseServiceDetails(result.output)
            }
            await MainActor.run {
                self.lastStatusOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastCheckedAt = Date()
            }
            if result.status == 0 {
                await refreshSystemProperties()
            }
            return result.status == 0
        } catch {
            return false
        }
    }

    /// Reads `container system property list` (TOML, cheap).
    func refreshSystemProperties() async {
        guard Self.resolveCLIPath() != nil else { return }
        let result = try? await Task.detached(priority: .utility) {
            try Self.runCommandBlocking(["system", "property", "list"])
        }.value
        guard let result, result.status == 0 else { return }
        let parsed = CLIParsers.parseSystemProperties(result.output)
        if parsed != systemProperties { systemProperties = parsed }
    }

    /// Reads `container system df --format json` (CLI ≥ 1.4). Older CLIs
    /// fail the command; `diskUsage` then stays `nil` and the section is
    /// hidden.
    func refreshDiskUsage() async {
        guard Self.resolveCLIPath() != nil, !isLoadingDiskUsage else { return }
        isLoadingDiskUsage = true
        defer { isLoadingDiskUsage = false }
        let result = try? await Task.detached(priority: .utility) {
            try Self.runCommandBlocking(["system", "df", "--format", "json"])
        }.value
        guard let result, result.status == 0,
              let parsed = CLIParsers.parseSystemDiskUsage(result.output) else { return }
        diskUsage = parsed
        diskUsageCheckedAt = Date()
    }
    
    private func parseServiceDetails(_ output: String) async {
        let details = CLIParsers.parseServiceDetails(output)
        await MainActor.run {
            self.serviceDetails = details
        }
    }

    func startService() async {
        guard Self.resolveCLIPath() != nil else { return }

        do {
            _ = try await Task.detached(priority: .utility) {
                try Self.runCommandBlocking(["system", "start"])
            }.value
            await checkServiceStatus()
        } catch {
            logger.error("Failed to start service: \(error)")
        }
    }

    func stopService() async {
        guard Self.resolveCLIPath() != nil else { return }

        do {
            _ = try await Task.detached(priority: .utility) {
                try Self.runCommandBlocking(["system", "stop"])
            }.value
            await checkServiceStatus()
        } catch {
            logger.error("Failed to stop service: \(error)")
        }
    }

    func refreshServiceLogs() async {
        guard !isLoadingServiceLogs, !isFollowingServiceLogs else { return }
        isLoadingServiceLogs = true
        defer { isLoadingServiceLogs = false }

        do {
            let result = try await Task.detached(priority: .utility) {
                try Self.runCommandBlocking(["system", "logs", "--last", "15m"])
            }.value
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let limitedOutput = Self.limitedLogOutput(output)
            if limitedOutput.isEmpty {
                serviceLogs = "No Apple Container service logs found in the last 15 minutes."
            } else if result.status == 0 {
                serviceLogs = limitedOutput
            } else {
                serviceLogs = "container system logs exited with status \(result.status):\n\n\(limitedOutput)"
            }
            serviceLogsCheckedAt = Date()
        } catch {
            logger.error("Failed to fetch service logs: \(error)")
            serviceLogs = error.localizedDescription
            serviceLogsCheckedAt = Date()
        }
    }

    func clearServiceLogs() {
        serviceLogs = ""
        serviceLogsCheckedAt = nil
    }

    func startFollowingServiceLogs() {
        guard !isFollowingServiceLogs else { return }
        guard let cliPath = Self.resolveCLIPath() else {
            serviceLogs = "container CLI not found"
            serviceLogsCheckedAt = Date()
            return
        }

        stopFollowingServiceLogs()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["system", "logs", "--last", "15m", "-f"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Empty data means EOF (the `-f` log process exited). Remove the
            // handler so the fd-monitoring queue stops re-invoking it in a
            // busy loop; the termination handler clears it too, but the EOF
            // read can land first.
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendServiceLogChunk(chunk)
            }
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, self.serviceLogsFollowProcess === process else { return }
                self.finishFollowingServiceLogs(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            serviceLogsFollowProcess = process
            serviceLogsFollowPipe = pipe
            isFollowingServiceLogs = true
            serviceLogsCheckedAt = Date()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            serviceLogs = "Failed to follow Apple Container service logs: \(error.localizedDescription)"
            serviceLogsCheckedAt = Date()
        }
    }

    func stopFollowingServiceLogs() {
        guard let process = serviceLogsFollowProcess else {
            isFollowingServiceLogs = false
            return
        }

        serviceLogsFollowPipe?.fileHandleForReading.readabilityHandler = nil
        serviceLogsFollowPipe = nil
        serviceLogsFollowProcess = nil
        isFollowingServiceLogs = false

        if process.isRunning {
            process.terminate()
        }
    }

    deinit {
        timer?.invalidate()
        serviceLogsFollowPipe?.fileHandleForReading.readabilityHandler = nil
        serviceLogsFollowProcess?.terminate()
    }
}

private extension ServiceManager {
    func appendServiceLogChunk(_ chunk: String) {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if serviceLogs.isEmpty {
            serviceLogs = trimmed
        } else {
            serviceLogs += "\n" + trimmed
        }
        serviceLogs = Self.limitedLogOutput(serviceLogs, maxLines: 1_000)
        serviceLogsCheckedAt = Date()
    }

    func finishFollowingServiceLogs(status: Int32) {
        serviceLogsFollowPipe?.fileHandleForReading.readabilityHandler = nil
        serviceLogsFollowPipe = nil
        serviceLogsFollowProcess = nil
        isFollowingServiceLogs = false
        serviceLogsCheckedAt = Date()
        if status != 0 {
            appendServiceLogChunk("container system logs -f exited with status \(status)")
        }
    }

    nonisolated static func runCommandBlocking(_ arguments: [String]) throws -> (output: String, status: Int32) {
        guard let cliPath = resolveCLIPath() else {
            throw NSError(domain: "ServiceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "container CLI not found"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Drain the pipe BEFORE waiting: outputs larger than the 64 KB
        // pipe buffer (e.g. system logs) deadlock if we wait first.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }

    nonisolated static func resolveCLIPath() -> String? {
        SettingsManager.resolvedContainerCLIPath()
    }

    nonisolated static func limitedLogOutput(_ output: String, maxLines: Int = 500) -> String {
        CLIParsers.limitedLogOutput(output, maxLines: maxLines)
    }
}

/// Everything `container system status` tells us. Field names follow the
/// CLI ≥ 1.4 table (`server.*`, `client.*`, `host.*`, `paths.*`,
/// `containers.*`, `images.*`); older CLIs only fill `version`, `commit`,
/// `dataRoot` and `installRoot`.
nonisolated struct ServiceDetails: Sendable, Equatable {
    var status: String?
    /// API server version (the running service). Kept as `version` because
    /// it's what the rest of the app has always shown.
    var version: String?
    var commit: String?
    var build: String?
    var serverAppName: String?
    /// The `container` CLI binary that answered. Differs from `version`
    /// right after a CLI upgrade until the service is restarted.
    var clientVersion: String?
    var clientCommit: String?
    var clientBuild: String?
    var hostOS: String?
    var hostArchitecture: String?
    var hostCPUs: Int?
    var dataRoot: String?
    var installRoot: String?
    var logRoot: String?
    var containersTotal: Int?
    var containersRunning: Int?
    var imagesTotal: Int?

    /// `true` when the CLI and the service report different versions —
    /// the usual state right after upgrading the CLI without restarting.
    var hasVersionMismatch: Bool {
        guard let clientVersion, let version else { return false }
        return clientVersion != version
    }
}

/// One row of `container system df`.
nonisolated struct DiskUsageCategory: Sendable, Equatable {
    var total: Int
    var active: Int
    var sizeBytes: Int64
    var reclaimableBytes: Int64
}

/// `container system df --format json` (CLI ≥ 1.4).
nonisolated struct SystemDiskUsage: Sendable, Equatable {
    var images: DiskUsageCategory?
    var containers: DiskUsageCategory?
    var volumes: DiskUsageCategory?
}
