
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
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { await self?.checkServiceStatus() }
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
            logger.info("Container System Service status: \(self.serviceStatus)")
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
        
        await MainActor.run {
            self.serviceDetails = details
        }
    }

    private func keyValuePair(from line: String) -> (key: String, value: String)? {
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

    private func isDataRootKey(_ key: String) -> Bool {
        key == "dataroot" || key == "data_root" || key == "appRoot".lowercased()
            || key == "approot"
    }

    private func isInstallRootKey(_ key: String) -> Bool {
        key == "installroot" || key == "install_root"
    }

    private func isVersionKey(_ key: String) -> Bool {
        key == "apiserver.version" || key == "container-apiserver.version" || key == "version"
    }

    private func isCommitKey(_ key: String) -> Bool {
        key == "apiserver.commit" || key == "container-apiserver.commit" || key == "commit"
    }

    private func parseVersionAndCommit(from value: String) -> (version: String?, commit: String?) {
        let version = regexFirstMatch(in: value, pattern: #"(\d+(?:\.\d+)+)"#)
        let commit = regexFirstMatch(in: value, pattern: #"commit:\s*([A-Fa-f0-9]+)"#)
        return (version, commit)
    }

    private func valueAfterColon(in line: String) -> String? {
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count > 1 else { return nil }
        let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private func regexFirstMatch(in line: String, pattern: String, group: Int = 1) -> String? {
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
            serviceLogs = "CLI 'container' non trovata"
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
            throw NSError(domain: "ServiceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "CLI 'container' non trovata"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }

    nonisolated static func resolveCLIPath() -> String? {
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

    nonisolated static func limitedLogOutput(_ output: String, maxLines: Int = 500) -> String {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else {
            return output
        }
        let visibleLines = lines.suffix(maxLines).joined(separator: "\n")
        return "Showing the latest \(maxLines) of \(lines.count) log lines.\n\n\(visibleLines)"
    }
}

struct ServiceDetails {
    var dataRoot: String?
    var installRoot: String?
    var version: String?
    var commit: String?
}
