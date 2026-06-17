import SwiftUI

/// The "home" screen shown when no sidebar item is selected.
///
/// Pure presentation: it receives the data it needs and surfaces user
/// actions through closures. Owned by `ContentView`.
struct WelcomeDashboardView: View {
    let containers: [Container]
    let imageCount: Int
    let isServiceRunning: Bool
    let onCreateContainer: () -> Void
    let onPullImage: () -> Void
    let onShowService: () -> Void
    let onSelectContainer: (Container) -> Void

    @EnvironmentObject private var releaseChecker: ContainerReleaseChecker
    @EnvironmentObject private var appReleaseChecker: AppReleaseChecker
    @State private var showingAppReleaseNotes: Bool = false

    private var runningContainers: [Container] {
        containers.filter { $0.status == .running }
    }

    private var stoppedContainers: [Container] {
        containers.filter { $0.status == .stopped }
    }

    private var previewContainers: [Container] {
        (runningContainers + stoppedContainers).prefix(5).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if appReleaseChecker.isUpdateAvailable {
                    appUpdateAvailableBanner
                }
                if releaseChecker.isUpdateAvailable {
                    updateAvailableBanner
                }
                metrics
                actions
                containerPreview
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showingAppReleaseNotes) {
            ReleaseNotesSheet(
                title: appReleaseChecker.latestReleaseName ?? "What's new in iContainer",
                version: appReleaseChecker.latestVersion,
                notes: appReleaseChecker.latestReleaseNotes,
                downloadURL: appReleaseChecker.latestReleaseURL ?? AppReleaseChecker.releasesPageURL,
                onClose: { showingAppReleaseNotes = false }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image("LogoHome")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                (Text("i").foregroundColor(.accentColor) + Text("Container"))
                    .font(.system(size: 34, weight: .semibold))
                HStack(spacing: 8) {
                    StatusDot(isRunning: isServiceRunning)
                    Text("Apple container service")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Text(AppVersion.displayString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var appUpdateAvailableBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of iContainer is available")
                    .font(.subheadline.weight(.semibold))
                if let latest = appReleaseChecker.latestVersion {
                    Text("Installed v\(appReleaseChecker.installedVersion) · Latest v\(latest)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 12) {
                    Link(
                        "Download latest release",
                        destination: appReleaseChecker.latestReleaseURL ?? AppReleaseChecker.releasesPageURL
                    )
                    Button("What's new") {
                        showingAppReleaseNotes = true
                    }
                    .buttonStyle(.link)
                }
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var updateAvailableBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("A new version of the Apple container service is available")
                    .font(.subheadline.weight(.semibold))
                if let latest = releaseChecker.latestVersion {
                    let installed = releaseChecker.installedVersion ?? "?"
                    Text("Installed v\(installed) · Latest v\(latest)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Link(
                    "Download latest release",
                    destination: releaseChecker.latestReleaseURL ?? ContainerReleaseChecker.releasesPageURL
                )
                .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            WelcomeMetricTile(title: "Containers", value: containers.count, systemImage: "shippingbox")
            WelcomeMetricTile(title: "Running", value: runningContainers.count, systemImage: "play.circle")
            WelcomeMetricTile(title: "Stopped", value: stoppedContainers.count, systemImage: "stop.circle")
            WelcomeMetricTile(title: "Images", value: imageCount, systemImage: "square.stack.3d.up")
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(action: onCreateContainer) {
                Label("Create Container", systemImage: "plus")
            }
            .actionButtonStyle(prominent: true)
            .controlSize(.large)
            .disabled(!isServiceRunning)

            Button(action: onPullImage) {
                Label("Pull Image", systemImage: "square.and.arrow.down")
            }
            .actionButtonStyle()
            .controlSize(.large)
            .disabled(!isServiceRunning)

            if isServiceRunning {
                Button(action: onShowService) {
                    Label("Apple container service details", systemImage: "server.rack")
                }
                .actionButtonStyle()
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    private var containerPreview: some View {
        if previewContainers.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("No containers yet", systemImage: "shippingbox")
                    .font(.headline)
                Text(isServiceRunning ? "Create a container or pull an image to start." : "Start the container service to create and manage containers.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Available Containers")
                    .font(.headline)

                VStack(spacing: 0) {
                    ForEach(previewContainers) { container in
                        Button {
                            onSelectContainer(container)
                        } label: {
                            WelcomeContainerRow(container: container)
                        }
                        .buttonStyle(.plain)

                        if container.id != previewContainers.last?.id {
                            Divider()
                                .padding(.leading, 28)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small))
            }
        }
    }
}

private struct WelcomeMetricTile: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

private struct WelcomeContainerRow: View {
    let container: Container

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(isRunning: container.status == .running)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(container.image ?? "No image")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let ipAddress = container.ipAddress {
                Text(ipAddress)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
