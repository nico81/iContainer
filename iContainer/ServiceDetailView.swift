import SwiftUI
import AppKit

struct ServiceDetailView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("Info").tag(0)
                    Text("Logs").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                switch selectedTab {
                case 0:
                    serviceInfoView
                case 1:
                    serviceLogsView
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Service Details")
        .task {
            await serviceManager.checkServiceStatus()
        }
        .task(id: selectedTab) {
            if selectedTab == 1 && serviceManager.serviceLogs.isEmpty {
                await serviceManager.refreshServiceLogs()
            }
        }
    }

    private var serviceInfoView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apple Container System Service")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        StatusBadge(status: serviceManager.isServiceRunning ? "Running" : "Stopped")
                    }
                    Text(serviceManager.serviceStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Last check: \(lastCheckedAtText)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
                
                if let details = serviceManager.serviceDetails {
                    // Version Info
                    DetailSection(title: "Version Information", icon: "info.circle") {
                        DetailRow(label: "Version", value: details.version ?? "-")
                        DetailRow(label: "Commit", value: details.commit ?? "-", isMonospaced: true)
                    }
                    
                    // Paths
                    DetailSection(title: "System Paths", icon: "folder") {
                        DetailRow(label: "Install Root", value: details.installRoot ?? "-", isMonospaced: true)
                        DetailRow(label: "Data Root", value: details.dataRoot ?? "-", isMonospaced: true)
                    }

                    DetailSection(title: "Status Output", icon: "terminal") {
                        Text(serviceManager.lastStatusOutput.isEmpty ? "No status output available." : serviceManager.lastStatusOutput)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundColor(.secondary)
                    }

                    DetailSection(title: "Registry Authentication", icon: "person.badge.key") {
                        DetailRow(label: "Status", value: registryStatusText)
                        if let host = registryPrimaryHost {
                            DetailRow(label: "Host", value: host)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        if serviceManager.isServiceRunning {
                            ProgressView()
                            Text("Fetching service details...")
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.orange)
                            Text("Service is not running.")
                                .font(.headline)
                            Text("Start the service to view details.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
            }
            .padding()
        }
    }

    private var serviceLogsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Apple Container Service Logs")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                    if serviceManager.isLoadingServiceLogs {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Toggle("Follow", isOn: Binding(
                        get: { serviceManager.isFollowingServiceLogs },
                        set: { shouldFollow in
                            if shouldFollow {
                                serviceManager.startFollowingServiceLogs()
                            } else {
                                serviceManager.stopFollowingServiceLogs()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Button("Clear") {
                        serviceManager.clearServiceLogs()
                    }
                    .controlSize(.small)
                    Button {
                        Task { await serviceManager.refreshServiceLogs() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .disabled(serviceManager.isLoadingServiceLogs || serviceManager.isFollowingServiceLogs)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(serviceManager.serviceLogs, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(serviceManager.serviceLogs.isEmpty)
                }
                Text(serviceLogsCheckedAtText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    Text(serviceManager.serviceLogs.isEmpty ? "No service logs loaded yet. Press Refresh to load the latest Apple Container service logs, or enable Follow for live output." : serviceManager.serviceLogs)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    Color.clear
                        .frame(height: 1)
                        .id("SERVICE_LOGS_BOTTOM")
                }
                .onChange(of: serviceManager.serviceLogs) { _, _ in
                    guard serviceManager.isFollowingServiceLogs else { return }
                    proxy.scrollTo("SERVICE_LOGS_BOTTOM", anchor: .bottom)
                }
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding()
    }

    private var lastCheckedAtText: String {
        guard let date = serviceManager.lastCheckedAt else {
            return "Not checked yet"
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private var registryStatusText: String {
        switch containerManager.registryAuthState {
        case .unknown:
            return "Unknown"
        case .checking:
            return "Checking..."
        case .authenticated:
            return "Authenticated"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }

    private var serviceLogsCheckedAtText: String {
        guard let date = serviceManager.serviceLogsCheckedAt else {
            return "Last 15 minutes"
        }
        if serviceManager.isFollowingServiceLogs {
            return "Following live output since \(date.formatted(date: .omitted, time: .standard))"
        }
        return "Last 15 minutes, refreshed \(date.formatted(date: .omitted, time: .standard))"
    }

    private var registryPrimaryHost: String? {
        if case .authenticated(let hosts) = containerManager.registryAuthState {
            return hosts.first
        }
        return nil
    }
}
