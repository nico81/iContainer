import SwiftUI
import AppKit
import Combine
import SwiftTerm

// MARK: - Commands (pure)

/// The `container` CLI arguments behind the interactive terminals. Both run
/// with `-t -i` inside a real pseudo-terminal (SwiftTerm's
/// `LocalProcessTerminalView`), so full-screen programs, colors, Ctrl-C and
/// window resizes reach the guest — verified that `-t` under a pty gives the
/// guest a `/dev/pts` TTY (CLI 1.7.1).
nonisolated enum TerminalCommands {
    static let termName = "xterm-256color"

    /// Starts the preferred shell when the image has it, else `/bin/sh`.
    static let shellFallbackScript = #"if [ -x "$1" ]; then exec "$1"; fi; exec /bin/sh"#

    static func containerShell(containerId: String, preferredShell: String) -> [String] {
        ["exec", "-t", "-i", "-e", "TERM=\(termName)", containerId,
         "/bin/sh", "-c", shellFallbackScript, "sh", preferredShell]
    }

    /// `machine run` with no executable opens the machine's login shell
    /// (as the host user unless `asRoot`), booting the machine if needed.
    static func machineShell(machineId: String, asRoot: Bool) -> [String] {
        ["machine", "run", "-n", machineId, "-t", "-i", "-e", "TERM=\(termName)"] + (asRoot ? ["--root"] : [])
    }

    /// POSIX single-quoting for the Terminal.app hand-off script.
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// A `.command` file body that runs the same session in Terminal.app.
    static func commandFile(cliPath: String, arguments: [String]) -> String {
        "#!/bin/sh\nexec " + ([cliPath] + arguments).map(shellQuote).joined(separator: " ") + "\n"
    }
}

// MARK: - Session

/// One interactive terminal (container shell or machine shell). Sessions are
/// cached by key, and so is their SwiftTerm view: switching tabs or leaving
/// the detail view keeps the shell, its scrollback and anything running in
/// it alive until the process exits or the user restarts it.
@MainActor
final class TerminalSession: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    enum State: Equatable {
        case idle
        case running
        case ended(exitCode: Int32?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var title = ""

    let terminalView: LocalProcessTerminalView
    private(set) var arguments: [String] = []

    private static var cache: [String: TerminalSession] = [:]

    static func shared(key: String) -> TerminalSession {
        if let existing = cache[key] { return existing }
        let created = TerminalSession()
        cache[key] = created
        return created
    }

    private override init() {
        terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        super.init()
        terminalView.processDelegate = self
        terminalView.optionAsMetaKey = true
    }

    var isRunning: Bool { state == .running }

    /// Starts `container <arguments>`; restarts when already running.
    func start(arguments: [String]) {
        guard let cliPath = SettingsManager.resolvedContainerCLIPath() else {
            state = .failed("CLI tool 'container' not found.")
            return
        }
        if isRunning { terminalView.terminate() }
        self.arguments = arguments
        title = ""
        if state != .idle {
            // Keep the old scrollback, but make the restart visible.
            terminalView.feed(text: "\r\n\u{1B}[2m── new session ──\u{1B}[0m\r\n")
        }
        state = .running
        terminalView.startProcess(
            executable: cliPath,
            args: arguments,
            environment: Terminal.getEnvironmentVariables(termName: TerminalCommands.termName),
            execName: "container"
        )
    }

    func terminate() {
        guard isRunning else { return }
        terminalView.terminate()
    }

    /// Font and colors from Settings › Terminal; called whenever they or
    /// the app's appearance change.
    func applyAppearance(fontName: String, fontSize: Double, forceBlack: Bool) {
        let size = CGFloat(fontSize)
        let font = NSFont(name: fontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if terminalView.font != font { terminalView.font = font }
        terminalView.nativeBackgroundColor = forceBlack ? .black : .textBackgroundColor
        terminalView.nativeForegroundColor = forceBlack ? .white : .textColor
        terminalView.caretColor = forceBlack ? .white : .controlAccentColor
    }

    /// Opens the same session in Terminal.app through a throwaway `.command`
    /// file (no Apple Events permission needed).
    func openInTerminalApp() {
        guard let cliPath = SettingsManager.resolvedContainerCLIPath(), !arguments.isEmpty else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("iContainer-terminal", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("session-\(UUID().uuidString.prefix(8)).command")
        do {
            try TerminalCommands.commandFile(cliPath: cliPath, arguments: arguments).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            state = .failed("Couldn't open Terminal: \(error.localizedDescription)")
        }
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        state = .ended(exitCode: exitCode)
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        state = .failed("The session couldn't start: \(error)")
    }
}

// MARK: - Views

/// Hosts a session's cached terminal view. The view is moved into whichever
/// container is on screen and detached again on teardown, so it survives
/// SwiftUI rebuilding the hierarchy.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if session.terminalView.superview !== container { attach(to: container) }
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        for subview in container.subviews { subview.removeFromSuperview() }
    }

    private func attach(to container: NSView) {
        let terminal = session.terminalView
        terminal.removeFromSuperview()
        terminal.frame = container.bounds
        terminal.autoresizingMask = [.width, .height]
        container.addSubview(terminal)
        DispatchQueue.main.async { terminal.window?.makeFirstResponder(terminal) }
    }
}

/// Terminal plus its header row (status, title, Restart, Terminal.app) and
/// the "session ended" overlay. `startArguments` is read when the user
/// (re)starts the session, so options like Run as root apply then.
struct TerminalPanel: View {
    @ObservedObject var session: TerminalSession
    let startArguments: () -> [String]
    /// Extra controls shown before the buttons (e.g. a Run as root toggle).
    var accessory: AnyView? = nil

    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                statusBadge
                if !session.title.isEmpty {
                    Text(session.title)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if let accessory { accessory }
                Button {
                    session.start(arguments: startArguments())
                } label: {
                    Label(session.isRunning ? "Restart" : "Start", systemImage: "arrow.clockwise")
                }
                .help(session.isRunning ? "End this session and start a new one" : "Start a new session")
                Button {
                    session.openInTerminalApp()
                } label: {
                    Label("Open in Terminal", systemImage: "macwindow")
                }
                .disabled(session.arguments.isEmpty)
                .help("Run the same session in Terminal.app")
            }
            .controlSize(.small)

