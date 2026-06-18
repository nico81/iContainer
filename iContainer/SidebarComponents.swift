import SwiftUI

/// Sidebar-specific row views used by `ContentView`. Each row owns its
/// own confirmation alerts and inline action buttons so the parent
/// `List` can stay focused on selection and search.

// MARK: - Service status row

/// Top sidebar entry showing whether the Apple container service is up
/// and exposing a start/stop button.
struct ServiceStatusView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var isProcessing = false

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(isRunning: serviceManager.isServiceRunning, size: 14)
            VStack(alignment: .leading, spacing: 4) {
                Text("Container service")
                    .font(.headline)
                Text(serviceManager.serviceStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            Button(action: {
                isProcessing = true
                Task {
                    if serviceManager.isServiceRunning {
                        await serviceManager.stopService()
                    } else {
                        await serviceManager.startService()
                    }
                    isProcessing = false
                }
            }) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                        .padding(6)
                } else {
                    Image(systemName: serviceManager.isServiceRunning ? "stop.fill" : "play.fill")
                        .foregroundColor(serviceManager.isServiceRunning ? .red : .green)
                        .brightness(serviceManager.isServiceRunning ? 0.05 : 0.15)
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
            }
            .actionButtonStyle(circular: true)
            .controlSize(.small)
            .disabled(isProcessing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Container row

/// One container in the sidebar. Renders the running/stopped indicator,
/// image / IP labels, an inline start/stop button, plus the context-menu
/// driven action set (`ContainerActionsMenuItems`).
struct ContainerRowView: View {
    let container: Container
    let onNavigateToTab: (Int) -> Void
    let onEditSettings: () -> Void
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingDeleteConfirmation = false
    @State private var showingStopConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    StatusDot(isRunning: container.status == .running)
                    Text(container.name)
                        .font(.headline)
                }
                // One compact subtitle: the IP address when the container
                // has one (i.e. it is running), otherwise the image reference.
                if let ip = container.ipAddress {
                    Label(ip, systemImage: "network")
                        .font(.caption)
                } else if let image = container.image {
                    Label(image, systemImage: "shippingbox")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            HStack(spacing: 12) {
                ZStack {
                    if isDeleting || containerManager.updatingContainerIDs.contains(container.id) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                            .padding(3)
                    } else {
                        if container.status == .stopped {
                            Button {
                                Task {
                                    await containerManager.startContainer(containerId: container.id)
                                }
                            } label: {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.green)
                                    .brightness(0.15)
                                    .frame(width: 16, height: 16)
                                    .padding(3)
                            }
                            .actionButtonStyle(circular: true)
                            .controlSize(.small)
                        } else {
                            Button {
                                if SettingsManager.shared.confirmStop {
                                    showingStopConfirmation = true
                                } else {
                                    Task {
                                        await containerManager.stopContainer(containerId: container.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                                    .brightness(0.05)
                                    .frame(width: 16, height: 16)
                                    .padding(3)
                            }
                            .actionButtonStyle(circular: true)
                            .controlSize(.small)
                        }
                    }
                }
                .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            ContainerActionsMenuItems(
                container: container,
                onNavigateToTab: onNavigateToTab,
                onEditSettings: onEditSettings,
                onRequestStop: {
                    if SettingsManager.shared.confirmStop {
                        showingStopConfirmation = true
                    } else {
                        Task { await containerManager.stopContainer(containerId: container.id) }
                    }
                },
                onDelete: {
                    if SettingsManager.shared.confirmDelete {
                        showingDeleteConfirmation = true
                    } else {
                        isDeleting = true
                        Task {
                            await containerManager.deleteContainer(containerId: container.id)
                            isDeleting = false
                        }
                    }
                }
            )
        }
        .confirmationDialog("Delete Container?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await containerManager.deleteContainer(containerId: container.id)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the container \"\(container.name)\"? This action cannot be undone.")
        }
        .alert(isPresented: $showingStopConfirmation) {
            Alert(
                title: Text("Stop Container?"),
                message: Text("Are you sure you want to stop the container \"\(container.name)\"?"),
                primaryButton: .destructive(Text("Stop")) {
                    Task {
                        await containerManager.stopContainer(containerId: container.id)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

// MARK: - Machine row

/// One container machine in the sidebar: status dot, name (with a default
/// marker), an inline start/stop button, and a context menu for
/// set-default / delete.
struct MachineRowView: View {
    let machine: Machine
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingDeleteConfirmation = false

    private var isBusy: Bool {
        containerManager.updatingMachineIDs.contains(machine.id)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    StatusDot(isRunning: machine.status == .running)
                    Text(machine.name)
                        .font(.headline)
                    if machine.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                    }
                }
                Label(machineSubtitle, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            ZStack {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                        .padding(3)
                } else if machine.status == .running {
                    Button {
                        Task { await containerManager.stopMachine(machineId: machine.id) }
                    } label: {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red).brightness(0.05)
                            .frame(width: 16, height: 16).padding(3)
                    }
                    .actionButtonStyle(circular: true)
                    .controlSize(.small)
                } else {
                    Button {
                        Task { await containerManager.startMachine(machineId: machine.id) }
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundColor(.green).brightness(0.15)
                            .frame(width: 16, height: 16).padding(3)
                    }
                    .actionButtonStyle(circular: true)
                    .controlSize(.small)
                }
            }
            .frame(width: 60)
        }
        .padding(.vertical, 4)
        .contextMenu {
            if machine.status == .running {
                Button("Stop") { Task { await containerManager.stopMachine(machineId: machine.id) } }
            } else {
                Button("Start") { Task { await containerManager.startMachine(machineId: machine.id) } }
            }
            if !machine.isDefault {
                Button("Set as Default") {
                    Task { await containerManager.setDefaultMachine(machineId: machine.id) }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                if SettingsManager.shared.confirmDelete {
                    showingDeleteConfirmation = true
                } else {
                    Task { await containerManager.deleteMachine(machineId: machine.id) }
                }
            }
        }
        .confirmationDialog("Delete Machine?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await containerManager.deleteMachine(machineId: machine.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the machine \"\(machine.name)\"? This action cannot be undone.")
        }
    }

    private var machineSubtitle: String {
        var parts: [String] = []
        if let cpus = machine.cpus { parts.append("\(cpus) CPU") }
        let mem = MachineDetailView.formatBytes(machine.memoryBytes)
        if mem != "-" { parts.append(mem) }
        return parts.isEmpty ? "machine" : parts.joined(separator: " · ")
    }
}
