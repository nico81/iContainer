import Foundation
import AppKit
import Combine
import Logging

/// Read-mostly bridge to a local Docker installation (Docker Desktop, or any
/// `docker` CLI pointed at a daemon via the current context).
///
/// iContainer never mutates Docker state: it lists images/containers,
/// inspects, and exports images with `docker save` so they can be imported
/// into Apple's `container` store. Availability is probed lazily and on a
/// slow timer — spawning `docker` is cheap but not free, and most users
/// never open the Docker features.
@MainActor
final class DockerWrapper: ObservableObject {
    enum Availability: Equatable {
        case unknown
        /// No `docker` binary found in the known locations / `$PATH`.
        case notInstalled
        /// Binary present but the daemon didn't answer (Docker Desktop
        /// stopped or still starting).
        case daemonUnavailable(String)
        case available(serverVersion: String)

        var isAvailable: Bool {
            if case .available = self { return true }
            return false
        }
    }

    struct SaveOutcome: Sendable {
        let archiveURL: URL
        /// `true` when the archive was narrowed to `linux/arm64`; `false`
        /// when the image had no arm64 variant and the full image was saved.
        let filteredToArm64: Bool
    }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var images: [DockerImage] = []
    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var isRefreshing = false
    @Published var lastErrorMessage: String?

    private let logger = Logger(label: "iContainer.docker")
    private var timer: Timer?
    private var isProbing = false

    /// Live file-system check; cheap and never stale.
    var isInstalled: Bool { Self.resolveCLIPath() != nil }

    init(startPolling: Bool = true) {
        if startPolling {
            startAvailabilityPolling()
        }
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Availability

    /// Probes every 30 s. Cheap when Docker isn't installed (a file-system
    /// check), one short-lived `docker version` otherwise.
    func startAvailabilityPolling(interval: TimeInterval = 30) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refreshAvailability() }
        }
        Task { await refreshAvailability() }
    }

    func refreshAvailability() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }

        guard Self.resolveCLIPath() != nil else {
            if availability != .notInstalled {
                availability = .notInstalled
                images = []
                containers = []
            }
            return
        }
        do {
            let output = try await run(["version", "--format", "{{.Server.Version}}"])
            let version = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let next: Availability = version.isEmpty ? .daemonUnavailable("Docker daemon not responding.") : .available(serverVersion: version)
            if availability != next { availability = next }
        } catch {
            let message = Self.friendlyDaemonError(error.localizedDescription)
            if availability != .daemonUnavailable(message) {
                availability = .daemonUnavailable(message)
                images = []
                containers = []
            }
        }
    }

    /// Launches Docker Desktop (no-op if it's not installed).
    static func openDockerDesktop() {
        let url = URL(fileURLWithPath: "/Applications/Docker.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static var isDockerDesktopInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Docker.app")
    }

    // MARK: - Listing

    func refreshImages() async {
        guard availability.isAvailable else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let output = try await run(["images", "--format", "json"])
            let parsed = DockerParsers.parseImageList(output)
            if images != parsed { images = parsed }
        } catch {
            logger.error("docker images failed: \(error)")
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshContainers() async {
        guard availability.isAvailable else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let output = try await run(["ps", "-a", "--format", "json"])
            let parsed = DockerParsers.parseContainerList(output)
            if containers != parsed { containers = parsed }
        } catch {
            logger.error("docker ps failed: \(error)")
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshAll() async {
        await refreshAvailability()
        await refreshImages()
        await refreshContainers()
    }

    // MARK: - Inspect

    func inspectContainer(id: String) async -> DockerContainerInspect? {
        do {
            let output = try await run(["inspect", "--type", "container", id])
            return DockerParsers.parseContainerInspect(output)
        } catch {
            logger.error("docker inspect failed: \(error)")
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    /// The env baked into an image (`Config.Env`), or `[]` if unavailable.
    func imageEnvironment(reference: String) async -> [String] {
        do {
            let output = try await run(["image", "inspect", "--format", "{{json .Config.Env}}", reference])
            return DockerParsers.parseEnvironmentArray(output)
        } catch {
            return []
        }
    }

    /// `true` when Docker has a local image with exactly this reference
    /// (so `docker save <reference>` can export it).
    func hasImage(reference: String) -> Bool {
        let wanted = DockerParsers.normalizedReference(reference)
        return images.contains { image in
            guard let ref = image.reference else { return false }
            return DockerParsers.normalizedReference(ref) == wanted
        }
    }

    // MARK: - Export

    /// Exports `reference` to an OCI-layout tar via `docker save`. Tries a
    /// `linux/arm64`-only archive first (smaller, and what Apple silicon
    /// runs natively); if the image has no arm64 variant the full image is
    /// saved instead and `filteredToArm64` is `false`.
    func saveImage(reference: String, to directory: URL) async throws -> SaveOutcome {
        let safeName = reference.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let archiveURL = directory.appendingPathComponent("docker-\(safeName)-\(UUID().uuidString.prefix(8)).tar")
        do {
            _ = try await run(["save", reference, "--platform", "linux/arm64", "-o", archiveURL.path])
            return SaveOutcome(archiveURL: archiveURL, filteredToArm64: true)
        } catch {
            logger.info("docker save --platform linux/arm64 failed for \(reference), retrying without platform filter: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: archiveURL)
            _ = try await run(["save", reference, "-o", archiveURL.path])
            return SaveOutcome(archiveURL: archiveURL, filteredToArm64: false)
        }
    }

    // MARK: - Runner

    private func run(_ arguments: [String]) async throws -> String {
        guard let cliPath = Self.resolveCLIPath() else {
            throw NSError(domain: "iContainer.docker", code: 1, userInfo: [NSLocalizedDescriptionKey: "docker CLI not found"])
        }
        let result = try await Task.detached(priority: .utility) {
            try CLIProcess.run(executable: cliPath, arguments: arguments)
        }.value
        if result.status != 0 {
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = message.isEmpty
                ? "Command failed (docker \(arguments.joined(separator: " "))) with exit code \(result.status)."
                : message
            throw NSError(domain: "iContainer.docker", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: description])
        }
        return result.output
    }

    nonisolated static func resolveCLIPath() -> String? {
        SettingsManager.resolvedDockerCLIPath()
    }

    /// Collapses the CLI's multi-line socket error into one actionable line.
    nonisolated static func friendlyDaemonError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("cannot connect") || lower.contains("failed to connect") || lower.contains("docker.sock") || lower.contains("daemon") {
            return "Docker daemon isn't running."
        }
        return raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
    }
}