            ZStack {
                TerminalHostView(session: session)
                    .padding(6)
                    .background(settings.forceBlackTerminal ? Color.black : Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(Color.hairline))
                endedOverlay
            }
        }
        .onAppear(perform: applyAppearance)
        .onChange(of: settings.terminalFontName) { _, _ in applyAppearance() }
        .onChange(of: settings.terminalFontSize) { _, _ in applyAppearance() }
        .onChange(of: settings.forceBlackTerminal) { _, _ in applyAppearance() }
        .onChange(of: colorScheme) { _, _ in applyAppearance() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch session.state {
        case .running:
            Label("Connected", systemImage: "circle.fill").foregroundColor(.green)
                .font(.caption).labelStyle(StatusDotLabelStyle())
        case .ended(let code):
            Label(code.map { "Ended (exit \($0))" } ?? "Ended", systemImage: "circle.fill").foregroundColor(.secondary)
                .font(.caption).labelStyle(StatusDotLabelStyle())
        case .failed:
            Label("Not connected", systemImage: "circle.fill").foregroundColor(.red)
                .font(.caption).labelStyle(StatusDotLabelStyle())
        case .idle:
            Label("Not started", systemImage: "circle.fill").foregroundColor(.secondary)
                .font(.caption).labelStyle(StatusDotLabelStyle())
        }
    }

    @ViewBuilder
    private var endedOverlay: some View {
        switch session.state {
        case .ended, .failed:
            VStack(spacing: 10) {
                if case .failed(let message) = session.state {
                    Text(message).font(.callout).foregroundColor(.secondary).multilineTextAlignment(.center)
                } else {
                    Text("The session has ended.").font(.callout).foregroundColor(.secondary)
                }
                Button("Start New Session") { session.start(arguments: startArguments()) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.card))
        default:
            EmptyView()
        }
    }

    private func applyAppearance() {
        session.applyAppearance(fontName: settings.terminalFontName,
                                fontSize: settings.terminalFontSize,
                                forceBlack: settings.forceBlackTerminal)
    }
}

/// Small colored dot + text.
private struct StatusDotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title.foregroundColor(.secondary)
        }
    }
}
