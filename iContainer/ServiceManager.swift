
import Foundation
import Combine
import Containerization
import Logging

@MainActor
class ServiceManager: ObservableObject {
    @Published var isServiceRunning: Bool = false
    @Published var serviceStatus: String = "Unknown"
    private var timer: Timer?
    private let logger = Logger(label: "ServiceManager")

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
        let running = await isContainerServiceRunning()
        await MainActor.run {
            self.isServiceRunning = running
            self.serviceStatus = running ? "Service running" : "Service not running"
            logger.info("Container System Service status: \(self.serviceStatus)")
        }
    }

    @Published var serviceDetails: ServiceDetails?

    func isContainerServiceRunning() async -> Bool {
        let cliPath = "/usr/local/bin/container"
        guard FileManager.default.fileExists(atPath: cliPath) else {
            return false
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["system", "status"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                await parseServiceDetails(output)
            }
            
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func parseServiceDetails(_ output: String) async {
        var details = ServiceDetails()
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("application data root:") {
                details.dataRoot = line.components(separatedBy: "root: ").last?.trimmingCharacters(in: .whitespaces)
            } else if line.contains("application install root:") {
                details.installRoot = line.components(separatedBy: "root: ").last?.trimmingCharacters(in: .whitespaces)
            } else if line.contains("container-apiserver version:") {
                // Extract everything after the first colon
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count > 1 {
                    details.version = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            } else if line.contains("container-apiserver commit:") {
                details.commit = line.components(separatedBy: "commit: ").last?.trimmingCharacters(in: .whitespaces)
            }
        }
        
        await MainActor.run {
            self.serviceDetails = details
        }
    }

    func startService() async {
        let cliPath = "/usr/local/bin/container"
        guard FileManager.default.fileExists(atPath: cliPath) else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["system", "start"]
        
        do {
            try process.run()
            process.waitUntilExit()
            await checkServiceStatus()
        } catch {
            logger.error("Failed to start service: \(error)")
        }
    }

    func stopService() async {
        let cliPath = "/usr/local/bin/container"
        guard FileManager.default.fileExists(atPath: cliPath) else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["system", "stop"]
        
        do {
            try process.run()
            process.waitUntilExit()
            await checkServiceStatus()
        } catch {
            logger.error("Failed to stop service: \(error)")
        }
    }

    deinit {
        timer?.invalidate()
    }
}

struct ServiceDetails {
    var dataRoot: String?
    var installRoot: String?
    var version: String?
    var commit: String?
}
