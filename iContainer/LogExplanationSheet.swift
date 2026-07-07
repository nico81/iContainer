import SwiftUI
import AppKit

/// Modal sheet that shows an on-device AI analysis of a container's recent
/// logs. Mirrors `ReleaseNotesSheet`'s chrome and reuses its Markdown
/// rendering; the model work lives in `LogExplainer`.
struct LogExplanationSheet: View {
    /// The container ID or machine name shown under the title.
    let subjectLabel: String
    let logs: String
    let onClose: () -> Void

    @StateObject private var explainer = LogExplainer()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 520)
        .onAppear { explainer.explain(logs: logs) }
        .onDisappear { explainer.cancel() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.appleIntelligence)
                    Text("Log Analysis")
                        .font(.title2.weight(.semibold))
                }
                Text(subjectLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let error = explainer.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if explainer.explanation.isEmpty && explainer.isExplaining {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Analyzing logs on-device…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                } else {
                    renderedMarkdown(explainer.explanation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("Runs entirely on-device. AI-generated — may be inaccurate.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                explainer.explain(logs: logs)
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .disabled(explainer.isExplaining)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(explainer.explanation, forType: .string)
            }
            .disabled(explainer.explanation.isEmpty)
        }
        .padding(20)
    }

    /// Same Markdown treatment as `ReleaseNotesSheet`: inline styling with
    /// whitespace preserved, so bullet markers and line breaks in the
    /// model's report survive. Falls back to plain text on parse failure.
    @ViewBuilder
    private func renderedMarkdown(_ raw: String) -> some View {
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
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
