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
    @State private var logsText: String = ""
    @State private var isLoadingLogs = false
    /// Single "Follow" toggle. When on: poll for new lines every refresh
    /// interval AND keep the scroll pinned to the latest entry. When off:
    /// no polling, no auto-scroll — the user reads what they have and
    /// presses Refresh manually. Replaces the previous Auto Refresh /
    /// Auto Scroll pair, which always moved together in practice.
    @State private var isFollowing = true
    @State private var filterText = ""
    @State private var lastClearDate: Date = .distantPast
    @State private var lastSnapshotLines: [String] = []
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
                            if isLoadingLogs {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Toggle("Follow", isOn: $isFollowing)
                                .toggleStyle(.switch)
                            Button("Refresh") {
                                Task { await refreshLogs() }
                            }
                            .disabled(isLoadingLogs || isFollowing)
                            Button("Clear") {
                                logsText = ""
                                lastClearDate = Date()
                                lastSnapshotLines.removeAll()
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
                            .onChange(of: logsText) { _, _ in
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
        guard !trimmed.isEmpty else { return logsText }
        return logsText
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
        if let output = await containerManager.fetchContainerLogs(containerId: containerId, tail: tailLines) {
            let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let lines = cleaned
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }
                .filter { line in
                    lineTimestamp(line) >= lastClearDate
                }
            if lastSnapshotLines.isEmpty && logsText.isEmpty {
                lastSnapshotLines = lines
                return
            }
            let delta = deltaLines(previous: lastSnapshotLines, current: lines)
            if !delta.isEmpty {
                if logsText.isEmpty {
                    logsText = delta.joined(separator: "\n")
                } else {
                    logsText += "\n" + delta.joined(separator: "\n")
                }
            }
            lastSnapshotLines = lines
        } else {
            logsText = "No logs available."
        }
        isLoadingLogs = false
    }

    private func deltaLines(previous: [String], current: [String]) -> [String] {
        let prefixCount = commonPrefixCount(previous, current)
        if prefixCount < current.count {
            return Array(current.dropFirst(prefixCount))
        }
        return []
    }

    private func commonPrefixCount(_ a: [String], _ b: [String]) -> Int {
        let count = min(a.count, b.count)
        var idx = 0
        while idx < count, a[idx] == b[idx] {
            idx += 1
        }
        return idx
    }

    private func lineTimestamp(_ line: String) -> Date {
        if let parsed = parseRFC3339(line) {
            return parsed
        }
        return lastClearDate
    }

    private func parseRFC3339(_ line: String) -> Date? {
        let pattern = #"^\s*(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z)\s"#
        guard let match = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let token = String(line[match]).trimmingCharacters(in: .whitespaces)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: token) {
            return date
        }
        let isoNoFrac = ISO8601DateFormatter()
        isoNoFrac.formatOptions = [.withInternetDateTime]
        return isoNoFrac.date(from: token)
    }
}
