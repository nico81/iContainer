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

    /// Button style for primary/inline action buttons. When `glass` is on
    /// (the `settings.glassButtons` preference) it uses the Liquid Glass
    /// style; otherwise it falls back to the standard bordered style for
    /// higher contrast and usability. `prominent` picks the emphasised
    /// variant (used for the main call-to-action).
    @ViewBuilder
    func actionButtonStyle(prominent: Bool = false, glass: Bool) -> some View {
        if glass {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
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
