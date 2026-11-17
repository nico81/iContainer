import SwiftUI

/// Centralised visual tokens. These values already lived (inconsistently)
/// across the views; collecting them here gives corner radii, the hairline
/// outline and the running/stopped dot a single source of truth so the UI
/// stays pixel-consistent and future tweaks happen in one place.

/// Corner radii. Just two: a large radius for top-level bordered cards and
/// a small one for everything nested or smaller (tiles, panels, badges,
/// terminals).
enum AppRadius {
    static let card: CGFloat = 12
    static let small: CGFloat = 8
}

extension Color {
    /// The hairline outline drawn around cards, panels and boxes.
    static let hairline = Color.gray.opacity(0.2)
}

extension ShapeStyle where Self == LinearGradient {
    /// The multicolour "Apple Intelligence" wash used to tint AI affordances —
    /// the ✨ on the log-analysis button and its sheet header. A diagonal
    /// pink → purple → blue → cyan gradient in the familiar Apple Intelligence
    /// palette. Usable anywhere a `ShapeStyle` is expected, e.g.
    /// `Image(systemName: "sparkles").foregroundStyle(.appleIntelligence)`.
    static var appleIntelligence: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.24, blue: 0.53),  // pink
                Color(red: 0.68, green: 0.31, blue: 0.93),  // purple
                Color(red: 0.33, green: 0.44, blue: 0.96),  // blue
                Color(red: 0.28, green: 0.79, blue: 1.00)   // cyan
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    /// Standard 1pt hairline outline, matching the given corner radius.
    /// Replaces the ad-hoc `.overlay(RoundedRectangle(...).stroke(...))`
    /// that was repeated with slightly different opacities.
    func cardOutline(_ radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.hairline, lineWidth: 1)
        )
    }

    /// Button style for primary/inline action buttons: the standard
    /// bordered style. `prominent` picks the emphasised variant (used for
    /// the main call-to-action); `circular` rounds the button into a circle
    /// — intended for icon-only action buttons.
    @ViewBuilder
    func actionButtonStyle(prominent: Bool = false, circular: Bool = false) -> some View {
        let shaped = buttonBorderShape(circular ? .circle : .automatic)
        if prominent {
            shaped.buttonStyle(.borderedProminent)
        } else {
            shaped.buttonStyle(.bordered)
        }
    }
}

/// The tab switcher used in the detail toolbars. A custom segmented control
/// because the native one can't be tinted: SwiftUI's `.segmented` picker
/// ignores `.tint` for its selection, and `NSSegmentedControl`'s
/// `selectedSegmentBezelColor` is overridden by Liquid Glass. This renders
/// only the segments and the accent-filled selected pill (no separators, no
/// own track) — the single outer border is the toolbar's own glass capsule,
/// so the bar has one outline with just the pill moving inside.
/// `selection` is an `Int` tag matching the order of `labels`.
struct AccentTabPicker: View {
    @Binding var selection: Int
    let labels: [String]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let isSelected = index == selection
                Button {
                    selection = index
                } label: {
                    Text(label)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .contentShape(Capsule())
                        .background {
                            if isSelected {
                                Capsule().fill(Color.accentColor)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        // Inset the segment row inside the toolbar's glass capsule so the
        // selected pill keeps an even margin from the outer border on every
        // side — including the first/last segment, which would otherwise
        // touch the edge.
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }
}

/// The running/stopped indicator dot. One definition for the sidebar
/// service row, the container rows and the welcome dashboard — only the
/// `size` varies (14 for the prominent service row, 10 elsewhere).
struct StatusDot: View {
    let isRunning: Bool
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(isRunning ? Color.green : Color.red)
            .brightness(isRunning ? 0.15 : 0.05)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 0)
    }
}

/// Bottom bar shared by the app's sheets, in the macOS order used by the
/// container CLI sheets: an optional note, a hairline, then secondary
/// actions on the leading edge and Close + the primary (default) action on
/// the trailing edge. `note` is parsed as Markdown, so `code` spans render.
struct SheetActionBar<Secondary: View>: View {
    var note: String? = nil
    let primaryTitle: String
    var primaryDisabled = false
    var isWorking = false
    var closeTitle = "Close"
    var closeDisabled = false
    let onPrimary: () -> Void
    let onClose: () -> Void
    @ViewBuilder var secondary: () -> Secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let note {
                Text(LocalizedStringKey(note))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 10) {
                secondary()
                Spacer()
                if isWorking { ProgressView().controlSize(.small) }
                Button(closeTitle, action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .disabled(closeDisabled)
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryDisabled)
            }
            .controlSize(.large)
        }
    }
}

extension SheetActionBar where Secondary == EmptyView {
    init(note: String? = nil, primaryTitle: String, primaryDisabled: Bool = false, isWorking: Bool = false,
         closeTitle: String = "Close", closeDisabled: Bool = false,
         onPrimary: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.init(note: note, primaryTitle: primaryTitle, primaryDisabled: primaryDisabled, isWorking: isWorking,
                  closeTitle: closeTitle, closeDisabled: closeDisabled, onPrimary: onPrimary, onClose: onClose,
                  secondary: { EmptyView() })
    }
}

/// A sheet whose form scrolls while the action bar stays pinned at the
/// bottom, so Create/Close never scroll away or float mid-sheet.
struct ScrollingSheet<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            footer()
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
}
