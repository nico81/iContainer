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
    @AppStorage(SettingsManager.Keys.glassButtons) private var glassButtons = SettingsManager.Defaults.glassButtons

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
                } else {
                    Image(systemName: serviceManager.isServiceRunning ? "stop.fill" : "play.fill")
                        .foregroundColor(serviceManager.isServiceRunning ? .red : .green)
                        .brightness(serviceManager.isServiceRunning ? 0.05 : 0.15)
                        .frame(width: 16, height: 16)
                }
            }
            .actionButtonStyle(glass: glassButtons)
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
    @AppStorage(SettingsManager.Keys.glassButtons) private var glassButtons = SettingsManager.Defaults.glassButtons
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
                            }
                            .actionButtonStyle(glass: glassButtons)
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
                            }
                            .actionButtonStyle(glass: glassButtons)
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
