import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingAddContainerAlert = false
    @State private var newContainerName = ""
    @State private var isContainersExpanded = true
    @State private var isImagesExpanded = true
    @State private var showingPullImageAlert = false
    @State private var pullImageReference = ""
    @State private var isPullingImage = false
    @State private var showingExecSheet = false
    @State private var execContainerId: String = ""
    @State private var execCommand = "echo hello"
    @State private var execOutput = ""
    @State private var execIsRunning = false
    @FocusState private var execCommandFocused: Bool

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
                Section {
                    DisclosureGroup("Containers", isExpanded: $isContainersExpanded) {
                    ForEach(containerManager.containers) { container in
                        ContainerRowView(
                            container: container,
                            showingExecSheet: $showingExecSheet,
                            execContainerId: $execContainerId,
                            execOutput: $execOutput
                        )
                    }
                }
                }
                Section {
                    DisclosureGroup(isExpanded: $isImagesExpanded) {
                        ForEach(containerManager.images) { image in
                            ImageRowView(image: image)
                        }
                    } label: {
                        HStack {
                            Text("Images")
                            Spacer()
                            Button {
                                showingPullImageAlert = true
                            } label: {
                                if isPullingImage {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                }
                            }
                            .buttonStyle(.borderless)
                            .disabled(isPullingImage)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("iContainer")
            .toolbar { addToolbar }
            .alert("Operation Failed", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {
                    containerManager.lastErrorMessage = nil
                }
            } message: {
                Text(containerManager.lastErrorMessage ?? "Unknown error")
            }
            
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
        .alert("Pull Image", isPresented: $showingPullImageAlert) {
            TextField("repository:tag", text: $pullImageReference)
            Button("Pull") {
                let reference = pullImageReference.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reference.isEmpty {
                    isPullingImage = true
                    Task {
                        await containerManager.pullImage(reference: reference)
                        pullImageReference = ""
                        isPullingImage = false
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pullImageReference = ""
            }
        } message: {
            Text("Enter the image reference to pull from the registry.")
        }
        .sheet(isPresented: $showingExecSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Execute Command")
                    .font(.headline)
                TextField("Command", text: $execCommand)
                    .textFieldStyle(.roundedBorder)
                    .focused($execCommandFocused)
                HStack {
                    Button("Run") {
                        runExecCommand()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(execCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || execIsRunning)
                    if execIsRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                    Spacer()
                    Button("Close") {
                        showingExecSheet = false
                    }
                }
                ScrollView {
                    Text(execOutput.isEmpty ? "Output will appear here." : execOutput)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 200)
            }
            .padding()
            .frame(minWidth: 500, minHeight: 360)
            .onAppear {
                execCommandFocused = true
            }
        }
        .task {
            await containerManager.refreshImages()
        }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { containerManager.lastErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    containerManager.lastErrorMessage = nil
                }
            }
        )
    }

    private func runExecCommand() {
        let trimmed = execCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !execIsRunning else { return }
        execIsRunning = true
        Task {
            let output = await containerManager.execContainer(
                containerId: execContainerId,
                command: trimmed
            )
            execOutput = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No output."
            execIsRunning = false
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
                .fill(serviceManager.isServiceRunning ? Color.green : Color.red)
                .brightness(serviceManager.isServiceRunning ? 0.15 : 0.05)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 0)
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
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: serviceManager.isServiceRunning ? "stop.fill" : "play.fill")
                        .foregroundColor(serviceManager.isServiceRunning ? .red : .green)
                        .brightness(serviceManager.isServiceRunning ? 0.05 : 0.15)
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isProcessing)
        }
        .padding(.vertical, 4)
    }
}

struct ContainerRowView: View {
    let container: Container
    @Binding var showingExecSheet: Bool
    @Binding var execContainerId: String
    @Binding var execOutput: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingDeleteConfirmation = false
    @State private var showingStopConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink {
                ContainerDetailView(containerId: container.id)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(container.status == .running ? Color.green : Color.red)
                            .brightness(container.status == .running ? 0.15 : 0.05)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.15), radius: 1, x: 0, y: 0)
                        Text(container.name)
                            .font(.headline)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                ZStack {
                    if isDeleting || containerManager.updatingContainerIDs.contains(container.id) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        if container.status == .stopped {
                            Button {
                                Task {
                                    await containerManager.startContainer(containerId: container.id)
                                }
                            } label: {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.green)
                                    .brightness(0.15)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button {
                                showingStopConfirmation = true
                            } label: {
                                Image(systemName: "stop.fill")
                                    .foregroundColor(.red)
                                    .brightness(0.05)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .frame(width: 60)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if container.status == .running {
                Button {
                    showingStopConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .foregroundColor(.red)
                        Text("Stop")
                    }
                }
                Button {
                    execContainerId = container.id
                    execOutput = ""
                    showingExecSheet = true
                } label: {
                    Label("Exec", systemImage: "terminal")
                }
                Button {
                    Task {
                        await containerManager.stopContainer(containerId: container.id)
                        await containerManager.startContainer(containerId: container.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                        Text("Restart")
                    }
                }
            } else {
                Button {
                    Task {
                        await containerManager.startContainer(containerId: container.id)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .foregroundColor(.green)
                        Text("Start")
                    }
                }
                Button {
                    execContainerId = container.id
                    execOutput = ""
                    showingExecSheet = true
                } label: {
                    Label("Exec", systemImage: "terminal")
                }
            }
            Divider()
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                    Text("Delete")
                }
            }
            .tint(.red)
        }
        .confirmationDialog("Delete Container?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await containerManager.deleteContainer(containerId: container.id)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the container \"\(container.name)\"? This action cannot be undone.")
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
