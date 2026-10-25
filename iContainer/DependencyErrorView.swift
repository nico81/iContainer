import SwiftUI

/// Shown instead of the main window while Apple's `container` CLI can't be
/// found. Offers the in-app install (same verified package flow as the
/// updater), a custom path in Settings, or Homebrew — and re-checks on its
/// own so an install done elsewhere is picked up without a relaunch.
struct DependencyErrorView: View {
    let errors: [DependencyError]
    /// Opens the install sheet.
    let onInstall: () -> Void

    @EnvironmentObject private var containerManager: ContainerizationWrapper
    @EnvironmentObject private var updater: ContainerCLIUpdater
    @Environment(\.openWindow) private var openWindow

    @State private var plan: ContainerCLIUpdater.Plan?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(spacing: 8) {
                    Text("Install Apple's container CLI")
                        .font(.largeTitle.weight(.semibold))
                    Text("iContainer is a native interface for **container**, Apple's open-source tool for running Linux containers on your Mac. It isn't installed yet.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 480)

                VStack(alignment: .leading, spacing: 14) {
                    step("arrow.down.circle", "Downloads the official installer",
                         plan.map { "v\($0.version) · \(ByteCountFormatter.string(fromByteCount: $0.assetSize, countStyle: .file)) from github.com/apple/container" }
                            ?? "From the latest release on github.com/apple/container")
                    step("checkmark.seal", "Verifies it before installing",
                         "Signed by Apple Inc. - Containerization and notarized")
                    step("lock", "Uses macOS's own password prompt",
                         "iContainer never sees your password")
                    step("play.circle", "Starts the container service",
                         "The first start downloads Apple's default Linux kernel")
                }
                .padding(18)
                .frame(maxWidth: 480, alignment: .leading)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.card))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(Color.hairline))

                Button(action: onInstall) {
                    Text("Install container CLI").frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                VStack(spacing: 8) {
                    HStack(spacing: 18) {
                        Button("Check Again") { containerManager.checkDependencies() }
                        Button("Set CLI Path…") { openWindow(id: "settings") }
                        Link("Release Page", destination: ContainerReleaseChecker.releasesPageURL)
                    }
                    .buttonStyle(.link)
                    Text("Prefer Homebrew? Run `brew install container` — iContainer picks it up automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Requires a Mac with Apple silicon.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            plan = try? await updater.preparePlan()
        }
        .task {
            // Pick up an install done outside the app (Homebrew, the .pkg).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                containerManager.checkDependencies()
            }
        }
    }

    private func step(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundColor(.secondary)
            }
        }
    }
}

struct DependencyErrorView_Previews: PreviewProvider {
    static var previews: some View {
        DependencyErrorView(errors: [.cliMissing], onInstall: {})
            .environmentObject(ContainerizationWrapper())
            .environmentObject(ContainerCLIUpdater())
    }
}
