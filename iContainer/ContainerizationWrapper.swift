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
    @Published var updatingContainerIDs: Set<String> = []
    @Published var missingDependencies: [DependencyError] = []
    @Published var images: [ContainerImage] = []
    @Published var updatingImageIDs: Set<String> = []
    @Published var lastErrorMessage: String?
    @Published var registryAuthState: RegistryAuthState = .unknown
    private let logger = Logger(label: "iContainer")
    private var timer: Timer?

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
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshContainers()
                await self?.refreshImages()
                await self?.refreshRegistryAuthStatus()
            }
        }
        Task {
            await refreshContainers()
            await refreshImages()
            await refreshRegistryAuthStatus()
        }
    }

    deinit {
        timer?.invalidate()
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

    nonisolated private static func runCommandBlocking(_ arguments: [String], standardInput: String? = nil) throws -> (output: String, status: Int32) {
        guard let cliPath = resolveCLIPath() else {
            throw NSError(domain: "iContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "CLI 'container' non trovata"])
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
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "iContainer", code: 2, userInfo: [NSLocalizedDescriptionKey: "Impossibile leggere output comando"])
        }
        return (output, process.terminationStatus)
    }

    nonisolated private static func resolveCLIPath() -> String? {
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

    // MARK: - Container Management
    func refreshContainers() async {
        do {
            let output = try await runCommand(["list", "--all", "--format", "json"])
            if let data = output.data(using: .utf8) {
                let decoded = try JSONDecoder().decode([ContainerCLI].self, from: data)
                let newContainers = decoded.map { cli in
                    Container(
                        id: cli.configuration?.id ?? "",
                        name: cli.configuration?.hostname ?? cli.configuration?.id ?? "",
                        status: cli.status == "running" ? .running : .stopped,
                        image: cli.configuration?.image?.reference,
                        ipAddress: cli.networks?.first?.address
                    )
                }
                .sorted { lhs, rhs in
                    let lhsPriority = lhs.status == .running ? 0 : 1
                    let rhsPriority = rhs.status == .running ? 0 : 1
                    if lhsPriority != rhsPriority {
                        return lhsPriority < rhsPriority
                    }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                
                // Update only if the containers list has changed
                if self.containers != newContainers {
                    self.containers = newContainers
                }
            }
        } catch {
            logger.error("Errore nel refresh dei container: \(error)")
            self.containers = []
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
            logger.error("Errore nel refresh delle immagini: \(error)")
        }
    }

    func pullImage(reference: String) async {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updatingImageIDs.insert(trimmed)
        defer { updatingImageIDs.remove(trimmed) }
        do {
            _ = try await runCommand(["image", "pull", trimmed])
            await refreshImages()
            await refreshRegistryAuthStatus()
        } catch {
            logger.error("Errore nel pull dell'immagine: \(error)")
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
            logger.error("Errore nell'eliminazione dell'immagine: \(error)")
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
            logger.error("Errore nell'ispezione dell'immagine: \(error)")
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func startContainer(containerId: String) async {
        updatingContainerIDs.insert(containerId)
        do {
            _ = try await runCommand(["start", containerId])
            await refreshContainers()
        } catch {
            logger.error("Errore nell'avvio del container: \(error)")
        }
        updatingContainerIDs.remove(containerId)
    }

    func stopContainer(containerId: String) async {
        updatingContainerIDs.insert(containerId)
        do {
            _ = try await runCommand(["stop", containerId])
            await refreshContainers()
        } catch {
            logger.error("Errore nello stop del container: \(error)")
        }
        updatingContainerIDs.remove(containerId)
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
            logger.error("Errore nell'eliminazione del container: \(error)")
            do {
                _ = try await runCommand(["delete", "--force", containerId])
                await refreshContainers()
                return
            } catch {
                logger.error("Errore nell'eliminazione forzata del container: \(error)")
                do {
                    _ = try await runCommand(["rm", containerId])
                    await refreshContainers()
                    return
                } catch {
                    logger.error("Errore nell'eliminazione con rm: \(error)")
                    lastErrorMessage = error.localizedDescription
                }
            }
        }
    }

    func createContainer(
        image: String,
        name: String?,
        publishedPorts: [String] = [],
        volumes: [String] = [],
        environment: [String] = []
    ) async {
        let trimmedImage = image.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedImage.isEmpty else {
            lastErrorMessage = "Image is required."
            return
        }

        var args: [String] = ["create"]

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
            _ = try await runCommand(args)
            await refreshContainers()
            await refreshRegistryAuthStatus()
        } catch {
            logger.error("Errore nella creazione del container: \(error)")
            lastErrorMessage = error.localizedDescription
            if Self.isRegistryAuthError(error.localizedDescription) {
                registryAuthState = .notAuthenticated
            }
        }
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
            lastErrorMessage = "Host, username e password sono obbligatori."
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

    static func isRegistryAuthError(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("401 unauthorized")
            || lower.contains("unauthorized")
            || lower.contains("authentication required")
            || lower.contains("no credentials found for host")
            || lower.contains("insufficient_scope")
            || lower.contains("denied")
    }

    static func looksLikeTopLevelHelp(_ output: String) -> Bool {
        let lower = output.lowercased()
        return lower.contains("overview: a container platform for macos")
            && lower.contains("container subcommands:")
            && lower.contains("image subcommands:")
    }

    static func registryLoginHosts(for host: String) -> [String] {
        let normalized = host.lowercased()
        if normalized == "registry-1.docker.io" || normalized == "docker.io" || normalized == "index.docker.io" {
            return ["registry-1.docker.io", "docker.io", "index.docker.io"]
        }
        return [host]
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
            logger.error("Errore nell'ispezione del container: \(error)")
        }
        return nil
    }

    func inspectContainerRaw(containerId: String) async -> String? {
        do {
            return try await runCommand(["inspect", containerId])
        } catch {
            logger.error("Errore nell'ispezione raw del container: \(error)")
            return nil
        }
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
                logger.error("Errore nell'esecuzione comando nel container: \(error)")
                lastErrorMessage = error.localizedDescription
                return nil
            }
        }
    }
}

