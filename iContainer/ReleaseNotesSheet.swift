import SwiftUI

/// Modal sheet that renders the GitHub release notes returned by
/// `AppReleaseChecker`. The body is plain markdown — SwiftUI's
/// `AttributedString(markdown:)` handles links, lists, emphasis, etc.
/// Falls back to a plain-text view if parsing fails.
struct ReleaseNotesSheet: View {
    let title: String
    let version: String?
    let notes: String?
    let downloadURL: URL?
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    if let version {
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Close", action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let notes, !notes.isEmpty {
                        renderedNotes(notes)
                    } else {
                        Text("No release notes are available for this version.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                if let downloadURL {
                    Button("Download") {
                        openURL(downloadURL)
                        onClose()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private func renderedNotes(_ raw: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            Text(attributed)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(raw)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
