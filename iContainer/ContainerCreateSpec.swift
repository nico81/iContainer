import Foundation

/// Everything `container create` needs, expressed as data.
///
/// Three producers feed this: the create sheet (image/name/ports/volumes/
/// env typed by the user), `ComposeParser` (one spec per service), and
/// `DockerParsers.translate` (a Docker container's inspect output). One
/// consumer turns it into CLI flags — `ContainerCLIArguments.create` — so
/// the flag vocabulary lives in exactly one place and is unit-tested.
nonisolated struct ContainerCreateSpec: Equatable, Sendable {
    var image: String
    var name: String? = nil
    /// `[host-ip:]host-port:container-port[/proto]`
    var publishedPorts: [String] = []
    /// Bind mounts `host-path:container-path[:ro]` or named volumes
    /// `volume-name:container-path` (the `container` CLI resolves a
    /// non-path source as a volume name).
    var volumes: [String] = []
    /// `KEY=value`
    var environment: [String] = []
    /// Trailing init-process arguments (after the image).
    var command: [String] = []
    var entrypoint: String? = nil
    var workingDirectory: String? = nil
    /// `name|uid[:gid]`
    var user: String? = nil
    /// Whole CPUs — the CLI rejects fractional values.
    var cpus: Int? = nil
    var memoryBytes: Int64? = nil
    /// `key=value`
    var labels: [String] = []
    var network: String? = nil
    /// Search domains written to the container's resolv.conf (`--dns-search`).
    /// Set to the service's DNS domain so a bare container name resolves as
    /// `<name>.<domain>` even on CLI versions that don't add the domain to
    /// resolv.conf themselves (1.3.1 does; older docs say user networks
    /// only answer the qualified form).
    var dnsSearchDomains: [String] = []
    var capabilitiesToAdd: [String] = []
    var capabilitiesToDrop: [String] = []
    var tmpfsPaths: [String] = []
    var readOnlyRootFilesystem = false

    var trimmedImage: String { image.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Pure `ContainerCreateSpec` → `container create …` argument builder.
nonisolated enum ContainerCLIArguments {

    /// Flags are emitted in a fixed order (name, network, labels, env,
    /// ports, volumes, process options, resources, capabilities, tmpfs,
    /// read-only, image, command) so the result is deterministic and easy
    /// to assert on. Blank entries are dropped, everything is trimmed.
    static func create(_ spec: ContainerCreateSpec) -> [String] {
        var args: [String] = ["create"]
        if let name = clean(spec.name) { args += ["--name", name] }
        if let network = clean(spec.network) { args += ["--network", network] }
        for domain in spec.dnsSearchDomains.compactMap(clean) { args += ["--dns-search", domain] }
        for label in spec.labels.compactMap(clean) { args += ["--label", label] }
        for env in spec.environment.compactMap(clean) { args += ["-e", env] }
        for port in spec.publishedPorts.compactMap(clean) { args += ["-p", port] }
        for volume in spec.volumes.compactMap(clean) { args += ["-v", volume] }
        if let workdir = clean(spec.workingDirectory) { args += ["-w", workdir] }
        if let user = clean(spec.user) { args += ["-u", user] }
        if let entrypoint = clean(spec.entrypoint) { args += ["--entrypoint", entrypoint] }
        if let cpus = spec.cpus, cpus > 0 { args += ["--cpus", String(cpus)] }
        if let memory = spec.memoryBytes, memory > 0 { args += ["--memory", String(memory)] }
        for cap in spec.capabilitiesToAdd.compactMap(clean) { args += ["--cap-add", cap] }
        for cap in spec.capabilitiesToDrop.compactMap(clean) { args += ["--cap-drop", cap] }
        for path in spec.tmpfsPaths.compactMap(clean) { args += ["--tmpfs", path] }
        if spec.readOnlyRootFilesystem { args.append("--read-only") }
        args.append(spec.trimmedImage)
        args += spec.command
        return args
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
