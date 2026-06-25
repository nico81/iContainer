import Foundation
import Combine
import Logging

@MainActor
class ContainerizationWrapper: ObservableObject {
    enum RegistryAuthState: Equatable {
        case unknown
        case checking
        case authenticated(hosts: [String])
        case notAuthenticated
    }

    @Published var containers: [Container] = []
    /// Infrastructure containers Apple's `container` CLI manages itself
    /// (currently the BuildKit shim). Kept separate from `containers` so
    /// they don't clutter the sidebar, and exposed for the Service view to
    /// surface their presence.
    @Published var systemContainers: [Container] = []
    @Published var updatingContainerIDs: Set<String> = []
    @Published var missingDependencies: [DependencyError] = []
    @Published var images: [ContainerImage] = []
    @Published var updatingImageIDs: Set<String> = []
    @Published var machines: [Machine] = []
    @Published var updatingMachineIDs: Set<String> = []
    @Published var lastErrorMessage: String?
    @Published var lastBuildOutput: String?
    @Published var registryAuthState: RegistryAuthState = .unknown
    /// Background-collected resource history per container. Kept as its own
    /// `ObservableObject` so per-tick stats samples don't re-render every
    /// view that observes this wrapper. See `ContainerStatsStore`.
    let statsStore = ContainerStatsStore()
    private let logger = Logger(label: "iContainer")
    private var timer: Timer?
    private var isPolling = false
    private var lastKnownStatuses: [String: ContainerStatus] = [:]

    init() {
        checkDependencies()
        startPolling()
    }
    
    func checkDependencies() {
        var errors: [DependencyError] = []
        if Self.resolveCLIPath() == nil {
            errors.append(.cliMissing)
        }
        self.missingDependencies = errors
    }
    
    // MARK: - Polling
    func startPolling() {
        timer?.invalidate()
        timer = nil
        let interval = SettingsManager.storedRefreshIntervalSeconds()
        if interval > 0 {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                Task {
                    await self?.pollContainerState()
                }
            }
        }
        Task {
            await pollContainerState()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func pollContainerState() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        await refreshContainers()
        await sampleRunningContainerStats()
        await sampleServiceStats()
        await refreshImages()
        await refreshMachines()
        await refreshRegistryAuthStatus()
    }

    // MARK: - Stats sampling

    /// Samples `container stats` for every running container and appends to
    /// `statsStore`, so the Stats tab's chart is already populated when the
    /// user opens it — even if the container has been running for a while.
    /// Driven by the polling loop; the open Stats tab additionally samples
    /// its own container via `sampleStats(for:)` for liveness.
    private func sampleRunningContainerStats() async {
        // Keep history only for running containers: stopping (or deleting) a
        // container drops its history, so a later restart charts fresh
        // instead of bridging the downtime with a stale flat line.
        let running = containers.filter { $0.status == .running }
        statsStore.prune(keeping: Set(running.map { $0.id }))
        for container in running {
            await sampleStats(for: container.id)
        }
    }

    /// Fetches and records a single stats sample for `id`. Safe to call for
    /// a stopped container — the CLI call simply fails and nothing is added.
    func sampleStats(for id: String) async {
        if let output = await fetchContainerStats(containerId: id),
           let parsed = parseContainerStats(output) {
            statsStore.record(stats: parsed, for: id)
        }
    }

    /// Fetches and records a single service-wide aggregate stats sample.
    /// Uses `container stats --no-stream` with no arguments — Apple's CLI
    /// returns one row per running container in a single shot, which is the
    /// authoritative "all containers" view. The aggregate includes
    /// infrastructure containers (e.g. BuildKit shim): they're real work
    /// the service is doing, and the user already sees them surfaced in the
    /// Build Infrastructure section of the Service tab.
    func sampleServiceStats() async {
        // Avoid charting a flat zero line while no container is running.
        // `container stats` would print only a header in that case.
        let anyRunning = containers.contains { $0.status == .running }
            || systemContainers.contains { $0.status == .running }
        guard anyRunning else {
            statsStore.clearServiceHistory()
            return
        }
        do {
            let output = try await runCommand(["stats", "--no-stream"])
            if let parsed = parseServiceStats(output) {
                statsStore.recordService(stats: parsed)
            }
        } catch {
            logger.error("Failed to sample service stats: \(error)")
        }
    }

