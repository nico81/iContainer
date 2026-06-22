import SwiftUI
import AppKit

/// Detail view for a single container machine. Mirrors `ContainerDetailView`:
/// a tab host (Info / Logs for now) with the switcher in the toolbar.
struct MachineDetailView: View {
    let machineId: String
    let initialTab: Int
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var appNavigation: AppNavigation
    @State private var details: MachineDetails?
    @State private var isLoading = true
    @State private var selectedTab: Int
    @State private var showingDeleteConfirmation = false

    init(machineId: String, initialTab: Int = 0) {
        self.machineId = machineId
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 1:
                    MachineShellView(machineId: machineId)
                case 2:
                    MachineLogsView(machineId: machineId)
                default:
                    infoTab
                }
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                AccentTabPicker(selection: $selectedTab, labels: ["Info", "Run", "Logs"])
                    .frame(width: 260)
            }
        }
        .task(id: machineId) { await loadDetails() }
        .onChange(of: containerManager.machines) { _, _ in
            Task { await loadDetails() }
        }
        .confirmationDialog(
            "Delete Machine?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await containerManager.deleteMachine(machineId: machineId) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the machine \"\(machineId)\"? This action cannot be undone.")
        }
    }

    private var liveStatus: MachineStatus {
        containerManager.machines.first(where: { $0.id == machineId })?.status
            ?? details?.status ?? .unknown
    }

    private var isBusy: Bool {
        containerManager.updatingMachineIDs.contains(machineId)
    }

    private var infoTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(machineId)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        if details?.isDefault ?? false {
                            Text("DEFAULT")
                                .font(.caption2).fontWeight(.bold)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .foregroundColor(.accentColor)
                                .cornerRadius(AppRadius.small)
                        }
                        Spacer()
                        StatusBadge(status: liveStatus.isRunning ? "Running" : "Stopped")
                    }
                }

                actionsRow

                if let details {
                    DetailSection(title: "Configuration", icon: "cpu") {
                        DetailRow(label: "CPUs", value: details.cpus.map(String.init) ?? "-")
                        DetailRow(label: "Memory", value: Self.formatBytes(details.memoryBytes))
                        DetailRow(label: "Disk", value: Self.formatBytes(details.diskBytes))
                        DetailRow(label: "Home mount", value: details.homeMount ?? "-")
                    }
                    DetailSection(title: "Image", icon: "shippingbox") {
                        DetailRow(label: "Reference", value: details.imageReference ?? "-", isMonospaced: true)
                        DetailRow(label: "Platform", value: platformText(details))
                    }
                    DetailSection(title: "Details", icon: "info.circle") {
                        DetailRow(label: "Created", value: details.createdDate ?? "-")
                        DetailRow(label: "User", value: details.username ?? "-")
                    }
                } else if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                }
            }
            .padding()
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            if isBusy {
                ProgressView().scaleEffect(0.8)
            } else if liveStatus.isRunning {
                Button { Task { await containerManager.stopMachine(machineId: machineId) } } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .actionButtonStyle()
            } else {
                Button { Task { await containerManager.startMachine(machineId: machineId) } } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .actionButtonStyle(prominent: true)
            }

            Button { appNavigation.editMachine(id: machineId) } label: {
                Label("Edit Configuration", systemImage: "slider.horizontal.3")
            }
            .actionButtonStyle()
            .disabled(isBusy)

            Spacer()

            Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .actionButtonStyle()
            .disabled(isBusy)
        }
    }

    private func platformText(_ d: MachineDetails) -> String {
        switch (d.os, d.architecture) {
        case let (os?, arch?): return "\(os)/\(arch)"
        case let (os?, nil): return os
        case let (nil, arch?): return arch
        default: return "-"
        }
    }

    private func loadDetails() async {
        details = await containerManager.inspectMachine(machineId: machineId)
        isLoading = false
    }

    static func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "-" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: bytes)
    }
}

/// Logs tab: fetches `container machine logs <id>` on demand.
struct MachineLogsView: View {
    let machineId: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var logs: String = ""
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Machine Logs").font(.largeTitle).fontWeight(.bold)
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.8) }
                Button { Task { await refresh() } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(isLoading)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(logs.isEmpty)
            }

            ScrollView {
                Text(logs.isEmpty ? "No logs loaded yet. Press Refresh." : logs)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
            .cardOutline(AppRadius.card)
        }
        .padding()
        .task(id: machineId) { await refresh() }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        if let output = await containerManager.machineLogs(machineId: machineId) {
            logs = CLIParsers.limitedLogOutput(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
