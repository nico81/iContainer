import SwiftUI
import Combine

/// "Run" tab of the machine detail view.
///
/// Maintains a persistent interactive `container machine run -n <id> -i`
/// session, mirroring `ContainerShellSession`. Per the docs, `machine run`
/// boots the machine if it is stopped, so opening this tab also starts the
/// machine (subject to the one-machine-at-a-time limit).

// MARK: - Session

final class MachineShellSession: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var lastError: String?

    private let machineId: String
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    private static var cache: [String: MachineShellSession] = [:]

    static func shared(for machineId: String) -> MachineShellSession {
        if let existing = cache[machineId] {
            return existing
        }
        let created = MachineShellSession(machineId: machineId)
        cache[machineId] = created
        return created
    }

    private init(machineId: String) {
        self.machineId = machineId
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

        // Try a specific shell first, then fall back to the machine's login
        // shell (no executable argument).
        var candidates: [[String]] = shellPaths.map { shell in
            ["machine", "run", "-n", machineId, "-i", shell]
        }
        candidates.append(["machine", "run", "-n", machineId, "-i"])

        for args in candidates {
            if startProcess(cliPath: cliPath, arguments: args) {
                return
            }
        }

        lastError = "Unable to start the machine run session."
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
                    self?.lastError = "Run session ended without output."
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
                self.output = "[machine run started]\n"
            } else {
                self.output.append("\n[machine run restarted]\n")
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

struct MachineShellView: View {
    let machineId: String
    @StateObject private var session: MachineShellSession
    @State private var command: String = ""
    @State private var autoScroll = true

    init(machineId: String) {
        self.machineId = machineId
        _session = StateObject(wrappedValue: MachineShellSession.shared(for: machineId))
    }

    var body: some View {
        GeometryReader { proxy in
            let shellHeight = max(280, proxy.size.height - 240)
            VStack(alignment: .leading, spacing: 16) {
                MachineHeaderView(machineId: machineId)
                DetailSection(title: "Shell", icon: "terminal") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Toggle("Auto Scroll", isOn: $autoScroll)
                                .toggleStyle(.switch)
                            Spacer()
                            Button("Clear") { session.clear() }
                        }

                        ScrollViewReader { scrollProxy in
                            let s = SettingsManager.shared
                            ScrollView {
                                Text(session.output.isEmpty ? "Run output will appear here." : session.output)
                                    .font(.custom(s.terminalFontName, size: s.terminalFontSize, relativeTo: .body).monospaced())
                                    .foregroundColor(s.forceBlackTerminal ? .white : nil)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(s.forceBlackTerminal ? 8 : 0)
                                Color.clear.frame(height: 1).id("MACHINE_RUN_BOTTOM")
                            }
                            .frame(height: shellHeight)
                            .background(s.forceBlackTerminal ? Color.black : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: s.forceBlackTerminal ? AppRadius.small : 0))
                            .onChange(of: session.output) { _, _ in
                                guard autoScroll else { return }
                                withAnimation(.easeOut(duration: 0.15)) {
                                    scrollProxy.scrollTo("MACHINE_RUN_BOTTOM", anchor: .bottom)
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            TextField("Command", text: $command)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { sendCommand() }
                            Button("Send") { sendCommand() }
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
        .onAppear { session.startIfNeeded() }
    }

    private func sendCommand() {
        let toSend = command
        command = ""
        session.send(toSend)
    }
}
