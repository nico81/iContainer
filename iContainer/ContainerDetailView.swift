import SwiftUI
import Charts
import Combine
import AppKit

struct ContainerDetailView: View {
    let containerId: String
    let initialTab: Int
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var details: ContainerDetails?
    @State private var isLoading = true
    @State private var rawInspectText: String = ""
    @State private var fallback: ContainerInspectFallback?
    @State private var selectedTab: Int

    init(containerId: String, initialTab: Int = 0) {
        self.containerId = containerId
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    /// Named volumes this container mounts (from the live list). Drives the
    /// optional "Volumes" tab.
    private var volumeMounts: [VolumeMount] {
        containerManager.containers.first(where: { $0.id == containerId })?.volumeMounts ?? []
    }

    private var tabLabels: [String] {
        var labels = ["Info", "Stats", "Shell", "Logs"]
        if !volumeMounts.isEmpty { labels.append("Volumes") }
        return labels
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0:
                    ContainerInfoView(
                        details: details,
                        fallback: fallback,
                        isLoading: isLoading,
                        formattedInspectOutput: formattedInspectOutput,
                        onBrowseVolumes: volumeMounts.isEmpty ? nil : { selectedTab = 4 }
                    )

                case 1:
                    ContainerStatsView(
                        details: details,
                        containerId: containerId,
                        cpuLimit: fallback?.resources?.cpus
                    )

                case 2:
                    ContainerShellView(
                        details: details,
                        containerId: containerId
                    )

                case 3:
                    ContainerLogsView(
                        details: details,
                        containerId: containerId,
                        isActive: true
                    )

                case 4:
                    ContainerVolumesView(
                        details: details,
                        containerId: containerId,
                        volumeMounts: volumeMounts
                    )

                default:
                    EmptyView()
                }
            }
        }
        // Empty navigation title: the section name shows as the large
        // in-content header instead, so a titlebar title would just
        // duplicate it. Tab switcher lives in the toolbar (control layer).
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                AccentTabPicker(selection: $selectedTab, labels: tabLabels)
                    .frame(width: volumeMounts.isEmpty ? 320 : 400)
            }
        }
        .task(id: containerId) {
            await loadDetails()
        }
        .onChange(of: containerManager.containers) { _, _ in
            Task {
                await loadDetails()
            }
            // The Volumes tab disappears with its last volume (e.g. after a
            // recreate); don't leave the picker pointing at nothing.
            if selectedTab == 4 && volumeMounts.isEmpty { selectedTab = 0 }
        }
    }

    private func loadDetails() async {
        details = await containerManager.inspectContainer(containerId: containerId)
        if let raw = await containerManager.inspectContainerRaw(containerId: containerId) {
            rawInspectText = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            fallback = parseContainerInspect(rawInspectText)
        } else {
            rawInspectText = ""
            fallback = nil
        }
        isLoading = false
        updateDetailsFromList()
    }

    private func updateDetailsFromList() {
        guard let current = details,
              let match = containerManager.containers.first(where: { $0.id == containerId }) else {
            return
        }
        let statusText = match.status == .running ? "running" : "stopped"
        let updatedNetworks: [ContainerDetails.NetworkInfo]? = match.ipAddress != nil
            ? [ContainerDetails.NetworkInfo(address: match.ipAddress)]
            : current.networks
        let updatedImage: ContainerDetails.ImageInfo? = match.image != nil
            ? ContainerDetails.ImageInfo(reference: match.image)
            : current.configuration?.image
        let updatedConfiguration = ContainerDetails.ConfigurationData(
            id: current.configuration?.id,
            hostname: current.configuration?.hostname,
            image: updatedImage,
            mounts: current.configuration?.mounts,
            initProcess: current.configuration?.initProcess,
            publishedSockets: current.configuration?.publishedSockets
        )
        let updated = ContainerDetails(
            status: statusText,
            networks: updatedNetworks,
            configuration: updatedConfiguration
        )
        if updated != current {
            details = updated
        }
    }

    private var formattedInspectOutput: String {
        let trimmed = rawInspectText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No details available." }
        guard let data = trimmed.data(using: .utf8) else { return trimmed }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8) ?? trimmed
        } catch {
            return trimmed
        }
    }
}

