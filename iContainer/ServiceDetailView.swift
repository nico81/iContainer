import SwiftUI

struct ServiceDetailView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("System Service")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        StatusBadge(status: serviceManager.isServiceRunning ? "Running" : "Stopped")
                    }
                    Text(serviceManager.serviceStatus)
                        .font(.caption)
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
    }
}
