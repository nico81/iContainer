import SwiftUI

/// The "From Docker Container" source of the create sheet: pick one of the
/// local Docker containers, show what its configuration translates to for
/// Apple's `container` CLI, and list every approximation. The actual
/// prefill of the editable fields (name, ports, volumes, env, image) is done
/// by the owner through `onSelect`.
struct DockerContainerPickerView: View {
    @EnvironmentObject var dockerManager: DockerWrapper
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @Binding var selectedContainerID: String?
    let translation: DockerTranslation?
    let isLoading: Bool
    let loadError: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch dockerManager.availability {
            case .unknown:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Checking Docker…").foregroundColor(.secondary)
                }
            case .notInstalled:
                unavailable("Docker CLI not found", "Install Docker Desktop, or set the path to the `docker` binary in Settings → Advanced.", showOpen: false)
            case .daemonUnavailable(let message):
                unavailable("Docker isn't running", message, showOpen: DockerWrapper.isDockerDesktopInstalled)
            case .available:
                picker
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Reading container configuration…").font(.caption).foregroundColor(.secondary)
                    }
                }
                if let loadError {
                    Text(loadError).font(.caption).foregroundColor(.red).textSelection(.enabled)
                }
                if let translation {
                    summary(translation)
                    dnsNote(translation)
                    if !translation.warnings.isEmpty {
                        warningsBox(translation.warnings)
                    }
                }
            }
        }
        .task {
            await dockerManager.refreshAvailability()
            await dockerManager.refreshContainers()
        }
    }

    private var picker: some View {
        HStack {
            Picker("Docker container", selection: Binding(
                get: { selectedContainerID ?? "" },
                set: { id in if !id.isEmpty { onSelect(id) } }
            )) {
                Text("Choose a container…").tag("")
                ForEach(dockerManager.containers) { container in
                    Text("\(container.name) · \(container.image) · \(container.state)")
                        .tag(container.id)
                }
            }
            Button {
                Task { await dockerManager.refreshContainers() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            .disabled(dockerManager.isRefreshing)
        }
    }

    private func summary(_ translation: DockerTranslation) -> some View {
        let spec = translation.spec
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Configuration to recreate", count: 0)
            line("Image", spec.image)
            if let entrypoint = spec.entrypoint { line("Entrypoint", entrypoint) }
            if !spec.command.isEmpty { line("Command", spec.command.joined(separator: " ")) }
            if let workdir = spec.workingDirectory { line("Working dir", workdir) }
            if let user = spec.user { line("User", user) }
            if let cpus = spec.cpus { line("CPUs", "\(cpus)") }
            if let memory = spec.memoryBytes {
                line("Memory", ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))
            }
            if let network = spec.network { line("Network", "\(network) (created if missing)") }
            if !translation.volumesToCreate.isEmpty {
                line("Named volumes", translation.volumesToCreate.joined(separator: ", ") + " (created empty)")
            }
            Text("Ports, volumes and environment variables were filled into Container Options below — review them before creating.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    /// Docker containers usually talk to each other by name; say whether
    /// that will keep working in Apple Container.
    @ViewBuilder
    private func dnsNote(_ translation: DockerTranslation) -> some View {
        let name = translation.spec.name ?? "<name>"
        if let domain = containerManager.systemDNSDomain {
            Label("Other containers can reach this one as \(name) or \(name).\(domain) through the service DNS domain \"\(domain)\".", systemImage: "network")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("No DNS domain is configured for the container service — other containers can only reach this one by IP address.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("To enable names: add `[dns]` and `domain = \"test\"` to ~/.config/container/config.toml, restart the container service, then run `sudo container system dns create test` once.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    private func warningsBox(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Not everything maps to Apple Container", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            ForEach(warnings, id: \.self) { warning in
                Text("• \(warning)").font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    private func unavailable(_ title: String, _ message: String, showOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            Text(message).font(.caption)
            HStack {
                if showOpen {
                    Button("Open Docker Desktop") { DockerWrapper.openDockerDesktop() }
                }
                Button("Retry") { Task { await dockerManager.refreshAll() } }
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }
}
