import SwiftUI

/// Shared context-menu / submenu actions for a machine. Mirrors
/// `ContainerActionsMenuItems` so the sidebar context menu and the menu bar
/// extra present the same homogeneous set of actions. Tabs are
/// Info (0) / Run (1) / Logs (2).
struct MachineActionsMenuItems: View {
    let machine: Machine
    let onNavigateToTab: (Int) -> Void
    let onEditConfig: () -> Void
    let onRequestStop: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var containerManager: ContainerizationWrapper

    var body: some View {
        if machine.status == .running {
            Button(role: .destructive) {
                onRequestStop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Button {
                Task {
                    await containerManager.stopMachine(machineId: machine.id)
                    await containerManager.startMachine(machineId: machine.id)
                }
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
        } else {
            Button {
                Task {
                    await containerManager.startMachine(machineId: machine.id)
                }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
        }

        Divider()

        Button { onNavigateToTab(0) } label: {
            Label("Info", systemImage: "info.circle")
        }
        Button { onNavigateToTab(1) } label: {
            Label("Run", systemImage: "terminal")
        }
        Button { onNavigateToTab(2) } label: {
            Label("Logs", systemImage: "doc.plaintext")
        }

        Divider()

        Button { onEditConfig() } label: {
            Label("Edit Configuration", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button(role: .destructive) { onDelete() } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }
}
