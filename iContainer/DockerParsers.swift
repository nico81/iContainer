import Foundation

// MARK: - Models

/// One row of `docker images --format json`. The same image ID appears once
/// per tag, so `id` combines both to stay unique in a `ForEach`.
nonisolated struct DockerImage: Identifiable, Equatable, Sendable {
    let imageID: String
    let repository: String
    /// `nil` for dangling images (`<none>`).
    let tag: String?
    let sizeText: String
    let createdAt: String?
    let createdSince: String?

    var id: String { "\(imageID)|\(repository)|\(tag ?? "")" }

    /// `repository:tag`, or `nil` when the image has no usable name — those
    /// can't be exported by reference and are skipped by the import flow.
    var reference: String? {
        guard repository != "<none>", !repository.isEmpty, let tag, tag != "<none>", !tag.isEmpty else {
            return nil
        }
        return "\(repository):\(tag)"
    }
}

/// One row of `docker ps -a --format json`. `Mounts`/`Labels` in that
/// output are truncated, so anything beyond identity comes from `inspect`.
nonisolated struct DockerContainer: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let image: String
    /// `running`, `exited`, `created`, `paused`, …
    let state: String
    let status: String
    let createdAt: String?
    /// `os/arch` when the CLI reports it (Docker ≥ 27).
    let platform: String?

    var isRunning: Bool { state == "running" }
}

/// The subset of `docker inspect <container>` the clone flow reads.
nonisolated struct DockerContainerInspect: Equatable, Sendable {
    struct PortBinding: Equatable, Sendable {
        let containerPort: String   // "3000/tcp"
        let hostIP: String
        let hostPort: String        // may be "" when Docker picked a random port
    }
    struct Mount: Equatable, Sendable {
        let type: String            // bind | volume | tmpfs
        let name: String?
        let source: String?
        let destination: String
        let readWrite: Bool
    }

    let id: String
    let name: String
    let state: String?
    let imageReference: String?
    let imageID: String?
    let environment: [String]
    let command: [String]
    let entrypoint: [String]
    let workingDirectory: String?
    let user: String?
    let portBindings: [PortBinding]
    let mounts: [Mount]
    let memoryBytes: Int64
    let nanoCPUs: Int64
    let restartPolicy: String?
    let networkMode: String?
    let networks: [String]
    let capabilitiesToAdd: [String]
    let capabilitiesToDrop: [String]
    let privileged: Bool
    let readOnlyRootFilesystem: Bool
    let tmpfs: [String]
    let hasHealthcheck: Bool
    let deviceCount: Int
    let extraHosts: [String]
    let links: [String]
    let hasDeviceRequests: Bool
}

/// Result of translating a Docker container into a `container create` spec.
/// `warnings` lists everything that was dropped or approximated so the UI
/// can show it before the user confirms.
nonisolated struct DockerTranslation: Equatable, Sendable {
    var spec: ContainerCreateSpec
    var warnings: [String]
    /// Named volumes referenced by `spec.volumes` that must exist in the
    /// Apple store before `create` (data is not migrated).
    var volumesToCreate: [String]
    /// User-defined Docker network to recreate so cloned containers keep
    /// resolving each other by name.
    var networkToCreate: String?
}

// MARK: - Parsers

