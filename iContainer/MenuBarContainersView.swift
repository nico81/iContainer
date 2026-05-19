import SwiftUI

struct MenuBarContainersView: View {
    @EnvironmentObject private var containerManager: ContainerizationWrapper
    @EnvironmentObject private var serviceManager: ServiceManager
    @EnvironmentObject private var appNavigation: AppNavigation
    @Environment(\.openWindow) private var openWindow
    @State private var isUpdatingService = false

    var body: some View {
        Group {
            serviceSection

            Divider()

            Text(AppVersion.displayString)

            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Open iContainer", systemImage: "shippingbox")
            }

            Divider()

            if containerManager.containers.isEmpty {
                Text("No containers")
            } else {
                ForEach(containerManager.containers) { container in
                    Menu {
                        ContainerActionsMenuItems(
                            container: container,
                            onNavigateToTab: { tab in
                                showContainer(container, tab: tab)
                            },
                            onEditSettings: {
                                editContainer(container)
                            },
                            onRequestStop: {
                                Task {
                                    await containerManager.stopContainer(containerId: container.id)
                                    await refreshMenuState()
                                }
                            },
                            onDelete: {
                                Task {
                                    await containerManager.deleteContainer(containerId: container.id)
                                    await refreshMenuState()
                                }
                            }
                        )
                    } label: {
                        Label {
                            Text(container.name)
                        } icon: {
                            Image(nsImage: MenuBarImages.statusDot(isRunning: container.status == .running))
                        }
                    }
                }
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit iContainer", systemImage: "power")
            }
        }
        .task {
            await refreshMenuState()
        }
    }

    @ViewBuilder
    private var serviceSection: some View {
        Label {
            Text(serviceManager.isServiceRunning ? "Service running" : "Service stopped")
        } icon: {
            Image(nsImage: MenuBarImages.statusDot(isRunning: serviceManager.isServiceRunning))
        }

        if serviceManager.isServiceRunning {
            Button {
                showServiceDetails()
            } label: {
                Label("Apple container service details", systemImage: "server.rack")
            }

            Button(role: .destructive) {
                updateService(isStarting: false)
            } label: {
                Label("Stop Service", systemImage: "stop.fill")
            }
            .disabled(isUpdatingService)
        } else {
            Button {
                updateService(isStarting: true)
            } label: {
                Label("Start Service", systemImage: "play.fill")
            }
            .disabled(isUpdatingService)
        }
    }

    private func showContainer(_ container: Container, tab: Int) {
        openMainWindow()
        appNavigation.showContainer(id: container.id, tab: tab)
    }

    private func editContainer(_ container: Container) {
        openMainWindow()
        appNavigation.editContainer(id: container.id)
    }

    private func showServiceDetails() {
        openMainWindow()
        appNavigation.showService()
    }

    private func updateService(isStarting: Bool) {
        guard !isUpdatingService else { return }
        isUpdatingService = true
        Task {
            if isStarting {
                await serviceManager.startService()
            } else {
                await serviceManager.stopService()
            }
            await refreshMenuState()
            isUpdatingService = false
        }
    }

    private func refreshMenuState() async {
        await serviceManager.checkServiceStatus()
        await containerManager.refreshContainers()
    }

    private func openMainWindow() {
        openWindow(id: "main")
        appNavigation.activateApp()
    }
}
