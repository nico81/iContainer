import SwiftUI

/// "Shell" tab of the machine detail view: a full terminal on the machine's
/// login shell (`container machine run -t -i`), kept alive across tab
/// switches by the cached `TerminalSession`. `machine run` boots a stopped
/// machine, so a stopped machine waits for an explicit click (only one
/// machine runs at a time).
struct MachineShellView: View {
    let machineId: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @StateObject private var session: TerminalSession
    @AppStorage("machineShell.runAsRoot") private var runAsRoot = false
    @State private var confirmingUserSwitch = false

    init(machineId: String) {
        self.machineId = machineId
        _session = StateObject(wrappedValue: TerminalSession.shared(key: "machine:\(machineId)"))
    }

    private var isMachineRunning: Bool {
        containerManager.machines.first { $0.id == machineId }?.status == .running
    }

    private func shellArguments() -> [String] {
        TerminalCommands.machineShell(machineId: machineId, asRoot: runAsRoot)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 16) {
                MachineHeaderView(machineId: machineId)
                DetailSection(title: "Terminal", icon: "terminal") {
                    // Same rule as containers: a stopped machine shows the boot
                    // prompt, not the dead terminal of its last session.
                    if isMachineRunning || session.isRunning {
                        TerminalPanel(
                            session: session,
                            startArguments: shellArguments,
                            accessory: AnyView(
                                Toggle("Run as root", isOn: rootToggleBinding)
                                    .toggleStyle(.checkbox)
                                    .help("Run the shell as root instead of your Mac user. Switching restarts the open session.")
                            )
                        )
                        .frame(height: max(320, proxy.size.height - 180))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "terminal").font(.largeTitle).foregroundColor(.secondary)
                            Text("The machine is stopped. Opening a terminal boots it — only one machine runs at a time.")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Toggle("Run as root", isOn: $runAsRoot).toggleStyle(.checkbox)
                            Button("Boot Machine & Open Terminal") { session.start(arguments: shellArguments()) }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if isMachineRunning, session.state == .idle { session.start(arguments: shellArguments()) }
        }
        .confirmationDialog(
            runAsRoot ? "Restart the terminal as root?" : "Restart the terminal as your Mac user?",
            isPresented: $confirmingUserSwitch,
            titleVisibility: .visible
        ) {
            Button("Restart Terminal") { session.start(arguments: shellArguments()) }
            Button("Cancel", role: .cancel) { runAsRoot.toggle() }
        } message: {
            Text("The open session ends; anything running in it stops.")
        }
    }

    /// Toggling with a live session asks to restart it, so the user the
    /// shell runs as always matches the checkbox; Cancel reverts the box.
    private var rootToggleBinding: Binding<Bool> {
        Binding(
            get: { runAsRoot },
            set: { newValue in
                runAsRoot = newValue
                if session.isRunning { confirmingUserSwitch = true }
            }
        )
    }
}