/// Pure parsers for the Docker CLI's JSON output plus the Docker → Apple
/// `container` translation rules. Deterministic and side-effect free (same
/// contract as `CLIParsers` / `ComposeParser`), so exhaustively testable
/// against captured fixtures.
nonisolated enum DockerParsers {

    /// Networks Docker treats as built-in — these have no user-defined
    /// counterpart to recreate.
    static let builtinNetworkModes: Set<String> = ["", "default", "bridge", "host", "none"]

    /// Docker Desktop stamps its own bookkeeping labels; never copy them.
    static let dockerDesktopLabelPrefix = "desktop.docker.io/"

    // MARK: docker images

    /// `docker images --format json` prints one JSON object per line.
    static func parseImageList(_ output: String) -> [DockerImage] {
        ndjsonObjects(output).compactMap { dict in
            guard let imageID = string(dict["ID"]), !imageID.isEmpty else { return nil }
            let repository = string(dict["Repository"]) ?? "<none>"
            let rawTag = string(dict["Tag"])
            return DockerImage(
                imageID: imageID,
                repository: repository,
                tag: (rawTag == nil || rawTag == "<none>" || rawTag == "") ? nil : rawTag,
                sizeText: string(dict["Size"]) ?? "-",
                createdAt: string(dict["CreatedAt"]),
                createdSince: string(dict["CreatedSince"])
            )
        }
    }

    // MARK: docker ps

    /// `docker ps -a --format json` prints one JSON object per line.
    static func parseContainerList(_ output: String) -> [DockerContainer] {
        ndjsonObjects(output).compactMap { dict in
            guard let id = string(dict["ID"]), !id.isEmpty else { return nil }
            var platform: String?
            if let platformDict = dict["Platform"] as? [String: Any],
               let os = string(platformDict["os"]), let arch = string(platformDict["architecture"]) {
                platform = "\(os)/\(arch)"
            }
            return DockerContainer(
                id: id,
                name: (string(dict["Names"]) ?? id).split(separator: ",").first.map(String.init) ?? id,
                image: string(dict["Image"]) ?? "",
                state: string(dict["State"]) ?? "",
                status: string(dict["Status"]) ?? "",
                createdAt: string(dict["CreatedAt"]),
                platform: platform
            )
        }
    }

    // MARK: docker inspect

    /// `docker inspect <id>` returns a one-element array. Returns `nil` on
    /// malformed input.
    static func parseContainerInspect(_ output: String) -> DockerContainerInspect? {
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        let root: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            root = first
        } else if let object = json as? [String: Any] {
            root = object
        } else {
            return nil
        }
        guard let id = string(root["Id"]) ?? string(root["ID"]), !id.isEmpty else { return nil }

        let config = root["Config"] as? [String: Any] ?? [:]
        let host = root["HostConfig"] as? [String: Any] ?? [:]
        let state = root["State"] as? [String: Any] ?? [:]
        let networkSettings = root["NetworkSettings"] as? [String: Any] ?? [:]

        var bindings: [DockerContainerInspect.PortBinding] = []
        if let portBindings = host["PortBindings"] as? [String: Any] {
            for key in portBindings.keys.sorted() {
                guard let list = portBindings[key] as? [[String: Any]] else { continue }
                for entry in list {
                    bindings.append(.init(
                        containerPort: key,
                        hostIP: string(entry["HostIp"]) ?? "",
                        hostPort: string(entry["HostPort"]) ?? ""
                    ))
                }
            }
        }

        let mounts: [DockerContainerInspect.Mount] = (root["Mounts"] as? [[String: Any]] ?? []).compactMap { mount in
            guard let destination = string(mount["Destination"]), !destination.isEmpty else { return nil }
            return .init(
                type: string(mount["Type"]) ?? "bind",
                name: string(mount["Name"]),
                source: string(mount["Source"]),
                destination: destination,
                readWrite: (mount["RW"] as? Bool) ?? true
            )
        }

        let restart = (host["RestartPolicy"] as? [String: Any]).flatMap { string($0["Name"]) }
        let networks = ((networkSettings["Networks"] as? [String: Any])?.keys).map { Array($0).sorted() } ?? []
        let tmpfs = ((host["Tmpfs"] as? [String: Any])?.keys).map { Array($0).sorted() } ?? []

        var rawName = string(root["Name"]) ?? id
        if rawName.hasPrefix("/") { rawName.removeFirst() }

        return DockerContainerInspect(
            id: id,
            name: rawName,
            state: string(state["Status"]),
            imageReference: string(config["Image"]),
            imageID: string(root["Image"]),
            environment: stringArray(config["Env"]),
            command: stringArray(config["Cmd"]),
            entrypoint: stringArray(config["Entrypoint"]),
            workingDirectory: nonEmpty(string(config["WorkingDir"])),
            user: nonEmpty(string(config["User"])),
            portBindings: bindings,
            mounts: mounts,
            memoryBytes: int64(host["Memory"]) ?? 0,
            nanoCPUs: int64(host["NanoCpus"]) ?? 0,
            restartPolicy: restart,
            networkMode: string(host["NetworkMode"]),
            networks: networks,
            capabilitiesToAdd: stringArray(host["CapAdd"]),
            capabilitiesToDrop: stringArray(host["CapDrop"]),
            privileged: (host["Privileged"] as? Bool) ?? false,
            readOnlyRootFilesystem: (host["ReadonlyRootfs"] as? Bool) ?? false,
            tmpfs: tmpfs,
            // JSON `null` arrives as NSNull (non-nil), so test for an actual object.
            hasHealthcheck: (config["Healthcheck"] as? [String: Any]) != nil,
            deviceCount: (host["Devices"] as? [Any])?.count ?? 0,
            extraHosts: stringArray(host["ExtraHosts"]),
            links: stringArray(host["Links"]),
            hasDeviceRequests: !((host["DeviceRequests"] as? [Any]) ?? []).isEmpty
        )
    }

    /// `docker image inspect --format '{{json .Config.Env}}'` → the env baked
    /// into the image, used to subtract image defaults from a container's
    /// effective env so the clone only carries what the user actually set.
    static func parseEnvironmentArray(_ output: String) -> [String] {
        guard let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return [] }
        return (json as? [String]) ?? []
    }

    // MARK: container image load

    /// `container image load` prints one loaded reference per line plus
    /// `untagged@sha256:…` for unnamed manifests (attestations); only the
    /// named ones are returned.
    static func parseLoadedReferences(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("untagged@") && !$0.lowercased().hasPrefix("error") }
    }

    // MARK: Reference normalisation

    /// Canonical short form used to compare a Docker reference with what
    /// `container image list` shows: drops the implicit Docker Hub prefixes
    /// (`docker.io/`, `docker.io/library/`, `index.docker.io/`) and adds the
    /// implicit `:latest` tag. Digest references are returned trimmed only.
    static func normalizedReference(_ reference: String) -> String {
        var ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["index.docker.io/library/", "docker.io/library/", "index.docker.io/", "docker.io/", "library/"] {
            if ref.hasPrefix(prefix) {
                ref.removeFirst(prefix.count)
                break
            }
        }
        if ref.contains("@") { return ref }
        let lastSlash = ref.lastIndex(of: "/")
        let tagSearchStart = lastSlash.map { ref.index(after: $0) } ?? ref.startIndex
        if ref[tagSearchStart...].contains(":") { return ref }
        return ref + ":latest"
    }

    // MARK: Translation

    /// Turns a Docker container's inspect output into a `ContainerCreateSpec`
    /// for Apple's `container` CLI, listing every approximation in
    /// `warnings`.
    ///
    /// - Parameter imageEnvironment: the image's own `Config.Env`; entries
    ///   that match exactly are dropped from the spec so only user-set
    ///   variables are carried over. Pass `[]` to keep everything.
    /// - Parameter imageOverride: reference to use instead of the container's
    ///   `Config.Image` (e.g. after importing the image under a fully
    ///   qualified name).
    static func translate(
        _ inspect: DockerContainerInspect,
        imageEnvironment: [String] = [],
        imageOverride: String? = nil
    ) -> DockerTranslation {
        var warnings: [String] = []
        var volumesToCreate: [String] = []

        // Ports: PortBindings only (ExposedPorts without a binding aren't
        // published in Docker either).
        var ports: [String] = []
        for binding in inspect.portBindings {
            let parts = binding.containerPort.split(separator: "/", maxSplits: 1)
            let containerPort = String(parts.first ?? Substring(binding.containerPort))
            let proto = parts.count > 1 ? "/\(parts[1])" : ""
            var hostPort = binding.hostPort
            if hostPort.isEmpty {
                hostPort = containerPort
                warnings.append("Port \(binding.containerPort) was published to a random host port in Docker; mapped to \(containerPort):\(containerPort) instead.")
            }
            let hostPrefix = (binding.hostIP.isEmpty || binding.hostIP == "0.0.0.0" || binding.hostIP == "::") ? "" : "\(binding.hostIP):"
            ports.append("\(hostPrefix)\(hostPort):\(containerPort)\(proto)")
        }

        // Mounts.
        var volumes: [String] = []
        for mount in inspect.mounts {
            switch mount.type {
            case "bind":
                guard let source = mount.source, !source.isEmpty else {
                    warnings.append("Bind mount to \(mount.destination) has no host path and was skipped.")
                    continue
                }
                volumes.append("\(source):\(mount.destination)\(mount.readWrite ? "" : ":ro")")
            case "volume":
                let name = mount.name ?? mount.source ?? ""
                guard !name.isEmpty else {
                    warnings.append("Anonymous volume at \(mount.destination) was skipped.")
                    continue
                }
                volumes.append("\(name):\(mount.destination)")
                volumesToCreate.append(name)
                warnings.append("Named volume '\(name)' will be created empty in Apple Container — its Docker data is not migrated.")
            case "tmpfs":
                // handled via HostConfig.Tmpfs below
                continue
            default:
                warnings.append("Mount of type '\(mount.type)' at \(mount.destination) isn't supported and was skipped.")
            }
        }

        // Environment: drop the image's baked-in defaults.
        let imageEnv = Set(imageEnvironment)
        let environment = inspect.environment.filter { !imageEnv.contains($0) }

        // Entrypoint/command: Docker concatenates Entrypoint + Cmd; the
        // `container` CLI takes a single --entrypoint string plus trailing
        // arguments, so the entrypoint's extra elements move to the front
        // of the command.
        var entrypoint: String?
        var command = inspect.command
        if let first = inspect.entrypoint.first {
            entrypoint = first
            command = Array(inspect.entrypoint.dropFirst()) + inspect.command
        }

        // Resources.
        var cpus: Int?
        if inspect.nanoCPUs > 0 {
            let whole = Int((Double(inspect.nanoCPUs) / 1_000_000_000).rounded(.up))
            cpus = max(1, whole)
            if Double(inspect.nanoCPUs).truncatingRemainder(dividingBy: 1_000_000_000) != 0 {
                warnings.append("CPU limit \(String(format: "%.2f", Double(inspect.nanoCPUs) / 1e9)) rounded up to \(cpus!) — the container CLI only accepts whole CPUs.")
            }
        }

        // Network.
        var network: String?
        var networkToCreate: String?
        let userNetworks = inspect.networks.filter { !builtinNetworkModes.contains($0) }
        if let mode = inspect.networkMode {
            switch mode {
            case "host":
                warnings.append("Host networking isn't supported by the container CLI; the container will join the default network.")
            case "none":
                warnings.append("Network mode 'none' isn't supported; the container will join the default network.")
            case let m where m.hasPrefix("container:"):
                warnings.append("Sharing another container's network stack (\(m)) isn't supported; the container will join the default network.")
            default:
                break
            }
        }
        if let primary = userNetworks.first {
            network = primary
            networkToCreate = primary
            if userNetworks.count > 1 {
                warnings.append("Container was attached to \(userNetworks.count) Docker networks; only '\(primary)' is recreated (\(userNetworks.dropFirst().joined(separator: ", ")) dropped).")
            }
        }

        // Unsupported bits worth telling the user about.
        if let restart = inspect.restartPolicy, !["", "no"].contains(restart) {
            warnings.append("Restart policy '\(restart)' isn't supported — the container won't restart automatically.")
        }
        if inspect.privileged {
            warnings.append("Privileged mode isn't supported and was dropped.")
        }
        if inspect.hasHealthcheck {
            warnings.append("The healthcheck isn't supported and was dropped.")
        }
        if inspect.deviceCount > 0 {
            warnings.append("\(inspect.deviceCount) device mapping(s) aren't supported and were dropped.")
        }
        if inspect.hasDeviceRequests {
            warnings.append("GPU/device requests aren't supported and were dropped.")
        }
        if !inspect.extraHosts.isEmpty {
            warnings.append("extra_hosts (\(inspect.extraHosts.joined(separator: ", "))) aren't supported and were dropped.")
        }
        if !inspect.links.isEmpty {
            warnings.append("Legacy links (\(inspect.links.joined(separator: ", "))) aren't supported; use the shared network and container names instead.")
        }

        let spec = ContainerCreateSpec(
            image: imageOverride ?? inspect.imageReference ?? "",
            name: inspect.name,
            publishedPorts: ports,
            volumes: volumes,
            environment: environment,
            command: command,
            entrypoint: entrypoint,
            workingDirectory: inspect.workingDirectory,
            user: inspect.user,
            cpus: cpus,
            memoryBytes: inspect.memoryBytes > 0 ? inspect.memoryBytes : nil,
            labels: ["com.icontainer.source=docker:\(String(inspect.id.prefix(12)))"],
            network: network,
            capabilitiesToAdd: inspect.capabilitiesToAdd,
            capabilitiesToDrop: inspect.capabilitiesToDrop,
            tmpfsPaths: inspect.tmpfs,
            readOnlyRootFilesystem: inspect.readOnlyRootFilesystem
        )

        return DockerTranslation(
            spec: spec,
            warnings: warnings,
            volumesToCreate: volumesToCreate,
            networkToCreate: networkToCreate
        )
    }

    // MARK: - Helpers

    /// Splits NDJSON (one object per line) into dictionaries; blank or
    /// non-object lines are ignored.
    private static func ndjsonObjects(_ output: String) -> [[String: Any]] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
            }
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func stringArray(_ value: Any?) -> [String] {
        (value as? [String]) ?? []
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }
}