    // MARK: - Terminal command runner
    private func runCommand(_ arguments: [String], standardInput: String? = nil) async throws -> String {
        let result = try await Task.detached(priority: .utility) {
            try Self.runCommandBlocking(arguments, standardInput: standardInput)
        }.value
        if result.status != 0 {
            let commandText = "container " + arguments.joined(separator: " ")
            let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let description = message.isEmpty
                ? "Command failed (\(commandText)) with exit code \(result.status)."
                : message
            throw NSError(domain: "iContainer", code: Int(result.status), userInfo: [NSLocalizedDescriptionKey: description])
        }
        return result.output
    }

    /// Streams stdout+stderr of the `container` CLI line-by-line to `onChunk`
    /// on the main actor while the process is still running. Used by the
    /// build flow so the create sheet can show progress live instead of
    /// freezing until completion. Returns the process exit status.
    private func runCommandStreaming(
        _ arguments: [String],
        onChunk: @MainActor @escaping (String) -> Void
    ) async throws -> Int32 {
        guard let cliPath = Self.resolveCLIPath() else {
            throw NSError(domain: "iContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "container CLI not found"])
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                    Task { @MainActor in onChunk(chunk) }
                }

                process.terminationHandler = { proc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                    if !remaining.isEmpty, let chunk = String(data: remaining, encoding: .utf8) {
                        Task { @MainActor in onChunk(chunk) }
                    }
                    continuation.resume(returning: proc.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func runCommandBlocking(_ arguments: [String], standardInput: String? = nil) throws -> (output: String, status: Int32) {
        guard let cliPath = resolveCLIPath() else {
            throw NSError(domain: "iContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "container CLI not found"])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments
        let pipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if standardInput != nil {
            process.standardInput = inputPipe
        }
        try process.run()
        if let standardInput {
            if let inputData = standardInput.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(inputData)
            }
            try? inputPipe.fileHandleForWriting.close()
        }
        // Drain the pipe BEFORE waiting: container CLI ≥ 1.0 can emit more
        // than the 64 KB pipe buffer (image list is ~140 KB), and waiting
        // first deadlocks — the child blocks on write, we block on exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "iContainer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to read command output"])
        }
        return (output, process.terminationStatus)
    }

    nonisolated private static func resolveCLIPath() -> String? {
        SettingsManager.resolvedContainerCLIPath()
    }

    // MARK: - Container Management
    func refreshContainers() async {
        do {
            let output = try await runCommand(["list", "--all", "--format", "json"])
            if let data = output.data(using: .utf8) {
                let decoded = try JSONDecoder().decode([ContainerCLI].self, from: data)
                func toContainer(_ cli: ContainerCLI) -> Container {
                    Container(
                        id: cli.configuration?.id ?? "",
                        name: cli.configuration?.hostname ?? cli.configuration?.id ?? "",
                        status: cli.status == "running" ? .running : .stopped,
                        image: cli.configuration?.image?.reference,
                        ipAddress: cli.networks?.first?.resolvedAddress
                    )
                }
                let sortByStatusThenName: (Container, Container) -> Bool = { lhs, rhs in
                    let lhsPriority = lhs.status == .running ? 0 : 1
                    let rhsPriority = rhs.status == .running ? 0 : 1
                    if lhsPriority != rhsPriority {
                        return lhsPriority < rhsPriority
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                let userCLIs = decoded.filter { !Self.isSystemContainer($0) }
                let systemCLIs = decoded.filter { Self.isSystemContainer($0) }
                let newContainers = userCLIs.map(toContainer).sorted(by: sortByStatusThenName)
                let newSystemContainers = systemCLIs.map(toContainer).sorted(by: sortByStatusThenName)

                if self.containers != newContainers {
                    self.containers = newContainers
                }
                if self.systemContainers != newSystemContainers {
                    self.systemContainers = newSystemContainers
                }
                notifyStatusTransitions(for: newContainers)
            }
        } catch {
            logger.error("Failed to refresh containers: \(error)")
            self.containers = []
        }
    }

    /// Fires a system notification whenever a container that we previously
    /// saw as running has transitioned to stopped. New containers and
    /// containers that disappear from the list are ignored — we only care
    /// about live → stopped, which covers explicit user stops as well as
    /// crashes. User stops surfaced here are intentional: macOS coalesces
    /// duplicates and the user has a master toggle in Settings.
    private func notifyStatusTransitions(for current: [Container]) {
        defer {
            lastKnownStatuses = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0.status) })
        }
        guard !lastKnownStatuses.isEmpty else { return }
        for container in current {
            guard let previous = lastKnownStatuses[container.id] else { continue }
            if previous == .running, container.status == .stopped {
                NotificationService.shared.notifyContainerStopped(name: container.name)
                // Discard the chart history so a later restart begins fresh
                // rather than bridging the downtime with a stale flat line.
                statsStore.clearHistory(for: container.id)
            }
        }
    }

    // MARK: - Image Management
    func refreshImages() async {
        do {
            let output = try await runCommand(["image", "list", "--format", "json"])
            let parsed = parseImageList(output)
            if self.images != parsed {
                self.images = parsed
            }
        } catch {
            logger.error("Failed to refresh images: \(error)")
        }
    }

    func pullImage(reference: String) async {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updatingImageIDs.insert(trimmed)
        defer { updatingImageIDs.remove(trimmed) }
        lastErrorMessage = nil
        do {
            _ = try await runCommand(["image", "pull", trimmed])
            await refreshImages()
            await refreshRegistryAuthStatus()
        } catch {
            logger.error("Failed to pull image: \(error)")
            lastErrorMessage = error.localizedDescription
            if Self.isRegistryAuthError(error.localizedDescription) {
                registryAuthState = .notAuthenticated
            }
        }
    }

    func deleteImage(reference: String) async {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updatingImageIDs.insert(trimmed)
        defer { updatingImageIDs.remove(trimmed) }
        lastErrorMessage = nil
        do {
            _ = try await runCommand(["image", "delete", trimmed])
            await refreshImages()
        } catch {
            logger.error("Failed to delete image: \(error)")
            lastErrorMessage = error.localizedDescription
        }
    }

    func inspectImage(reference: String) async -> String? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let output = try await runCommand(["image", "inspect", trimmed])
            return output
        } catch {
            logger.error("Failed to inspect image: \(error)")
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func buildImage(
        tag: String,
        dockerfilePath: String,
        contextDirectory: String
    ) async -> Bool {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDockerfile = dockerfilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContext = contextDirectory.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTag.isEmpty else {
            lastErrorMessage = "Image tag is required."
            return false
        }
        guard !trimmedDockerfile.isEmpty else {
            lastErrorMessage = "Dockerfile is required."
            return false
        }
        guard !trimmedContext.isEmpty else {
            lastErrorMessage = "Build context folder is required."
            return false
        }

        lastErrorMessage = nil
        lastBuildOutput = ""
        do {
            let status = try await runCommandStreaming([
                "build",
                "--progress", "plain",
                "--tag", trimmedTag,
                "--file", trimmedDockerfile,
                trimmedContext
            ]) { [weak self] chunk in
                guard let self else { return }
                self.lastBuildOutput = (self.lastBuildOutput ?? "") + chunk
            }
            if status != 0 {
                let collected = lastBuildOutput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = collected.isEmpty
                    ? "container build failed with exit code \(status)."
                    : collected
                lastErrorMessage = message
                if Self.isRegistryAuthError(message) {
                    registryAuthState = .notAuthenticated
                }
                return false
            }
            await refreshImages()
            return true
        } catch {
            logger.error("Failed to build image: \(error)")
            lastErrorMessage = error.localizedDescription
            lastBuildOutput = error.localizedDescription
            if Self.isRegistryAuthError(error.localizedDescription) {
                registryAuthState = .notAuthenticated
            }
            return false
        }
    }

    func startContainer(containerId: String) async {
        updatingContainerIDs.insert(containerId)
        do {
            _ = try await runCommand(["start", containerId])
            await refreshContainers()
        } catch {
            logger.error("Failed to start container: \(error)")
            NotificationService.shared.notifyActionFailed(
                action: "Start",
                target: containerName(for: containerId),
                message: error.localizedDescription
            )
        }
        updatingContainerIDs.remove(containerId)
    }

    func stopContainer(containerId: String) async {
        updatingContainerIDs.insert(containerId)
        do {
            _ = try await runCommand(["stop", containerId])
            await refreshContainers()
        } catch {
            logger.error("Failed to stop container: \(error)")
            NotificationService.shared.notifyActionFailed(
                action: "Stop",
                target: containerName(for: containerId),
                message: error.localizedDescription
            )
        }
        updatingContainerIDs.remove(containerId)
    }

    private func containerName(for containerId: String) -> String {
        containers.first(where: { $0.id == containerId })?.name ?? containerId
    }

    func deleteContainer(containerId: String) async {
        if containerId.isEmpty {
            lastErrorMessage = "Cannot delete: container id is empty."
            return
        }
        updatingContainerIDs.insert(containerId)
        defer { updatingContainerIDs.remove(containerId) }
        lastErrorMessage = nil
        do {
            _ = try await runCommand(["delete", containerId])
            await refreshContainers()
            return
        } catch {
            logger.error("Failed to delete container: \(error)")
            do {
                _ = try await runCommand(["delete", "--force", containerId])
                await refreshContainers()
                return
            } catch {
                logger.error("Failed to force-delete container: \(error)")
                do {
                    _ = try await runCommand(["rm", containerId])
                    await refreshContainers()
                    return
                } catch {
                    logger.error("Failed to delete container with rm: \(error)")
                    lastErrorMessage = error.localizedDescription
                    NotificationService.shared.notifyActionFailed(
                        action: "Delete",
                        target: containerName(for: containerId),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    /// Creates a container via `container create` and returns its id/name as
    /// reported by the CLI on success, or `nil` on failure. The returned
    /// string is the same value that appears as `Container.id` after the
    /// next refresh, so callers can use it to navigate to the new container.
    @discardableResult
    func createContainer(
        image: String,
        name: String?,
        publishedPorts: [String] = [],
        volumes: [String] = [],
        environment: [String] = []
    ) async -> String? {
        let trimmedImage = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else {
            lastErrorMessage = "Image is required."
            return nil
        }

        var args: [String] = ["create"]
        lastErrorMessage = nil

        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args += ["--name", name.trimmingCharacters(in: .whitespacesAndNewlines)]
        }

        for env in environment {
            let value = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                args += ["-e", value]
            }
        }

        for port in publishedPorts {
            let value = port.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                args += ["-p", value]
            }
        }

        for volume in volumes {
            let value = volume.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                args += ["-v", value]
            }
        }

        args.append(trimmedImage)

        do {
            let output = try await runCommand(args)
            await refreshContainers()
            await refreshRegistryAuthStatus()
            let id = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return id.isEmpty ? nil : id
        } catch {
            logger.error("Failed to create container: \(error)")
            lastErrorMessage = error.localizedDescription
            if Self.isRegistryAuthError(error.localizedDescription) {
                registryAuthState = .notAuthenticated
            }
            return nil
        }
    }

    func updateContainerSettings(
        containerId: String,
        image: String,
        name: String?,
        publishedPorts: [String] = [],
        volumes: [String] = [],
        environment: [String] = []
    ) async -> Bool {
        guard let existing = containers.first(where: { $0.id == containerId }) else {
            lastErrorMessage = "Container not found."
            return false
        }

        lastErrorMessage = nil
        let wasRunning = existing.status == .running

        if wasRunning {
            await stopContainer(containerId: containerId)
        }

        await deleteContainer(containerId: containerId)
        if lastErrorMessage != nil {
            return false
        }

        await createContainer(
            image: image,
            name: name,
            publishedPorts: publishedPorts,
            volumes: volumes,
            environment: environment
        )
        if lastErrorMessage != nil {
            return false
        }

        await refreshContainers()
        if wasRunning {
            if let targetName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty,
               let recreated = containers.first(where: { $0.name == targetName }) {
                await startContainer(containerId: recreated.id)
            } else {
                let candidates = containers.filter {
                    ($0.image ?? "") == image.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let recreated = candidates.last {
                    await startContainer(containerId: recreated.id)
                }
            }
        }

        await refreshContainers()
        return lastErrorMessage == nil
    }

    func refreshRegistryAuthStatus(showLoadingState: Bool = false) async {
        if showLoadingState || registryAuthState == .unknown {
            registryAuthState = .checking
        }
        let commandOptions: [[String]] = [
            ["registry", "ls"],
            ["r", "ls"],
            ["registry", "list"],
            ["r", "list"]
        ]
        for args in commandOptions {
            do {
                let output = try await runCommand(args)
                if Self.looksLikeTopLevelHelp(output) {
                    continue
                }
                let hosts = Self.parseRegistryHosts(output)
                registryAuthState = hosts.isEmpty ? .notAuthenticated : .authenticated(hosts: hosts)
                return
            } catch {
                let message = error.localizedDescription.lowercased()
                if message.contains("unknown subcommand")
                    || message.contains("invalid option")
                    || message.contains("help information")
                    || message.contains("usage:") {
                    continue
                }
                if Self.isRegistryAuthError(error.localizedDescription) {
                    registryAuthState = .notAuthenticated
                    return
                }
                break
            }
        }
        registryAuthState = .unknown
    }

    func loginRegistry(host: String, username: String, password: String) async -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, !trimmedUser.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Host, username, and password are required."
            return false
        }

        lastErrorMessage = nil
        let hostsToTry = Self.registryLoginHosts(for: trimmedHost)
        var didLoginAtLeastOnce = false
        var lastMeaningfulError: String?

        for candidateHost in hostsToTry {
            let passwordInput = password + "\n"
            let commandOptions: [([String], String?)] = [
                (["registry", "login", candidateHost, "--username", trimmedUser, "--password-stdin"], passwordInput),
                (["r", "login", candidateHost, "--username", trimmedUser, "--password-stdin"], passwordInput),
                (["registry", "login", candidateHost, "--username", trimmedUser, "--password", password], nil),
                (["r", "login", candidateHost, "--username", trimmedUser, "--password", password], nil)
            ]

            for (args, input) in commandOptions {
                do {
                    let output = try await runCommand(args, standardInput: input)
                    if Self.looksLikeTopLevelHelp(output) {
                        continue
                    }
                    didLoginAtLeastOnce = true
                    break
                } catch {
                    let message = error.localizedDescription.lowercased()
                    if message.contains("unknown subcommand")
                        || message.contains("invalid option")
                        || message.contains("help information")
                        || message.contains("usage:") {
                        continue
                    }
                    lastMeaningfulError = error.localizedDescription
                }
            }
        }

        await refreshRegistryAuthStatus(showLoadingState: true)
        if didLoginAtLeastOnce,
           case .authenticated = registryAuthState {
            return true
        }
        lastErrorMessage = lastMeaningfulError ?? "Login registry non verificata. Prova `container registry login docker.io --username <user>` da terminale e poi riprova."
        return false
    }

    func registryLoginCommand(host: String, username: String) -> String {
        "container registry login \(host) --username \(username)"
    }

    func logoutRegistry(host: String) async -> Bool {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            lastErrorMessage = "Registry host is required."
            return false
        }

        lastErrorMessage = nil
        let hostsToTry = Self.registryLoginHosts(for: trimmedHost)
        let expectedRemainingHosts = Set(hostsToTry.map { $0.lowercased() })
        var lastMeaningfulError: String?
        var didLogoutAtLeastOnce = false

        for candidateHost in hostsToTry {
            let commandOptions: [[String]] = [
                ["registry", "logout", candidateHost],
                ["r", "logout", candidateHost]
            ]

            for args in commandOptions {
                do {
                    let output = try await runCommand(args)
                    if Self.looksLikeTopLevelHelp(output) {
                        continue
                    }
                    didLogoutAtLeastOnce = true
                    break
                } catch {
                    let message = error.localizedDescription.lowercased()
                    if message.contains("unknown subcommand")
                        || message.contains("invalid option")
                        || message.contains("help information")
                        || message.contains("usage:") {
                        continue
                    }
                    lastMeaningfulError = error.localizedDescription
                }
            }
        }

        await refreshRegistryAuthStatus(showLoadingState: true)
        if didLogoutAtLeastOnce {
            if case .authenticated(let hosts) = registryAuthState {
                let remaining = Set(hosts.map { $0.lowercased() })
                if remaining.isDisjoint(with: expectedRemainingHosts) {
                    return true
                }
            } else {
                return true
            }
        }

        lastErrorMessage = lastMeaningfulError ?? "Logout registry non riuscito. Prova `container registry logout \(trimmedHost)` da terminale."
        return false
    }

    // The actual parsing logic lives in `CLIParsers` so it can be unit
    // tested without spinning up this MainActor-isolated type. These
    // forwarders keep the call sites in views unchanged.
    static func isRegistryAuthError(_ message: String) -> Bool {
        CLIParsers.isRegistryAuthError(message)
    }

    static func isLikelyDockerHubImageReferenceError(_ message: String) -> Bool {
        CLIParsers.isLikelyDockerHubImageReferenceError(message)
    }

    static func looksLikeTopLevelHelp(_ output: String) -> Bool {
        CLIParsers.looksLikeTopLevelHelp(output)
    }

    /// Hides infrastructure containers Apple's `container` CLI manages
    /// automatically (currently the BuildKit shim used during `container
    /// build`). Showing them mixes the user's containers with internal
    /// workers and is the same convention Docker Desktop / OrbStack use.
    private static let systemContainerImagePrefixes = [
        "ghcr.io/apple/container-builder-shim/"
    ]

    nonisolated static func isSystemContainer(_ cli: ContainerCLI) -> Bool {
        guard let reference = cli.configuration?.image?.reference else { return false }
        return systemContainerImagePrefixes.contains { reference.hasPrefix($0) }
    }

    static func registryLoginHosts(for host: String) -> [String] {
        CLIParsers.registryLoginHosts(for: host)
    }
    
    func inspectContainer(containerId: String) async -> ContainerDetails? {
        do {
            let output = try await runCommand(["inspect", containerId])
            if let data = output.data(using: .utf8) {
                // The command returns an array with a single element
                let decoded = try JSONDecoder().decode([ContainerDetails].self, from: data)
                return decoded.first
            }
        } catch {
            logger.error("Failed to inspect container: \(error)")
        }
        return nil
    }

    func inspectContainerRaw(containerId: String) async -> String? {
        do {
            return try await runCommand(["inspect", containerId])
        } catch {
            logger.error("Failed to raw-inspect container: \(error)")
            return nil
        }
    }

    func editableSettings(containerId: String) async -> ContainerEditableSettings? {
        let listed = containers.first(where: { $0.id == containerId })
        guard let raw = await inspectContainerRaw(containerId: containerId),
              var settings = Self.parseEditableSettings(raw) else {
            guard let listed else { return nil }
            return ContainerEditableSettings(
                image: listed.image ?? "",
                name: listed.name,
                ports: [],
                volumes: [],
                environment: []
            )
        }

        if settings.image.isEmpty {
            settings.image = listed?.image ?? ""
        }
        if settings.name.isEmpty {
            settings.name = listed?.name ?? ""
        }
        return settings
    }

    func fetchContainerLogs(containerId: String, tail: Int? = nil) async -> String? {
        let tailArgs: [String]
        if let tail {
            tailArgs = ["--tail", "\(tail)"]
        } else {
            tailArgs = []
        }
        let commandOptions: [[String]] = [
            ["logs"] + tailArgs + [containerId],
            ["logs"] + (tail != nil ? [] : ["-n", "200"]) + [containerId],
            ["logs"] + ["-n", "\(tail ?? 200)"] + [containerId],
            ["logs"] + ["--tail", "\(tail ?? 200)"] + [containerId],
            ["log"] + tailArgs + [containerId]
        ]
        for args in commandOptions {
            do {
                return try await runCommand(args)
            } catch {
                continue
            }
        }
        return nil
    }

    func fetchContainerStats(containerId: String) async -> String? {
        let commandOptions: [[String]] = [
            ["stats", "--no-stream", containerId],
            ["stats", "--format", "json", "--no-stream", containerId]
        ]
        for args in commandOptions {
            do {
                return try await runCommand(args)
            } catch {
                continue
            }
        }
        return nil
    }

    func execContainer(containerId: String, command: String) async -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let args = ["exec", containerId, "/bin/sh", "-c", trimmed]
        let fallback = ["exec", containerId, "--", "/bin/sh", "-c", trimmed]
        do {
            return try await runCommand(args)
        } catch {
            do {
                return try await runCommand(fallback)
            } catch {
                logger.error("Failed to run command in container: \(error)")
                lastErrorMessage = error.localizedDescription
                return nil
            }
        }
    }

    // MARK: - Machine Management

    func refreshMachines() async {
        do {
            let output = try await runCommand(["machine", "list", "--format", "json"])
            let parsed = CLIParsers.parseMachineList(output)
                .sorted { lhs, rhs in
                    let lhsPriority = lhs.status == .running ? 0 : 1
                    let rhsPriority = rhs.status == .running ? 0 : 1
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
                }
            if self.machines != parsed {
                self.machines = parsed
            }
        } catch {
            logger.error("Failed to refresh machines: \(error)")
        }
    }

    func inspectMachine(machineId: String) async -> MachineDetails? {
        do {
            let output = try await runCommand(["machine", "inspect", machineId])
            return CLIParsers.parseMachineDetails(output)
        } catch {
            logger.error("Failed to inspect machine: \(error)")
            return nil
        }
    }

    /// Boots a stopped machine. There is no `machine start`; `machine run -d`
    /// boots the machine and detaches, leaving it running. Multiple machines
    /// can run at the same time.
    func startMachine(machineId: String) async {
        updatingMachineIDs.insert(machineId)
        do {
            _ = try await runCommand(["machine", "run", "-n", machineId, "-d", "/bin/true"])
            await refreshMachines()
        } catch {
            logger.error("Failed to start machine: \(error)")
            lastErrorMessage = error.localizedDescription
            NotificationService.shared.notifyActionFailed(
                action: "Start", target: machineId, message: error.localizedDescription
            )
        }
        updatingMachineIDs.remove(machineId)
    }

    func stopMachine(machineId: String) async {
        updatingMachineIDs.insert(machineId)
        do {
            _ = try await runCommand(["machine", "stop", machineId])
            await refreshMachines()
        } catch {
            logger.error("Failed to stop machine: \(error)")
            lastErrorMessage = error.localizedDescription
            NotificationService.shared.notifyActionFailed(
                action: "Stop", target: machineId, message: error.localizedDescription
            )
        }
        updatingMachineIDs.remove(machineId)
    }

    func deleteMachine(machineId: String) async {
        guard !machineId.isEmpty else {
            lastErrorMessage = "Cannot delete: machine id is empty."
            return
        }
        updatingMachineIDs.insert(machineId)
        do {
            _ = try await runCommand(["machine", "delete", machineId])
            await refreshMachines()
        } catch {
            logger.error("Failed to delete machine: \(error)")
            lastErrorMessage = error.localizedDescription
        }
        updatingMachineIDs.remove(machineId)
    }

    /// Applies configuration changes (cpus / memory / home-mount). Each takes
    /// effect after the machine is restarted.
    func setMachineConfig(machineId: String, cpus: String?, memory: String?, homeMount: String?) async -> Bool {
        var settings: [String] = []
        if let cpus = cpus?.trimmingCharacters(in: .whitespacesAndNewlines), !cpus.isEmpty {
            settings.append("cpus=\(cpus)")
        }
        if let memory = memory?.trimmingCharacters(in: .whitespacesAndNewlines), !memory.isEmpty {
            settings.append("memory=\(memory)")
        }
        if let homeMount = homeMount?.trimmingCharacters(in: .whitespacesAndNewlines), !homeMount.isEmpty {
            settings.append("home-mount=\(homeMount)")
        }
        guard !settings.isEmpty else { return false }

        updatingMachineIDs.insert(machineId)
        defer { updatingMachineIDs.remove(machineId) }
        do {
            _ = try await runCommand(["machine", "set", "-n", machineId] + settings)
            await refreshMachines()
            return true
        } catch {
            logger.error("Failed to set machine config: \(error)")
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    /// Creates (and optionally boots) a machine. Returns the machine name on
    /// success so the caller can navigate to it.
    @discardableResult
    func createMachine(
        image: String,
        name: String?,
        cpus: String?,
        memory: String?,
        homeMount: String?,
        setDefault: Bool,
        boot: Bool
    ) async -> String? {
        let trimmedImage = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else {
            lastErrorMessage = "Image is required."
            return nil
        }

        var args: [String] = ["machine", "create"]
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty { args += ["--name", trimmedName] }
        if let cpus = cpus?.trimmingCharacters(in: .whitespacesAndNewlines), !cpus.isEmpty {
            args += ["--cpus", cpus]
        }
        if let memory = memory?.trimmingCharacters(in: .whitespacesAndNewlines), !memory.isEmpty {
            args += ["--memory", memory]
        }
        if let homeMount = homeMount?.trimmingCharacters(in: .whitespacesAndNewlines), !homeMount.isEmpty {
            args += ["--home-mount", homeMount]
        }
        if setDefault { args.append("--set-default") }
        if !boot { args.append("--no-boot") }
        args.append(trimmedImage)

        do {
            let output = try await runCommand(args)
            await refreshMachines()
            let reported = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }
            return reported.isEmpty ? nil : reported
        } catch {
            logger.error("Failed to create machine: \(error)")
            lastErrorMessage = error.localizedDescription
            if Self.isRegistryAuthError(error.localizedDescription) {
                registryAuthState = .notAuthenticated
            }
            return nil
        }
    }

    func machineLogs(machineId: String) async -> String? {
        do {
            return try await runCommand(["machine", "logs", machineId])
        } catch {
            logger.error("Failed to fetch machine logs: \(error)")
            return nil
        }
    }
}

private extension ContainerizationWrapper {
    // Parsing of CLI output is delegated to `CLIParsers` so it can be
    // covered by unit tests. Keep these helpers as the integration point
    // between the (async, MainActor) wrapper and the (pure) parser layer.

    func parseImageList(_ output: String) -> [ContainerImage] {
        CLIParsers.parseImageList(output)
    }

    static func parseRegistryHosts(_ output: String) -> [String] {
        CLIParsers.parseRegistryHosts(output)
    }

    static func parseEditableSettings(_ raw: String) -> ContainerEditableSettings? {
        CLIParsers.parseEditableSettings(raw)
    }

    static func normalizedContainerName(_ raw: String) -> String {
        CLIParsers.normalizedContainerName(raw)
    }
}

enum DependencyError: Error, Identifiable {
    case cliMissing
    
    var id: String {
        switch self {
        case .cliMissing: return "cliMissing"
        }
    }
    
    var description: String {
        switch self {
        case .cliMissing:
            return "CLI tool 'container' not found. Install Apple container with Homebrew or set a custom CLI path in Settings."
        }
    }
}


// MARK: - Support struct for CLI JSON parsing
struct ContainerCLI {
    let status: String?
    let configuration: Configuration?
    let networks: [Network]?

    struct Configuration: Decodable {
        let id: String?
        let hostname: String?
        let image: Image?
    }
    struct Image: Decodable {
        let reference: String?
    }
    struct Network: Decodable {
        let address: String?
        let ipv4Address: String?

        /// Preferred display address: container CLI ≤ 0.x exposes
        /// `address`, ≥ 1.0 exposes `ipv4Address` in CIDR form
        /// (`192.168.64.2/24`) — the prefix length is stripped.
        var resolvedAddress: String? {
            let raw = ipv4Address ?? address
            return raw?.split(separator: "/").first.map(String.init)
        }
    }
}

extension ContainerCLI: Decodable {
    private enum CodingKeys: String, CodingKey {
        case status, configuration, networks
    }

    /// container CLI ≥ 1.0 moved `status` from a plain string to an
    /// object (`{state, networks, startedDate}`) and dropped the
    /// top-level `networks` array; both shapes are accepted here.
    private struct StatusObject: Decodable {
        let state: String?
        let networks: [Network]?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configuration = try container.decodeIfPresent(Configuration.self, forKey: .configuration)
        let legacyNetworks = try? container.decodeIfPresent([Network].self, forKey: .networks)
        if let legacyStatus = try? container.decodeIfPresent(String.self, forKey: .status) {
            status = legacyStatus
            networks = legacyNetworks
        } else {
            let statusObject = try? container.decodeIfPresent(StatusObject.self, forKey: .status)
            status = statusObject?.state
            networks = legacyNetworks ?? statusObject?.networks
        }
    }
}

struct ContainerEditableSettings: Equatable {
    var image: String
    var name: String
    var ports: [String]
    var volumes: [String]
    var environment: [String]
}

struct ContainerDetails: Equatable {
    let status: String?
    let networks: [NetworkInfo]?
    let configuration: ConfigurationData?

    struct NetworkInfo: Decodable, Equatable {
        let address: String?
    }

    struct ConfigurationData: Decodable, Equatable {
        let id: String?
        let hostname: String?
        let image: ImageInfo?
        let mounts: [MountInfo]?
        let initProcess: ProcessInfo?
        let publishedSockets: [SocketInfo]?
    }

    struct ImageInfo: Decodable, Equatable {
        let reference: String?
    }

    struct MountInfo: Decodable, Hashable, Equatable {
        let source: String?
        let destination: String?
    }
    
    struct ProcessInfo: Decodable, Equatable {
        let executable: String?
        let arguments: [String]?
        let environment: [String]?
    }
    
    struct SocketInfo: Decodable, Hashable, Equatable {
        let hostPort: Int?
        let containerPort: Int?
        let proto: String?
    }
    
    // Computed properties for easier view consumption
    var name: String { configuration?.hostname ?? configuration?.id ?? "Unknown" }
    var command: String {
        guard let proc = configuration?.initProcess else { return "-" }
        let exec = proc.executable ?? ""
        let args = proc.arguments ?? []
        return ([exec] + args).joined(separator: " ")
    }
    var portBindings: [String] {
        configuration?.publishedSockets?.compactMap { socket in
            guard let host = socket.hostPort, let container = socket.containerPort, let proto = socket.proto else { return nil }
            return "\(host):\(container)/\(proto)"
        } ?? []
    }
}

extension ContainerDetails: Decodable {
    private enum CodingKeys: String, CodingKey {
        case status, networks, configuration
    }

    /// Accepts both inspect output shapes: container CLI ≤ 0.x uses a
    /// plain `status` string plus a top-level `networks` array with an
    /// `address` field; CLI ≥ 1.0 nests `{state, networks}` inside
    /// `status`, with addresses under `ipv4Address` in CIDR form.
    private struct StatusObject: Decodable {
        let state: String?
        let networks: [RuntimeNetwork]?
    }

    private struct RuntimeNetwork: Decodable {
        let address: String?
        let ipv4Address: String?

        var normalizedAddress: String? {
            let raw = ipv4Address ?? address
            return raw?.split(separator: "/").first.map(String.init)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configuration = try container.decodeIfPresent(ConfigurationData.self, forKey: .configuration)
        let legacyNetworks = try? container.decodeIfPresent([NetworkInfo].self, forKey: .networks)
        if let legacyStatus = try? container.decodeIfPresent(String.self, forKey: .status) {
            status = legacyStatus
            networks = legacyNetworks
        } else {
            let statusObject = try? container.decodeIfPresent(StatusObject.self, forKey: .status)
            status = statusObject?.state
            networks = legacyNetworks ?? statusObject?.networks?.map {
                NetworkInfo(address: $0.normalizedAddress)
            }
        }
    }
}
