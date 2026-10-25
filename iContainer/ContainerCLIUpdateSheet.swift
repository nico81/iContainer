import SwiftUI

/// "Update container CLI" sheet: shows the plan (version, package, install
/// method, what gets stopped), then drives `ContainerCLIUpdater` with live
/// progress and a log. With no CLI on the Mac it becomes the installer.
struct ContainerCLIUpdateSheet: View {
    @EnvironmentObject var updater: ContainerCLIUpdater
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var releaseChecker: ContainerReleaseChecker
    /// Start as soon as the plan is ready. Ignored when running containers
    /// would be stopped: that case waits for an explicit confirmation.
    var autoStart = false
    let onClose: () -> Void

    @State private var plan: ContainerCLIUpdater.Plan?
    @State private var planError: String?
    @State private var restartContainers = true
    @State private var showingHighlights = true
    /// Decided once when the sheet opens; the CLI appears mid-run.
    @State private var isFreshInstall = SettingsManager.resolvedContainerCLIPath() == nil

    private var runningContainers: [Container] { containerManager.containers.filter { $0.status == .running } }

    private var title: String { isFreshInstall ? "Install Apple container CLI" : "Update Apple container CLI" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CLISheetHeader(title: title)

            if let plan {
                planSummary(plan)
                if !isFreshInstall, let notes = releaseChecker.latestReleaseNotes, releaseChecker.latestVersion == plan.version {
                    DisclosureGroup(isExpanded: $showingHighlights) {
                        CLIReleaseHighlightsView(notes: notes, maxItems: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Text("What's new in v\(plan.version)").font(.callout.weight(.semibold))
                            if !notes.breakingItems.isEmpty {
                                Text("\(notes.breakingItems.count) breaking").font(.caption2.weight(.semibold)).foregroundColor(.orange)
                            }
                        }
                    }
                }
            } else if let planError {
                Label(planError, systemImage: "xmark.circle.fill").font(.callout).foregroundColor(.red).textSelection(.enabled)
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking the latest release…").font(.callout).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 80)
            }

            progressView

            if !updater.log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(updater.log.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("END")
                        }
                        .padding(8)
                    }
                    // Grows with the log, caps at ~8 lines.
                    .frame(height: min(CGFloat(updater.log.count) * 17 + 18, 160))
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: AppRadius.small))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(Color.hairline))
                    .onChange(of: updater.log.count) { _, _ in proxy.scrollTo("END", anchor: .bottom) }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "lock.shield")
                Text(isFreshInstall
                     ? "Signed Apple package from the official release, verified before install. The password prompt is macOS's own; iContainer never sees it."
                     : "Signed Apple package from the official release, verified before install. The password prompt is macOS's own; iContainer never sees it. Same steps as Apple's update-container.sh.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Divider()

            HStack(spacing: 10) {
                switch updater.phase {
                case .downloading:
                    Button("Cancel Download") { updater.cancelDownload() }
                case .idle, .failed, .done:
                    EmptyView()
                default:
                    Text(isFreshInstall ? "Please wait — the CLI is being installed." : "Please wait — the service is being updated.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(updater.phase.isActive ? "Working…" : (isDone ? "Done" : "Close")) { updater.reset(); onClose() }
                    .disabled(updater.phase.isActive)
                    .keyboardShortcut(isDone ? .defaultAction : .cancelAction)
                switch updater.phase {
                case .idle, .failed:
                    Button(updater.phase == .idle ? (isFreshInstall ? "Install" : "Update Now") : "Try Again") { start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(plan == nil)
                default:
                    EmptyView()
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            guard plan == nil else { return }
            do {
                plan = try await updater.preparePlan()
                // A fresh install has nothing running to confirm about (the
                // container list may still hold entries from before the CLI
                // was removed).
                if autoStart, updater.phase == .idle, isFreshInstall || runningContainers.isEmpty { start() }
            } catch { planError = error.localizedDescription }
        }
    }

    private var isDone: Bool {
        if case .done = updater.phase { return true }
        return false
    }

    private func planSummary(_ plan: ContainerCLIUpdater.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CLIVersionTransition(
                fromLabel: "Installed",
                fromValue: isFreshInstall ? "None" : releaseChecker.installedVersion.map { "v\($0)" } ?? "?",
                toLabel: isFreshInstall ? "Will install" : "Latest",
                toValue: "v\(plan.version)"
            )

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if case .package = plan.method {
                    infoRow("doc.zipper", "\(plan.assetName)", monospaced: true)
                    infoRow("arrow.down.circle", ByteCountFormatter.string(fromByteCount: plan.assetSize, countStyle: .file) + " download")
                }
                infoRow("wrench.and.screwdriver", plan.method.label)
                if isFreshInstall {
                    infoRow("play.circle", "Installs under /usr/local and starts the container service; the first start also downloads Apple's default Linux kernel.")
                } else if runningContainers.isEmpty {
                    infoRow("arrow.clockwise", "No containers are running; the service is stopped and started again.")
                }
            }

            if case .unknown = plan.method {
                Label("Couldn't tell how the CLI was installed; the installer package will be used (it installs under /usr/local).", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundColor(.orange)
            }
            if !isFreshInstall, !runningContainers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Stopping the service stops \(runningContainers.count) running container\(runningContainers.count == 1 ? "" : "s"): \(runningContainers.map(\.name).joined(separator: ", ")). Press Update Now to confirm.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundColor(.orange)
                    Toggle("Start them again after the update", isOn: $restartContainers).toggleStyle(.checkbox)
                        .disabled(updater.phase.isActive)
                }
            }
        }
        .cliSheetCard()
    }

    private func infoRow(_ symbol: String, _ text: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundColor(.secondary).frame(width: 16)
            Text(text)
                .font(monospaced ? .callout.monospaced() : .callout)
                .foregroundColor(monospaced ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Downloading…").font(.callout)
                    Spacer()
                    if let fraction { Text("\(Int(fraction * 100))%").font(.callout.monospacedDigit()).foregroundColor(.secondary) }
                }
                if let fraction { ProgressView(value: fraction) } else { ProgressView().progressViewStyle(.linear) }
            }
        case .verifying: phaseLine("Verifying signature…")
        case .stoppingService: phaseLine("Stopping the container service…")
        case .installing: phaseLine("Installing — enter your administrator password in the macOS prompt.")
        case .startingService: phaseLine("Starting the container service…")
        case .restartingContainers: phaseLine("Restarting containers…")
        case .done(let version):
            Label(isFreshInstall ? "Installed v\(version). The container service is running." : "Updated to v\(version).", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundColor(.red).font(.callout).textSelection(.enabled)
        }
    }

    private func phaseLine(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text).font(.callout) }
    }

    private func start() {
        guard let plan else { return }
        Task {
            await updater.run(plan: plan, serviceManager: serviceManager, containerManager: containerManager, restartContainers: restartContainers)
            if case .done = updater.phase { await releaseChecker.checkForUpdateIfNeeded(force: true) }
        }
    }
}
