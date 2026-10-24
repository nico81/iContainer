import SwiftUI

/// "Update container CLI" sheet: shows the plan (version, package, install
/// method, what gets stopped), then drives `ContainerCLIUpdater` with live
/// progress and a log.
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

    private var runningContainers: [Container] { containerManager.containers.filter { $0.status == .running } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Update Apple container CLI").font(.headline)

            if let plan {
                planSummary(plan)
                if let notes = releaseChecker.latestReleaseNotes, releaseChecker.latestVersion == plan.version {
                    DisclosureGroup(isExpanded: $showingHighlights) {
                        CLIReleaseHighlightsView(notes: notes, maxItems: 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Text("What's new in v\(plan.version)").font(.caption.weight(.semibold))
                            if !notes.breakingItems.isEmpty {
                                Text("\(notes.breakingItems.count) breaking").font(.caption2.weight(.semibold)).foregroundColor(.orange)
                            }
                        }
                    }
                }
            } else if let planError {
                Label(planError, systemImage: "xmark.circle.fill").font(.caption).foregroundColor(.red).textSelection(.enabled)
            } else {
                HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text("Checking the latest release…").font(.caption).foregroundColor(.secondary) }
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
                    .onChange(of: updater.log.count) { _, _ in proxy.scrollTo("END", anchor: .bottom) }
                }
            }

            HStack {
                switch updater.phase {
                case .idle, .failed:
                    Button(updater.phase == .idle ? "Update Now" : "Try Again") { start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(plan == nil)
                case .downloading:
                    ProgressView().scaleEffect(0.8)
                    Button("Cancel") { updater.cancelDownload() }
                case .done:
                    EmptyView()
                default:
                    ProgressView().scaleEffect(0.8)
                    Text("Please wait — the service is being updated.").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Button(updater.phase.isActive ? "Working…" : "Close") { updater.reset(); onClose() }
                    .disabled(updater.phase.isActive)
            }

            Text("Signed Apple package from the official release, verified before install. The password prompt is macOS's own; iContainer never sees it. Same steps as Apple's update-container.sh.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding()
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            guard plan == nil else { return }
            do {
                plan = try await updater.preparePlan()
                if autoStart, updater.phase == .idle, runningContainers.isEmpty { start() }
            } catch { planError = error.localizedDescription }
        }
    }

    private func planSummary(_ plan: ContainerCLIUpdater.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(releaseChecker.installedVersion.map { "v\($0)" } ?? "installed ?").font(.title3.monospacedDigit())
                Image(systemName: "arrow.right").foregroundColor(.secondary)
                Text("v\(plan.version)").font(.title3.monospacedDigit().weight(.semibold))
                Spacer()
                Text(plan.method.label).font(.caption).foregroundColor(.secondary)
            }
            if case .package = plan.method {
                Text("\(plan.assetName) · \(ByteCountFormatter.string(fromByteCount: plan.assetSize, countStyle: .file))")
                    .font(.caption.monospaced()).foregroundColor(.secondary)
            }
            if case .unknown = plan.method {
                Label("Couldn't tell how the CLI was installed; the installer package will be used (it installs under /usr/local).", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange)
            }
            if runningContainers.isEmpty {
                Text("No containers are running; the service is stopped and started again.").font(.caption).foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Stopping the service stops \(runningContainers.count) running container\(runningContainers.count == 1 ? "" : "s"): \(runningContainers.map(\.name).joined(separator: ", ")). Press Update Now to confirm.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundColor(.orange)
                    Toggle("Start them again after the update", isOn: $restartContainers).toggleStyle(.checkbox).font(.caption)
                        .disabled(updater.phase.isActive)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    @ViewBuilder
    private var progressView: some View {
        switch updater.phase {
        case .idle:
            EmptyView()
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloading…").font(.caption)
                if let fraction { ProgressView(value: fraction) } else { ProgressView() }
            }
        case .verifying: phaseLine("Verifying signature…")
        case .stoppingService: phaseLine("Stopping the container service…")
        case .installing: phaseLine("Installing — enter your administrator password in the macOS prompt.")
        case .startingService: phaseLine("Starting the container service…")
        case .restartingContainers: phaseLine("Restarting containers…")
        case .done(let version):
            Label("Updated to v\(version).", systemImage: "checkmark.circle.fill").foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundColor(.red).font(.caption).textSelection(.enabled)
        }
    }

    private func phaseLine(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().scaleEffect(0.7); Text(text).font(.caption) }
    }

    private func start() {
        guard let plan else { return }
        Task {
            await updater.run(plan: plan, serviceManager: serviceManager, containerManager: containerManager, restartContainers: restartContainers)
            if case .done = updater.phase { await releaseChecker.checkForUpdateIfNeeded(force: true) }
        }
    }
}
