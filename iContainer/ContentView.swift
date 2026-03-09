import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddContainerAlert = false
    @State private var newContainerName = ""

    var body: some View {
        if !containerManager.missingDependencies.isEmpty {
            DependencyErrorView(errors: containerManager.missingDependencies)
        } else {
            NavigationView {
            List {
                Section(header: Text("Container System Service")) {
                    NavigationLink(destination: ServiceDetailView()) {
                        ServiceStatusView()
                    }
                }
                Section(header: Text("Containers")) {
                    ForEach(containerManager.containers) { container in
                        NavigationLink {
                            ContainerDetailView(containerId: container.id)
                        } label: {
                            ContainerRowView(container: container)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("iContainer")
            .toolbar { addToolbar }
            
            // Placeholder view for when no container is selected
            Text("Select a container to see its details.")
        }
        .alert("New Container", isPresented: $showingAddContainerAlert) {
            TextField("Container Name", text: $newContainerName)
            Button("Create") {
                if !newContainerName.isEmpty {
                    Task {
                        await containerManager.createContainer(name: newContainerName)
                        newContainerName = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                newContainerName = ""
            }
        }
        }
    }
    
    private var addToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingAddContainerAlert = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }
}

struct ServiceStatusView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var isProcessing = false
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .frame(width: 14, height: 14)
                .foregroundColor(serviceManager.isServiceRunning ? .green : .red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Service Status")
                    .font(.headline)
                Text(serviceManager.serviceStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            Button(action: {
                isProcessing = true
                Task {
                    if serviceManager.isServiceRunning {
                        await serviceManager.stopService()
                    } else {
                        await serviceManager.startService()
                    }
                    isProcessing = false
                }
            }) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: serviceManager.isServiceRunning ? "stop.fill" : "play.fill")
                        .foregroundColor(serviceManager.isServiceRunning ? .red : .green)
                        .frame(width: 20, height: 20)
                }
            }
            .buttonStyle(.plain) // Use plain style to avoid conflict with NavigationLink
            .disabled(isProcessing)
        }
        .padding(.vertical, 4)
    }
}

struct ContainerRowView: View {
    let container: Container
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingDeleteConfirmation = false
    @State private var showingStopConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .frame(width: 10, height: 10)
                    .foregroundColor(container.status == .running ? .green : .red)
                Text(container.name)
                    .font(.headline)
                Spacer()

                ZStack {
                    if containerManager.updatingContainerIDs.contains(container.id) {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        if container.status == .stopped {
                            Button {
                                Task {
                                    await containerManager.startContainer(containerId: container.id)
                                }
                            } label: {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button {
                                showingStopConfirmation = true
                            } label: {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .frame(width: 60)

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(containerManager.updatingContainerIDs.contains(container.id))
            }
            HStack(spacing: 16) {
                if let image = container.image {
                    Label(image, systemImage: "shippingbox")
                        .font(.caption)
                }
                if let ip = container.ipAddress {
                    Label(ip, systemImage: "network")
                        .font(.caption)
                }

            }
        }
        .padding(.vertical, 4)
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Container?"),
                message: Text("Are you sure you want to delete the container \"\(container.name)\"? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        await containerManager.deleteContainer(containerId: container.id)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(isPresented: $showingStopConfirmation) {
            Alert(
                title: Text("Stop Container?"),
                message: Text("Are you sure you want to stop the container \"\(container.name)\"?"),
                primaryButton: .destructive(Text("Stop")) {
                    Task {
                        await containerManager.stopContainer(containerId: container.id)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ContainerizationWrapper())
            .environmentObject(ServiceManager())
    }
}
