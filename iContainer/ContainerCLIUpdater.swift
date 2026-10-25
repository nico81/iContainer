import Foundation
import AppKit
import Combine
import Logging

/// Installs or updates Apple's `container` CLI in place.
///
/// Mirrors what Apple's own `/usr/local/bin/update-container.sh` does —
/// download the signed installer package from the GitHub release, stop the
/// service, run `installer`, start the service — with two things the script
/// doesn't do: the package is verified (`spctl` + the Apple Containerization
/// team ID) **before** anything privileged runs, and progress / errors are
/// surfaced step by step. The only privileged step is `installer -pkg … -target /`,
/// executed through macOS's own administrator prompt (`do shell script … with
/// administrator privileges`): the app never sees the password.
///
/// Homebrew installs (`/opt/homebrew/bin/container`) are upgraded with
/// `brew upgrade container` instead, which needs no privileges. When no CLI
/// is found at all the same package flow is a fresh install: nothing to stop
/// beforehand, and the first service start installs the default kernel.
@MainActor
final class ContainerCLIUpdater: ObservableObject {
    enum InstallMethod: Equatable {
        case package
        case homebrew(brewPath: String)
        case unknown

        var label: String {
            switch self {
            case .package: return "Apple installer package"
            case .homebrew: return "Homebrew"
            case .unknown: return "unknown"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case downloading(fraction: Double?)
        case verifying
        case stoppingService
        case installing
        case startingService
        case restartingContainers
        case done(version: String)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .idle, .done, .failed: return false
            default: return true
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var log: [String] = []

    /// Pinned signer of Apple's container packages (Developer ID Installer:
    /// Apple Inc. - Containerization). Anything else is refused even if
    /// notarized.
    nonisolated static let expectedTeamID = "UPBK2H6LZM"

    private let logger = Logger(label: "iContainer.cliUpdater")

    // MARK: - Install method

    nonisolated static func detectInstallMethod(cliPath: String?) -> InstallMethod {
        let path = cliPath ?? SettingsManager.resolvedContainerCLIPath() ?? ""
        let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) ?? path
        if path.hasPrefix("/opt/homebrew/") || resolved.contains("/Cellar/") || resolved.contains("/homebrew/") {
            for brew in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] where FileManager.default.isExecutableFile(atPath: brew) {
                return .homebrew(brewPath: brew)
            }
            return .unknown
        }
        if path.hasPrefix("/usr/local/") || FileManager.default.fileExists(atPath: "/usr/local/bin/update-container.sh") {
            return .package
        }
        return .unknown
    }

    // MARK: - Release asset selection (pure)

    /// Picks the signed installer package from a GitHub release's `assets`
    /// array, preferring the versioned name (same order as Apple's script).
    nonisolated static func signedPackageAsset(in release: [String: Any]) -> (name: String, url: URL, size: Int64)? {
        guard let assets = release["assets"] as? [[String: Any]] else { return nil }
        let tag = (release["tag_name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = ["container-\(tag)-installer-signed.pkg", "container-installer-signed.pkg"]
        for name in preferred {
            if let asset = assets.first(where: { ($0["name"] as? String) == name }),
               let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString) {
                return (name, url, (asset["size"] as? NSNumber)?.int64Value ?? 0)
            }
        }
        // Any signed pkg as a last resort.
        if let asset = assets.first(where: { (($0["name"] as? String) ?? "").hasSuffix("-installer-signed.pkg") }),
           let name = asset["name"] as? String,
           let urlString = asset["browser_download_url"] as? String, let url = URL(string: urlString) {
            return (name, url, (asset["size"] as? NSNumber)?.int64Value ?? 0)
        }
        return nil
    }

    /// Reads the signer's team ID out of `pkgutil --check-signature` output
    /// (`Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)`).
    nonisolated static func signerTeamID(fromPkgutilOutput output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("1. Developer ID Installer:") || trimmed.hasPrefix("Developer ID Installer:") else { continue }
            if let open = trimmed.lastIndex(of: "("), let close = trimmed.lastIndex(of: ")"), open < close {
                return String(trimmed[trimmed.index(after: open)..<close])
            }
        }
        return nil
    }

