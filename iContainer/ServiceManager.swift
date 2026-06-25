
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
            return result.status == 0
        } catch {
            return false
        }
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
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                return
            }
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

nonisolated struct ServiceDetails: Sendable, Equatable {
    var dataRoot: String?
    var installRoot: String?
    var version: String?
    var commit: String?
}
