import SwiftUI

/// Shared visual chrome for the container detail tabs (Info, Stats,
/// Shell, Logs). Centralised here so each tab file can stay focused on
/// its own content.

enum InfoTextStyle {
    static let labelFont = Font.caption
    static let valueFont = Font.body
    static let monospacedValueFont = Font.caption.monospaced()
}

/// Card-styled section with an SF Symbol icon, title and a vertical
/// stack of rows. Used as the top-level grouping element in every
/// detail tab.
struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.leading, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(AppRadius.card)
        .cardOutline(AppRadius.card)
    }
}

/// Label-over-value row used inside a `DetailSection`. Pass
/// `isMonospaced: true` for things like paths, commands, or any value
/// that benefits from a fixed-width font.
struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(InfoTextStyle.labelFont)
                .foregroundColor(.secondary)
                .fontWeight(.medium)
            Text(value)
                .font(isMonospaced ? InfoTextStyle.monospacedValueFont : InfoTextStyle.valueFont)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

/// Small coloured pill that shows "running" / "stopped" / etc next to
/// the container name in the header.
struct StatusBadge: View {
    let status: String

    var color: Color {
        status.lowercased() == "running" ? .green : .red
    }

    var body: some View {
        Text(status.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(AppRadius.small)
    }
}
