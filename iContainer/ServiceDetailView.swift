import SwiftUI

struct ServiceDetailView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var containerManager: ContainerizationWrapper
    
    var body: some View {
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
        .navigationTitle("Service Details")
        .task {
            await serviceManager.checkServiceStatus()
        }
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

    private var registryPrimaryHost: String? {
        if case .authenticated(let hosts) = containerManager.registryAuthState {
            return hosts.first
        }
        return nil
    }
}
