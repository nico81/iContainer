import SwiftUI
import AppKit

// MARK: - Sidebar rows

/// One network in the sidebar. Delete is hidden for the builtin `default`
/// network and disabled while containers are attached (the CLI refuses
/// either way — we just don't offer a button that can only fail).
struct NetworkRowView: View {
    let network: ContainerNetwork
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var appNavigation: AppNavigation
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    private var attached: [Container] { containerManager.containers(onNetwork: network.name) }
    private var canDelete: Bool { !network.isBuiltin && attached.isEmpty }

    private var attachedText: String {
        switch attached.count {
        case 0: return "no containers"
        case 1: return attached[0].name
        default: return "\(attached.count) containers"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(network.name)
                        .font(.headline)
                    if network.isBuiltin {
                        Text("builtin")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
                // One line, subnet first so it never gets cut.
                Text("\(network.ipv4Subnet ?? "no subnet") · \(attachedText)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            HStack(spacing: 12) {
                ZStack {
                    if isDeleting || containerManager.updatingNetworkIDs.contains(network.name) {
                        ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                    } else if !network.isBuiltin {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash").frame(width: 16, height: 16).padding(3)
                        }
                        .actionButtonStyle(circular: true)
                        .controlSize(.small)
                        .disabled(!canDelete)
                        .help(canDelete ? "Delete network" : "In use by \(attached.map(\.name).joined(separator: ", "))")
                    }
                }
            }
            .frame(width: 60)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                appNavigation.requestNewContainer(prefill: NewContainerPrefill(network: network.name))
            } label: {
                Label("Create Container on This Network…", systemImage: "plus")
            }
            Divider()
            if let subnet = network.ipv4Subnet {
                Button("Copy Subnet (\(subnet))") { copyToPasteboard(subnet) }
            }
            if let gateway = network.ipv4Gateway {
                Button("Copy Gateway (\(gateway))") { copyToPasteboard(gateway) }
            }
            Button("Copy Name") { copyToPasteboard(network.name) }
            if !network.isBuiltin {
                Divider()
                Button("Delete Network…", role: .destructive) { showingDeleteConfirmation = true }
                    .disabled(!canDelete)
            }
        }
        .confirmationDialog("Delete Network?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await containerManager.deleteNetwork(name: network.name)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete network \"\(network.name)\"? Containers created later with this network name will fail to start until it is recreated.")
        }
    }
}

/// One volume in the sidebar. Delete is disabled while a container mounts it.
struct VolumeRowView: View {
    let volume: ContainerVolume
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var appNavigation: AppNavigation
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false

    private var users: [Container] { containerManager.containers(usingVolume: volume.name) }

    private var usersText: String {
        switch users.count {
        case 0: return volume.isAnonymous ? "orphaned — no container uses it" : "not mounted"
        case 1: return "mounted by \(users[0].name)"
        default: return "mounted by \(users.count) containers"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(volume.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if volume.isAnonymous {
                        Text("anonymous")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .help("Created automatically by an image VOLUME directive when a container was created; deleting that container does not remove the volume")
                    }
                }
                // The ext4 superblock on the host is only consistent while the
                // volume is unmounted (the guest kernel flushes it lazily), so
                // the content count is shown for idle volumes only.
                Text([volume.displayUsage, users.isEmpty ? volume.displayContents : nil, usersText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            HStack(spacing: 12) {
                ZStack {
                    if isDeleting || containerManager.updatingVolumeIDs.contains(volume.name) {
                        ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                    } else {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash").frame(width: 16, height: 16).padding(3)
                        }
                        .actionButtonStyle(circular: true)
                        .controlSize(.small)
                        .disabled(!users.isEmpty)
                        .help(users.isEmpty ? "Delete volume" : "Mounted by \(users.map(\.name).joined(separator: ", "))")
                    }
                }
            }
            .frame(width: 60)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                appNavigation.requestNewContainer(prefill: NewContainerPrefill(volume: volume.name))
            } label: {
                Label("Create Container with This Volume…", systemImage: "plus")
            }
            if let source = volume.source, FileManager.default.fileExists(atPath: source) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source)])
                } label: {
                    Label("Reveal Backing File in Finder", systemImage: "folder")
                }
            }
            Divider()
            Button("Copy Name") { copyToPasteboard(volume.name) }
            Button("Copy Mount Mapping (\(volume.displayName):/data)") { copyToPasteboard("\(volume.name):/data") }
            Divider()
            Button("Delete Volume…", role: .destructive) { showingDeleteConfirmation = true }
                .disabled(!users.isEmpty)
        }
        .confirmationDialog("Delete Volume?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await containerManager.deleteVolume(name: volume.name)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete volume \"\(volume.name)\"? All data stored in it is lost. This cannot be undone.")
        }
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Detail views