private extension ContainerizationWrapper {
    func parseImageList(_ output: String) -> [ContainerImage] {
        guard let data = output.data(using: .utf8) else { return [] }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let array = json as? [[String: Any]] else { return [] }
            return array.compactMap { mapImage($0) }
        } catch {
            logger.error("Errore nel parsing immagini: \(error)")
            return []
        }
    }

    func mapImage(_ dict: [String: Any]) -> ContainerImage? {
        let reference = stringValue(dict, keys: ["reference", "ref"]) ?? ""
        let (name, tag) = splitReference(reference)
        let descriptor = dict["descriptor"] as? [String: Any]
        let digest = descriptor?["digest"] as? String
        let sizeBytes = intValue(descriptor ?? [:], keys: ["size"])
        let sizeText = stringValue(dict, keys: ["fullSize", "full_size"])
        let annotations = descriptor?["annotations"] as? [String: Any]
        let createdAt = stringValue(annotations ?? [:], keys: ["org.opencontainers.image.created"])
        let resolvedId = digest ?? reference
        guard !resolvedId.isEmpty else { return nil }
        return ContainerImage(
            id: resolvedId,
            name: name.isEmpty ? reference : name,
            tag: tag,
            sizeBytes: sizeBytes,
            sizeText: sizeText,
            createdAt: createdAt
        )
    }

    func splitReference(_ reference: String) -> (name: String, tag: String?) {
        guard !reference.isEmpty else { return ("", nil) }
        let parts = reference.split(separator: ":")
        if parts.count >= 2, let last = parts.last {
            let name = parts.dropLast().joined(separator: ":")
            return (name, String(last))
        }
        return (reference, nil)
    }

    func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
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

    func intValue(_ dict: [String: Any], keys: [String]) -> Int64? {
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

    static func parseRegistryHosts(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { line in
                line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(whereSeparator: \.isWhitespace)
                    .first
                    .map(String.init) ?? ""
            }
            .filter { !$0.isEmpty && !$0.lowercased().contains("host") && !$0.lowercased().contains("registry") }
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
            return "CLI tool 'container' not found at /usr/local/bin/container."
        }
    }
}


// MARK: - Support struct for CLI JSON parsing
struct ContainerCLI: Decodable {
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
    }
}

struct ContainerDetails: Decodable, Equatable {
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
