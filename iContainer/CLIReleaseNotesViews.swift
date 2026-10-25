import SwiftUI

/// Compact list of a container CLI release's highlights, grouped by area.
/// Breaking changes (⌨️ CLI / 👩‍💻 API in Apple's notes) are flagged in
/// orange so they're impossible to miss before updating. Items link to their
/// pull request.
struct CLIReleaseHighlightsView: View {
    let notes: CLIReleaseNotes
    /// Show at most this many items; `nil` = all.
    var maxItems: Int? = nil

    @Environment(\.openURL) private var openURL

    private var visibleGroups: [CLIReleaseNotes.Group] {
        guard let maxItems else { return notes.highlights }
        var remaining = maxItems
        var result: [CLIReleaseNotes.Group] = []
        // Breaking items first so truncation never hides them.
        let ordered = notes.highlights.map { group in
            CLIReleaseNotes.Group(title: group.title, items: group.items.filter(\.isBreaking) + group.items.filter { !$0.isBreaking })
        }
        for group in ordered where remaining > 0 {
            let items = Array(group.items.prefix(remaining))
            remaining -= items.count
            if !items.isEmpty { result.append(.init(title: group.title, items: items)) }
        }
        return result
    }

    private var hiddenCount: Int {
        notes.highlightCount - visibleGroups.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if notes.highlights.isEmpty {
                Text("No highlights in the release notes.").font(.caption).foregroundColor(.secondary)
            }
            ForEach(visibleGroups) { group in
                VStack(alignment: .leading, spacing: 3) {
                    if let title = group.title {
                        Text(title.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    ForEach(group.items) { item in
                        itemRow(item)
                    }
                }
            }
            if hiddenCount > 0 {
                Text("+ \(hiddenCount) more")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func itemRow(_ item: CLIReleaseNotes.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•").foregroundColor(.secondary)
            Group {
                if let url = item.url {
                    Button { openURL(url) } label: { markdown(item.text) }
                        .buttonStyle(.plain)
                        .help(url.absoluteString)
                } else {
                    markdown(item.text)
                }
            }
            if item.isBreakingCLI { breakingBadge("breaking CLI") }
            if item.isBreakingAPI { breakingBadge("breaking API") }
        }
        .font(.caption)
    }

    private func markdown(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) { return Text(attributed) }
        return Text(text)
    }

    private func breakingBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.15), in: Capsule())
    }
}

/// Header shared by the CLI sheets (install / update / release notes).
struct CLISheetHeader: View {
    let title: String
    var subtitle: String = "From the official apple/container release on GitHub"

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor], startPoint: .top, endPoint: .bottom),
                            in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.callout).foregroundColor(.secondary)
            }
        }
    }
}

/// "INSTALLED v1.6.0 → LATEST v1.6.1".
struct CLIVersionTransition: View {
    let fromLabel: String
    let fromValue: String
    let toLabel: String
    let toValue: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            block(fromLabel, fromValue, emphasized: false)
            Image(systemName: "arrow.right").font(.title3).foregroundColor(.secondary)
            block(toLabel, toValue, emphasized: true)
            Spacer(minLength: 0)
        }
    }

    private func block(_ label: String, _ value: String, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundColor(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(emphasized ? .semibold : .regular))
                .foregroundColor(emphasized ? .accentColor : .secondary)
        }
    }
}

extension View {
    /// The tinted, hairline-outlined box the CLI sheets group content in.
    func cliSheetCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(Color.hairline))
    }
}

/// Full release notes for a container CLI version: highlights (all of them)
/// and the "What's Changed" list, with Update Now and a GitHub link.
struct CLIReleaseNotesSheet: View {
    let version: String
    let installedVersion: String?
    let notes: CLIReleaseNotes?
    let releaseURL: URL?
    /// `nil` hides the Update Now button (e.g. already up to date).
    let onUpdate: (() -> Void)?
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CLISheetHeader(title: "What's new in container \(version)", subtitle: "Release notes from apple/container on GitHub")

            CLIVersionTransition(
                fromLabel: "Installed", fromValue: installedVersion.map { "v\($0)" } ?? "None",
                toLabel: "Latest", toValue: "v\(version)"
            )
            .cliSheetCard()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let notes, !notes.isEmpty {
                        if !notes.breakingItems.isEmpty {
                            Label("This release has \(notes.breakingItems.count) breaking change\(notes.breakingItems.count == 1 ? "" : "s"), marked below.", systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundColor(.orange)
                        }
                        if !notes.highlights.isEmpty {
                            section("Highlights", symbol: "sparkles") {
                                CLIReleaseHighlightsView(notes: notes)
                            }
                        }
                        if !notes.changes.isEmpty {
                            section("What's Changed", symbol: "list.bullet") {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(notes.changes) { change in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text("•").foregroundColor(.secondary)
                                            if let url = change.url {
                                                Button(change.title) { openURL(url) }.buttonStyle(.plain)
                                            } else {
                                                Text(change.title)
                                            }
                                            if let author = change.author {
                                                Text("@\(author)").foregroundColor(.secondary)
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Release notes aren't available. Open the release on GitHub to read them.")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 340)

            Divider()

            HStack(spacing: 10) {
                if let releaseURL {
                    Button {
                        openURL(releaseURL)
                    } label: {
                        Label("View on GitHub", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.link)
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(onUpdate == nil ? .defaultAction : .cancelAction)
                if let onUpdate {
                    Button("Update Now") { onClose(); onUpdate() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 600)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .cliSheetCard()
    }
}
