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
