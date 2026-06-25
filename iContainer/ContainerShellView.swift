import SwiftUI
import Combine

/// "Shell" tab of the container detail view.
///
/// Maintains a persistent `/bin/sh` exec per container, so jumping
/// between tabs (or even leaving and coming back to the container)
/// preserves history and running state.

// MARK: - Session

/// Long-lived `container exec -i <id> /bin/sh` process owned by the
/// container shell tab.
///
/// Sessions are cached per container ID in `shared(for:)` so that
/// re-creating the SwiftUI view (e.g. on tab switch) reuses the same
/// running shell instead of spawning a new one. The process is kept
/// alive until `stop()` is called explicitly.
final class ContainerShellSession: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    private let containerId: String
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    private static var cache: [String: ContainerShellSession] = [:]

    static func shared(for containerId: String) -> ContainerShellSession {
        if let existing = cache[containerId] {
            return existing
        }
        let created = ContainerShellSession(containerId: containerId)
        cache[containerId] = created
        return created
    }

    private init(containerId: String) {
        self.containerId = containerId
    }

    func startIfNeeded() {
        guard !isRunning else { return }
        guard let cliPath = resolveContainerCLIPath() else {
            lastError = "CLI tool 'container' not found."
            return
        }

        let preferredShell = SettingsManager.storedShellContainerPath()
        var shellPaths = [preferredShell]
        if preferredShell != "/bin/sh" {
            shellPaths.append("/bin/sh")
        }

        let candidates: [[String]] = shellPaths.flatMap { shell in
            [
                ["exec", "-i", containerId, shell],
                ["exec", containerId, shell]
            ]
        }

        for args in candidates {
            if startProcess(cliPath: cliPath, arguments: args) {
                return
            }
        }

        lastError = "Unable to start shell session."
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        isRunning = false
    }

    func send(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !isRunning {
            startIfNeeded()
        }
        guard let data = (trimmed + "\n").data(using: .utf8) else { return }
        inputPipe?.fileHandleForWriting.write(data)
    }

    func clear() {
        output = ""
    }

    private func startProcess(cliPath: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = arguments

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.output.append(contentsOf: chunk)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                if self?.output.isEmpty == true {
                    self?.lastError = "Shell session ended without output."
                }
            }
        }

        do {
            try process.run()
            self.process = process
            self.inputPipe = input
            self.outputPipe = output
            self.lastError = nil
            self.isRunning = true
            if self.output.isEmpty {
                self.output = "[shell started]\n"
            } else {
                self.output.append("\n[shell restarted]\n")
            }
            return true
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return false
        }
    }

    private func resolveContainerCLIPath() -> String? {
        SettingsManager.resolvedContainerCLIPath()
    }
}

// MARK: - View

struct ContainerShellView: View {
    let details: ContainerDetails?
    let containerId: String
    @StateObject private var session: ContainerShellSession
    @State private var command: String = ""
    @State private var autoScroll = true

    init(details: ContainerDetails?, containerId: String) {
        self.details = details
        self.containerId = containerId
        _session = StateObject(wrappedValue: ContainerShellSession.shared(for: containerId))
    }

    var body: some View {
        GeometryReader { proxy in
            let shellHeight = max(280, proxy.size.height - 240)
            VStack(alignment: .leading, spacing: 24) {
                if let details = details {
                    ContainerHeaderView(details: details)
                } else {
                    ProgressView("Loading Details...")
                        .padding(.top, 12)
                }

                DetailSection(title: "Shell", icon: "terminal") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Toggle("Auto Scroll", isOn: $autoScroll)
                                .toggleStyle(.switch)
                            Spacer()
                            Button("Clear") {
                                session.clear()
                            }
                        }

                        ScrollViewReader { scrollProxy in
                            let s = SettingsManager.shared
                            ScrollView {
                                Text(session.output.isEmpty ? "Shell output will appear here." : session.output)
                                    .font(.custom(s.terminalFontName, size: s.terminalFontSize, relativeTo: .body).monospaced())
                                    .foregroundColor(s.forceBlackTerminal ? .white : nil)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(s.forceBlackTerminal ? 8 : 0)
                                Color.clear
                                    .frame(height: 1)
                                    .id("SHELL_BOTTOM")
                            }
                            .frame(height: shellHeight)
                            .background(s.forceBlackTerminal ? Color.black : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: s.forceBlackTerminal ? AppRadius.small : 0))
                            .onChange(of: session.output) { _, _ in
                                guard autoScroll else { return }
                                withAnimation(.easeOut(duration: 0.15)) {
                                    scrollProxy.scrollTo("SHELL_BOTTOM", anchor: .bottom)
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            TextField("Command", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    let toSend = command
                                    command = ""
                                    session.send(toSend)
                                }
                            Button("Send") {
                                let toSend = command
                                command = ""
                                session.send(toSend)
                            }
                            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if let error = session.lastError, !error.isEmpty {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .onAppear {
            session.startIfNeeded()
        }
    }
}
