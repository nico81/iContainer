import SwiftUI

struct ContainerActionsMenuItems: View {
    let container: Container
    let onNavigateToTab: (Int) -> Void
    let onEditSettings: () -> Void
    let onRequestStop: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var containerManager: ContainerizationWrapper

    var body: some View {
        if container.status == .running {
            Button(role: .destructive) {
                onRequestStop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Button {
                Task {
                    await containerManager.stopContainer(containerId: container.id)
                    await containerManager.startContainer(containerId: container.id)
                }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
        } else {
            Button {
                Task {
                    await containerManager.startContainer(containerId: container.id)
                }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
        }

        Divider()

        Button {
            onNavigateToTab(0)
        } label: {
            Label("Info", systemImage: "info.circle")
        }

        Button {
            onNavigateToTab(1)
        } label: {
            Label("Stats", systemImage: "chart.xyaxis.line")
        }

        Button {
            onNavigateToTab(2)
        } label: {
            Label("Shell", systemImage: "terminal")
        }

        Button {
            onNavigateToTab(3)
        } label: {
            Label("Logs", systemImage: "doc.plaintext")
        }

        Divider()

        Button {
            onEditSettings()
        } label: {
            Label("Edit", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }
}