    nonisolated static func isTrustedPackage(spctlExitStatus: Int32, pkgutilOutput: String) -> Bool {
        spctlExitStatus == 0
            && pkgutilOutput.contains("signed by a developer certificate issued by Apple")
            && signerTeamID(fromPkgutilOutput: pkgutilOutput) == expectedTeamID
    }

    // MARK: - Update flow

    struct Plan {
        let version: String
        let assetName: String
        let assetURL: URL
        let assetSize: Int64
        let method: InstallMethod
        /// No CLI on this Mac yet: install rather than update.
        let isFreshInstall: Bool
    }

    /// Fetches the latest release and prepares the plan without side effects.
    func preparePlan() async throws -> Plan {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/apple/container/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw NSError(domain: "iContainer.cliUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read the latest release from GitHub."])
        }
        let cliPath = SettingsManager.resolvedContainerCLIPath()
        let method: InstallMethod = cliPath == nil ? .package : Self.detectInstallMethod(cliPath: cliPath)
        guard let asset = Self.signedPackageAsset(in: json) else {
            throw NSError(domain: "iContainer.cliUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: "Release \(tag) has no signed installer package."])
        }
        return Plan(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), assetName: asset.name, assetURL: asset.url, assetSize: asset.size, method: method, isFreshInstall: cliPath == nil)
    }

    /// Runs the whole update. `serviceManager` stops/starts the service;
    /// `containerManager` restarts the containers that were running when
    /// `restartContainers` is set. Never throws — the outcome is in `phase`.
    func run(plan: Plan, serviceManager: ServiceManager, containerManager: ContainerizationWrapper, restartContainers: Bool) async {
        guard !phase.isActive else { return }
        log = []
        let previouslyRunning = plan.isFreshInstall ? [] : containerManager.containers.filter { $0.status == .running }.map(\.id)
        do {
            switch plan.method {
            case .homebrew(let brewPath):
                phase = .stoppingService
                append("Stopping the container service…")
                await serviceManager.stopService()
                phase = .installing
                append("Running brew upgrade container…")
                let result = try await Task.detached(priority: .userInitiated) {
                    try CLIProcess.run(executable: brewPath, arguments: ["upgrade", "container"], environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"])
                }.value
                append(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
                guard result.status == 0 else { throw NSError(domain: "iContainer.cliUpdater", code: 10, userInfo: [NSLocalizedDescriptionKey: "brew upgrade failed (exit \(result.status))."]) }
            case .package, .unknown:
                let pkgURL = try await download(plan)
                defer { try? FileManager.default.removeItem(at: pkgURL.deletingLastPathComponent()) }
                try await verify(pkgURL)
                if !plan.isFreshInstall {
                    phase = .stoppingService
                    append("Stopping the container service…")
                    await serviceManager.stopService()
                }
                phase = .installing
                append("Installing \(plan.assetName) — macOS will ask for your administrator password.")
                try await installWithAdminPrivileges(pkgURL)
            }

            phase = .startingService
            append(plan.isFreshInstall
                   ? "Starting the container service — the first start downloads Apple's default Linux kernel…"
                   : "Starting the container service…")
            try await startService(serviceManager)
            if plan.isFreshInstall {
                // Swaps the setup screen for the main window.
                containerManager.checkDependencies()
            }

            if restartContainers, !previouslyRunning.isEmpty {
                phase = .restartingContainers
                append("Restarting \(previouslyRunning.count) container\(previouslyRunning.count == 1 ? "" : "s")…")
                await containerManager.refreshContainers()
                for id in previouslyRunning {
                    await containerManager.startContainer(containerId: id)
                }
            }

            let installed = serviceManager.serviceDetails?.clientVersion ?? serviceManager.serviceDetails?.version ?? plan.version
            append("Installed version: \(installed)")
            phase = .done(version: installed)
        } catch {
            logger.error("CLI update failed: \(error)")
            append("Error: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
            // Best effort: never leave the service down because we failed midway.
            if !serviceManager.isServiceRunning {
                append("Restarting the container service…")
                await serviceManager.startService()
            }
        }
    }

    func reset() {
        guard !phase.isActive else { return }
        phase = .idle
        log = []
    }

    // MARK: - Steps

    private var downloadTask: URLSessionDownloadTask?

    /// Cancels an in-flight download (no-op in other phases).
    func cancelDownload() {
        downloadTask?.cancel()
    }

    private func download(_ plan: Plan) async throws -> URL {
        phase = .downloading(fraction: 0)
        let sizeText = ByteCountFormatter.string(fromByteCount: plan.assetSize, countStyle: .file)
        append("Downloading \(plan.assetName) (\(sizeText))…")
        Self.removeStaleDownloadDirectories()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("icontainer-cli-update-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(plan.assetName)

        let downloader = PackageDownloader()
        let task = downloader.makeTask(url: plan.assetURL, expectedSize: plan.assetSize) { [weak self] fraction in
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction: fraction)
            }
        }
        downloadTask = task
        defer { downloadTask = nil }
        let received: Int64
        do {
            received = try await downloader.run(task: task, moveTo: destination)
        } catch {
            // Cancelled or failed: URLSession discards its partial file; drop
            // our directory too so nothing lingers.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        phase = .downloading(fraction: 1)
        append("Downloaded \(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)).")
        return destination
    }

    /// Leftovers from an interrupted run (quit mid-download).
    nonisolated private static func removeStaleDownloadDirectories() {
        let tmp = FileManager.default.temporaryDirectory
        guard let entries = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix("icontainer-cli-update-") {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func verify(_ pkgURL: URL) async throws {
        phase = .verifying
        append("Verifying the package signature…")
        let path = pkgURL.path
        let (spctl, pkgutil) = try await Task.detached(priority: .userInitiated) { () -> (CLIProcess.Result, CLIProcess.Result) in
            let a = try CLIProcess.run(executable: "/usr/sbin/spctl", arguments: ["-a", "-vv", "-t", "install", path])
            let b = try CLIProcess.run(executable: "/usr/sbin/pkgutil", arguments: ["--check-signature", path])
            return (a, b)
        }.value
        guard Self.isTrustedPackage(spctlExitStatus: spctl.status, pkgutilOutput: pkgutil.output) else {
            let signer = Self.signerTeamID(fromPkgutilOutput: pkgutil.output) ?? "unknown signer"
            throw NSError(domain: "iContainer.cliUpdater", code: 5, userInfo: [NSLocalizedDescriptionKey:
                "The package is not the Apple-signed container installer (signer: \(signer); spctl exit \(spctl.status)). Nothing was installed."])
        }
        append("Signature OK: Developer ID Installer: Apple Inc. - Containerization (\(Self.expectedTeamID)), notarized.")
    }

    /// `installer -pkg <pkg> -target /` through the system administrator
    /// prompt. The AppleScript runs **in-process** (`NSAppleScript`), so the
    /// SecurityAgent dialog is attributed to iContainer — "iContainer wants
    /// to make changes", with the app icon — instead of to a generic
    /// `osascript`. The password is typed into macOS's own dialog and never
    /// reaches the app. Runs on a background thread so the UI keeps
    /// updating while `installer` works.
    private func installWithAdminPrivileges(_ pkgURL: URL) async throws {
        let shellPath = "'" + pkgURL.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let shellCommand = "/usr/sbin/installer -pkg \(shellPath) -target /"
        let appleScriptLiteral = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(appleScriptLiteral)\" with administrator privileges"

        let output: String = try await withCheckedThrowingContinuation { continuation in
            let thread = Thread {
                guard let script = NSAppleScript(source: source) else {
                    continuation.resume(throwing: NSError(domain: "iContainer.cliUpdater", code: 9, userInfo: [NSLocalizedDescriptionKey: "Could not build the installer script."]))
                    return
                }
                var errorInfo: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                    let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "installer failed"
                    if number == -128 {
                        continuation.resume(throwing: NSError(domain: "iContainer.cliUpdater", code: 6, userInfo: [NSLocalizedDescriptionKey: "Installation cancelled at the administrator prompt."]))
                    } else {
                        continuation.resume(throwing: NSError(domain: "iContainer.cliUpdater", code: 7, userInfo: [NSLocalizedDescriptionKey: "\(message) (\(number))"]))
                    }
                    return
                }
                continuation.resume(returning: descriptor.stringValue ?? "")
            }
            thread.name = "iContainer.cliUpdater.installer"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { append(trimmed) }
        append("Package installed.")
    }

    /// `container system start --enable-kernel-install`: without the flag a
    /// first start (no kernel configured yet) asks on stdin, which an app
    /// can't answer. A no-op flag when the kernel is already there.
    private func startService(_ serviceManager: ServiceManager) async throws {
        guard let cliPath = SettingsManager.resolvedContainerCLIPath() else {
            throw NSError(domain: "iContainer.cliUpdater", code: 12, userInfo: [NSLocalizedDescriptionKey: "The container CLI isn't where the package installs it (/usr/local/bin)."])
        }
        let result = try await Task.detached(priority: .userInitiated) {
            try CLIProcess.run(executable: cliPath, arguments: ["system", "start", "--enable-kernel-install"])
        }.value
        await serviceManager.checkServiceStatus()
        guard result.status == 0 else {
            let tail = result.output.split(whereSeparator: { $0.isNewline }).suffix(3).joined(separator: "\n")
            if !tail.isEmpty { append(tail) }
            throw NSError(domain: "iContainer.cliUpdater", code: 11, userInfo: [NSLocalizedDescriptionKey: "The container service didn't start (exit \(result.status))."])
        }
    }

    private func append(_ line: String) {
        guard !line.isEmpty else { return }
        log.append(line)
        logger.info("\(line)")
    }
}

// MARK: - Download task bridge

/// Wraps a `URLSessionDownloadTask` (redirect-following, kernel-speed,
/// native progress) in an async call. Byte-wise `URLSession.bytes` was far
/// too slow for a 118 MB package in a debug build.
private final class PackageDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Int64, Error>?
    private var destination: URL?
    private var expectedSize: Int64 = 0
    private var onProgress: ((Double?) -> Void)?
    private var moveError: Error?
    private var received: Int64 = 0
    private lazy var session: URLSession = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    func makeTask(url: URL, expectedSize: Int64, onProgress: @escaping (Double?) -> Void) -> URLSessionDownloadTask {
        self.expectedSize = expectedSize
        self.onProgress = onProgress
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        return session.downloadTask(with: request)
    }

    func run(task: URLSessionDownloadTask, moveTo destination: URL) async throws -> Int64 {
        self.destination = destination
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        received = totalBytesWritten
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        onProgress?(total > 0 ? Double(totalBytesWritten) / Double(total) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Must move synchronously here: `location` is deleted when this returns.
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                moveError = NSError(domain: "iContainer.cliUpdater", code: 3, userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))."])
            }
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { continuation = nil; session.finishTasksAndInvalidate() }
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                continuation?.resume(throwing: NSError(domain: "iContainer.cliUpdater", code: 8, userInfo: [NSLocalizedDescriptionKey: "Download cancelled."]))
            } else {
                continuation?.resume(throwing: error)
            }
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            continuation?.resume(returning: received)
        }
    }
}
