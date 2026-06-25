import SwiftUI
import AppKit

/// "Logs" tab of the container detail view.
///
/// Polls `container logs <id> --tail N` on a 3 s timer when the tab is
/// active and appends only new lines (computed via longest-common-prefix
/// against the previous snapshot). RFC 3339 timestamps in each line are
/// parsed so the user-driven "Clear" button can hide everything older
/// than the clear instant.
struct ContainerLogsView: View {
    let details: ContainerDetails?
    let containerId: String
    let isActive: Bool
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var logAccumulator = ContainerLogAccumulator()
    @State private var isLoadingLogs = false
    /// Single "Follow" toggle. When on: poll for new lines every refresh
    /// interval AND keep the scroll pinned to the latest entry. When off:
    /// no polling, no auto-scroll — the user reads what they have and
    /// presses Refresh manually. Replaces the previous Auto Refresh /
    /// Auto Scroll pair, which always moved together in practice.
    @State private var isFollowing = true
    @State private var filterText = ""
    @State private var refreshTask: Task<Void, Never>?
    private let tailLines: Int = 200

    private let refreshIntervalNanos: UInt64 = 3_000_000_000

    var body: some View {
        GeometryReader { proxy in
            let logAreaHeight = max(240, proxy.size.height - 220)
            VStack(alignment: .leading, spacing: 24) {
                if let details = details {
                    ContainerHeaderView(details: details)
                } else {
                    ProgressView("Loading Details...")
                        .padding(.top, 12)
                }
                DetailSection(title: "Logs", icon: "doc.plaintext") {
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Filter", text: $filterText)
                                .textFieldStyle(.roundedBorder)
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                                .opacity(isLoadingLogs ? 1 : 0)
                            Toggle("Follow", isOn: $isFollowing)
                                .toggleStyle(.switch)
                            Button("Refresh") {
                                Task { await refreshLogs() }
                            }
                            .disabled(isLoadingLogs || isFollowing)
                            Button("Clear") {
                                logAccumulator.clear(at: Date())
                            }
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(filteredLogs, forType: .string)
                            }
                        }

                        ScrollViewReader { proxy in
                            let s = SettingsManager.shared
                            ScrollView {
                                Text(filteredLogs.isEmpty ? "No logs yet." : filteredLogs)
                                    .font(.custom(s.terminalFontName, size: s.terminalFontSize, relativeTo: .body).monospaced())
                                    .foregroundColor(s.forceBlackTerminal ? .white : nil)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(s.forceBlackTerminal ? 8 : 0)
                                Color.clear
                                    .frame(height: 1)
                                    .id("BOTTOM")
                            }
                            .frame(height: logAreaHeight)
                            .background(s.forceBlackTerminal ? Color.black : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: s.forceBlackTerminal ? AppRadius.small : 0))
                            .onChange(of: logAccumulator.text) { _, _ in
                                guard isFollowing else { return }
                                proxy.scrollTo("BOTTOM", anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { startAutoRefresh() }
        .onDisappear { stopAutoRefresh() }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }

    private var filteredLogs: String {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return logAccumulator.text }
        return logAccumulator.text
            .components(separatedBy: .newlines)
            .filter { $0.localizedCaseInsensitiveContains(trimmed) }
            .joined(separator: "\n")
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        guard isActive else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                if isFollowing {
                    await refreshLogs()
                }
                try? await Task.sleep(nanoseconds: refreshIntervalNanos)
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refreshLogs() async {
        isLoadingLogs = true
        defer { isLoadingLogs = false }
        if let output = await containerManager.fetchContainerLogs(containerId: containerId, tail: tailLines) {
            logAccumulator.ingest(output)
        } else {
            logAccumulator.replaceWithUnavailableMessage()
        }
    }
}
