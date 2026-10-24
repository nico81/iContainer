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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple container \(version)").font(.title2.weight(.semibold))
                if let installedVersion {
                    Text("Installed v\(installedVersion)").font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let notes, !notes.isEmpty {
                        if !notes.breakingItems.isEmpty {
                            Label("This release has \(notes.breakingItems.count) breaking change\(notes.breakingItems.count == 1 ? "" : "s"), marked below.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Highlights").font(.headline)
                            CLIReleaseHighlightsView(notes: notes)
                        }
                        if !notes.changes.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("What's Changed").font(.headline)
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
                    } else {
                        Text("Release notes aren't available. Open the release on GitHub to read them.")
                            .font(.callout).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()

            HStack {
                if let releaseURL {
                    Button("View on GitHub") { openURL(releaseURL) }
                }
                Spacer()
                Button("Close", action: onClose).keyboardShortcut(.escape, modifiers: [])
                if let onUpdate {
                    Button("Update Now") { onClose(); onUpdate() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 600, height: 520)
    }
}
