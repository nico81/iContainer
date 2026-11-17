import SwiftUI

/// "Shell" tab of the container detail view: a full terminal
/// (`container exec -t -i`) in a cached `TerminalSession`, so the shell and
/// whatever runs in it survive tab switches and leaving the container.
struct ContainerShellView: View {
    let details: ContainerDetails?
    let containerId: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @StateObject private var session: TerminalSession
    @State private var isStartingContainer = false

    init(details: ContainerDetails?, containerId: String) {
        self.details = details
        self.containerId = containerId
        _session = StateObject(wrappedValue: TerminalSession.shared(key: "container:\(containerId)"))
    }

    private var isContainerRunning: Bool {
        containerManager.containers.first { $0.id == containerId }?.status == .running
    }

    private func shellArguments() -> [String] {
        TerminalCommands.containerShell(containerId: containerId, preferredShell: SettingsManager.storedShellContainerPath())
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                if let details {
                    ContainerHeaderView(details: details)
                } else {
                    ProgressView("Loading Details...")
                        .padding(.top, 12)
                }

                DetailSection(title: "Terminal", icon: "terminal") {
                    if isContainerRunning || session.isRunning {
                        TerminalPanel(session: session, startArguments: shellArguments)
                            .frame(height: max(320, proxy.size.height - 200))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "terminal").font(.largeTitle).foregroundColor(.secondary)
                            Text("The container isn't running. Start it to open a terminal.")
                                .foregroundColor(.secondary)
                            Button {
                                isStartingContainer = true
                                Task {
                                    await containerManager.startContainer(containerId: containerId)
                                    isStartingContainer = false
                                }
                            } label: {
                                if isStartingContainer { ProgressView().controlSize(.small) } else { Text("Start Container") }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isStartingContainer)
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
            }
            .padding()
        }
        .onAppear(perform: startIfPossible)
        .onChange(of: isContainerRunning) { _, running in
            if running { startIfPossible() }
        }
    }

    /// Opens the shell automatically while the container runs; an ended
    /// session waits for the user (so its last output stays readable).
    private func startIfPossible() {
        guard isContainerRunning, session.state == .idle else { return }
        session.start(arguments: shellArguments())
    }
}