struct NetworkDetailView: View {
    let networkName: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var appNavigation: AppNavigation
    @State private var showingDeleteConfirmation = false

    private var network: ContainerNetwork? { containerManager.networks.first { $0.name == networkName } }
    private var attached: [Container] { containerManager.containers(onNetwork: networkName) }

    var body: some View {
        ScrollView {
            if let network {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(network.name).font(.largeTitle).fontWeight(.bold)
                            Spacer()
                            if network.isBuiltin {
                                StatusBadge(status: "builtin")
                            }
                        }
                        Text("Network").font(.caption).foregroundColor(.secondary)
                    }

                    DetailSection(title: "Configuration", icon: "network") {
                        DetailRow(label: "Mode", value: network.mode ?? "-")
                        DetailRow(label: "Plugin", value: network.plugin ?? "-", isMonospaced: true)
                        DetailRow(label: "Created", value: network.creationDate ?? "-")
                        if !network.labels.isEmpty {
                            DetailRow(label: "Labels", value: network.labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"), isMonospaced: true)
                        }
                    }

                    DetailSection(title: "Addressing", icon: "globe") {
                        DetailRow(label: "IPv4 Subnet", value: network.ipv4Subnet ?? "-", isMonospaced: true)
                        DetailRow(label: "IPv4 Gateway", value: network.ipv4Gateway ?? "-", isMonospaced: true)
                        DetailRow(label: "IPv6 Subnet", value: network.ipv6Subnet ?? "-", isMonospaced: true)
                        if let domain = containerManager.systemDNSDomain {
                            Text("Containers on this network resolve each other as <name> or <name>.\(domain).")
                                .font(.caption2).foregroundColor(.secondary)
                        } else {
                            Text("No service DNS domain is configured: containers on this network reach each other by IP only. See the Service page for how to enable it.")
                                .font(.caption2).foregroundColor(.orange)
                        }
                    }

                    attachedContainersSection(attached, emptyText: "No containers are attached to this network.")

                    HStack(spacing: 10) {
                        Button {
                            appNavigation.requestNewContainer(prefill: NewContainerPrefill(network: network.name))
                        } label: {
                            Label("Create Container on This Network", systemImage: "plus")
                        }
                        .actionButtonStyle(prominent: true)
                        if !network.isBuiltin {
                            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                                Label("Delete Network", systemImage: "trash")
                            }
                            .disabled(!attached.isEmpty || containerManager.updatingNetworkIDs.contains(network.name))
                            .help(attached.isEmpty ? "" : "Detach or delete the attached containers first.")
                        }
                        Spacer()
                    }
                    Text("Containers join a network when they are created (`--network`); an existing container can't be moved to another network.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding()
            } else {
                Text("Network \"\(networkName)\" no longer exists.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
            }
        }
        .navigationTitle(networkName)
        .confirmationDialog("Delete Network?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await containerManager.deleteNetwork(name: networkName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete network \"\(networkName)\"?")
        }
    }

    private func attachedContainersSection(_ containers: [Container], emptyText: String) -> some View {
        DetailSection(title: "Attached Containers", icon: "shippingbox") {
            if containers.isEmpty {
                Text(emptyText).font(.callout).foregroundColor(.secondary)
            } else {
                ForEach(containers) { container in
                    Button {
                        appNavigation.showContainer(id: container.id, tab: 0)
                    } label: {
                        HStack(spacing: 10) {
                            StatusDot(isRunning: container.status == .running)
                            Text(container.name).font(.callout.weight(.medium))
                            if let ip = container.ipAddress {
                                Text(ip).font(.caption.monospaced()).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

struct VolumeDetailView: View {
    let volumeName: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var appNavigation: AppNavigation
    @State private var showingDeleteConfirmation = false

    private var volume: ContainerVolume? { containerManager.volumes.first { $0.name == volumeName } }
    private var users: [Container] { containerManager.containers(usingVolume: volumeName) }

    var body: some View {
        ScrollView {
            if let volume {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(volume.name).font(.largeTitle).fontWeight(.bold)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            if volume.isAnonymous { StatusBadge(status: "anonymous") }
                        }
                        Text("Volume").font(.caption).foregroundColor(.secondary)
                    }

                    DetailSection(title: "Configuration", icon: "internaldrive") {
                        DetailRow(label: "Contents", value: users.isEmpty
                                  ? (volume.displayContents.map { $0 == "empty" ? "Empty filesystem — nothing was ever written to it" : $0 } ?? "-")
                                  : "Mounted — inspect from inside the container (the on-disk index is updated when the container stops)")
                        DetailRow(label: "Used on disk", value: volume.displayAllocated ?? "-")
                        DetailRow(label: "Capacity", value: volume.displayCapacity)
                        DetailRow(label: "Driver", value: volume.driver ?? "-")
                        DetailRow(label: "Filesystem", value: volume.format ?? "-")
                        DetailRow(label: "Created", value: volume.creationDate ?? "-")
                        if volume.isAnonymous {
                            Text(users.isEmpty
                                 ? "Created automatically by an image VOLUME directive when a container was created; that container has since been deleted, so nothing can reach this data any more. Prune Unused Volumes removes it."
                                 : "Created automatically by an image VOLUME directive for the container that mounts it.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Text("Capacity is the maximum the sparse backing image can grow to; \"Used on disk\" is what it actually occupies on your Mac.")
                            .font(.caption2).foregroundColor(.secondary)
                    }

                    DetailSection(title: "Backing File", icon: "doc") {
                        HStack(spacing: 6) {
                            Text(volume.source ?? "-")
                                .font(InfoTextStyle.monospacedValueFont)
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            if let source = volume.source, FileManager.default.fileExists(atPath: source) {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source)])
                                } label: { Image(systemName: "folder") }
                                .buttonStyle(.borderless)
                                .help("Reveal in Finder")
                            }
                        }
                    }

                    DetailSection(title: "Mounted By", icon: "shippingbox") {
                        if users.isEmpty {
                            Text("No container mounts this volume.").font(.callout).foregroundColor(.secondary)
                        } else {
                            ForEach(users) { container in
                                Button {
                                    appNavigation.showContainer(id: container.id, tab: 0)
                                } label: {
                                    HStack(spacing: 10) {
                                        StatusDot(isRunning: container.status == .running)
                                        Text(container.name).font(.callout.weight(.medium))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            appNavigation.requestNewContainer(prefill: NewContainerPrefill(volume: volume.name))
                        } label: {
                            Label("Create Container with This Volume", systemImage: "plus")
                        }
                        .actionButtonStyle(prominent: true)
                        Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                            Label("Delete Volume", systemImage: "trash")
                        }
                        .disabled(!users.isEmpty || containerManager.updatingVolumeIDs.contains(volume.name))
                        .help(users.isEmpty ? "" : "Delete the containers that mount it first.")
                        Spacer()
                    }
                    Text("Mount it in a new container as `\(volume.name):/path`. The data lives only inside the ext4 image, so the way to read it is from a container.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding()
            } else {
                Text("Volume \"\(volumeName)\" no longer exists.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 50)
            }
        }
        .navigationTitle(volume?.displayName ?? volumeName)
        .confirmationDialog("Delete Volume?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await containerManager.deleteVolume(name: volumeName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete volume \"\(volumeName)\"? All data stored in it is lost. This cannot be undone.")
        }
    }
}

// MARK: - Create sheets

struct CreateNetworkSheet: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    let onCreated: (String) -> Void
    let onClose: () -> Void
    @State private var name = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isNameValid: Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return !trimmedName.isEmpty && trimmedName.allSatisfy { allowed.contains($0) }
    }
    private var nameTaken: Bool { containerManager.networks.contains { $0.name == trimmedName } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Network").font(.headline)
            TextField("Name (e.g. app-net)", text: $name).textFieldStyle(.roundedBorder)
            if !trimmedName.isEmpty && !isNameValid {
                Text("Use letters, digits, '-', '_' or '.' only.").font(.caption).foregroundColor(.orange)
            } else if nameTaken {
                Text("A network named \"\(trimmedName)\" already exists.").font(.caption).foregroundColor(.orange)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red).textSelection(.enabled)
            }
            HStack {
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isNameValid || nameTaken || isCreating)
                if isCreating { ProgressView().scaleEffect(0.8) }
                Spacer()
                Button("Close") { onClose() }
            }
            Text("Creates a NAT network with its own subnet (`container network create`). Attach containers to it with the Network option when creating them.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 460, minHeight: 200)
    }

    private func create() {
        isCreating = true
        errorMessage = nil
        Task {
            let ok = await containerManager.createNetwork(name: trimmedName)
            isCreating = false
            if ok {
                onCreated(trimmedName)
            } else {
                errorMessage = containerManager.lastErrorMessage
                containerManager.lastErrorMessage = nil
            }
        }
    }
}

struct CreateVolumeSheet: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    let onCreated: (String) -> Void
    let onClose: () -> Void
    @State private var name = ""
    @State private var size = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isNameValid: Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return !trimmedName.isEmpty && trimmedName.allSatisfy { allowed.contains($0) }
    }
    private var nameTaken: Bool { containerManager.volumes.contains { $0.name == trimmedName } }
    /// `-s` accepts a number with an optional K/M/G/T/P suffix.
    private var isSizeValid: Bool {
        let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return trimmed.range(of: #"^\d+(\.\d+)?\s*[KMGTPkmgtp]?[iI]?[bB]?$"#, options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Volume").font(.headline)
            TextField("Name (e.g. pgdata)", text: $name).textFieldStyle(.roundedBorder)
            if !trimmedName.isEmpty && !isNameValid {
                Text("Use letters, digits, '-', '_' or '.' only.").font(.caption).foregroundColor(.orange)
            } else if nameTaken {
                Text("A volume named \"\(trimmedName)\" already exists.").font(.caption).foregroundColor(.orange)
            }
            TextField("Capacity (optional, e.g. 10G — CLI default when empty)", text: $size).textFieldStyle(.roundedBorder)
            if !isSizeValid {
                Text("Enter a size like 512M, 10G or 1T.").font(.caption).foregroundColor(.orange)
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red).textSelection(.enabled)
            }
            HStack {
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isNameValid || nameTaken || !isSizeValid || isCreating)
                if isCreating { ProgressView().scaleEffect(0.8) }
                Spacer()
                Button("Close") { onClose() }
            }
            Text("Creates a named volume (`container volume create`) backed by a sparse ext4 image; capacity is the maximum it can grow to. Mount it in a container as `<name>:/path`.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 460, minHeight: 240)
    }

    private func create() {
        isCreating = true
        errorMessage = nil
        Task {
            let ok = await containerManager.createVolume(name: trimmedName, size: size.isEmpty ? nil : size)
            isCreating = false
            if ok {
                onCreated(trimmedName)
            } else {
                errorMessage = containerManager.lastErrorMessage
                containerManager.lastErrorMessage = nil
            }
        }
    }
}
