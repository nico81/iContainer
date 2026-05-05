import SwiftUI
import AppKit

struct ContainerNavigationTarget: Hashable {
    let id: String
    let tab: Int
}

enum SidebarSelection: Hashable {
    case service
    case container(ContainerNavigationTarget)
}

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var showingCreateContainerSheet = false
    @State private var createImage = ""
    @State private var createName = ""
    @State private var createPorts = ""
    @State private var createHostPort = ""
    @State private var createContainerPort = ""
    @State private var createVolumes = ""
    @State private var createEnv = ""
    @State private var isCreatingContainer = false
    @State private var isContainersExpanded = true
    @State private var isImagesExpanded = true
    @State private var showingPullImageAlert = false
    @State private var pullImageReference = ""
    @State private var isPullingImage = false
    @State private var showingRegistryLoginSheet = false
    @State private var registryHost = "registry-1.docker.io"
    @State private var registryUsername = ""
    @State private var registryPassword = ""
    @State private var isLoggingInRegistry = false
    @State private var selection: SidebarSelection?

    var body: some View {
        Group {
            if !containerManager.missingDependencies.isEmpty {
                DependencyErrorView(errors: containerManager.missingDependencies)
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .sheet(isPresented: $showingCreateContainerSheet) {
            createContainerSheet
        }
        .sheet(isPresented: $showingRegistryLoginSheet) {
            registryLoginSheet
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
        .task {
            await containerManager.refreshImages()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section(header: Text("Container System Service")) {
                NavigationLink(value: SidebarSelection.service) {
                    ServiceStatusView()
                }
                .contextMenu {
                    Button("Registry Login") {
                        showingRegistryLoginSheet = true
                    }
                }
            }
            Section {
                DisclosureGroup("Containers", isExpanded: $isContainersExpanded) {
                    ForEach(containerManager.containers) { container in
                        NavigationLink(value: SidebarSelection.container(ContainerNavigationTarget(id: container.id, tab: 0))) {
                            ContainerRowView(
                                container: container,
                                onNavigateToTab: { tab in
                                    selection = .container(ContainerNavigationTarget(id: container.id, tab: tab))
                                }
                            )
                        }
                    }
                }
            }
            Section {
                DisclosureGroup(isExpanded: $isImagesExpanded) {
                    if serviceManager.isServiceRunning {
                        ForEach(containerManager.images) { image in
                            ImageRowView(image: image)
                        }
                    } else {
                        EmptyView()
                    }
                } label: {
                    HStack {
                        Text("Images")
                        Spacer()
                        if serviceManager.isServiceRunning {
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
        }
        .listStyle(.sidebar)
        .navigationTitle("iContainer")
        .toolbar { addToolbar }
        .alert("Operation Failed", isPresented: errorAlertBinding) {
            if isRegistryAuthError {
                Button("Login now") {
                    containerManager.lastErrorMessage = nil
                    showingRegistryLoginSheet = true
                }
                Button("Copy command") {
                    copyRegistryLoginCommand()
                    containerManager.lastErrorMessage = nil
                }
                Button("Cancel", role: .cancel) {
                    containerManager.lastErrorMessage = nil
                }
            } else {
                Button("OK", role: .cancel) {
                    containerManager.lastErrorMessage = nil
                }
            }
        } message: {
            Text(errorAlertMessage)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .service:
            ServiceDetailView()
        case .container(let target):
            ContainerDetailView(containerId: target.id, initialTab: target.tab)
                .id(target)
        default:
            Text("Select a container to see its details.")
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

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        if serviceManager.isServiceRunning {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateContainerSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var createContainerSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Container")
                .font(.headline)

            TextField("Image (required)", text: $createImage)
                .textFieldStyle(.roundedBorder)
            TextField("Name (optional)", text: $createName)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 4) {
                Text("Published Ports")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("Local port (host) e.g. 8080", text: $createHostPort)
                        .textFieldStyle(.roundedBorder)
                    Text(":")
                        .foregroundColor(.secondary)
                    TextField("Container port e.g. 80", text: $createContainerPort)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        addPortMapping()
                    }
                    .disabled(createHostPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || createContainerPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                TextField("Mappings list (host:container), e.g. 8080:80, 8443:443", text: $createPorts, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                if portMappings.isEmpty {
                    Text("No port mappings added yet.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(portMappings, id: \.self) { mapping in
                            HStack {
                                Text(mapping)
                                    .font(.caption.monospaced())
                                Spacer()
                                Button {
                                    removePortMapping(mapping)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                Text("Format: local(host):external(container)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Volumes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. /host/path:/container/path", text: $createVolumes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Environment Variables")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g. KEY=value", text: $createEnv, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Create") {
                    runCreateContainer()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(createImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreatingContainer)

                if isCreatingContainer {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Spacer()

                Button("Close") {
                    showingCreateContainerSheet = false
                }
            }

            Text("Use comma or newline to add multiple ports, volumes, or env entries.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 420)
    }

    private var registryLoginSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Registry Login")
                .font(.headline)

            TextField("Registry Host", text: $registryHost)
                .textFieldStyle(.roundedBorder)
            TextField("Username", text: $registryUsername)
                .textFieldStyle(.roundedBorder)
            SecureField("Password or token", text: $registryPassword)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Login") {
                    runRegistryLogin()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isLoggingInRegistry || registryHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || registryUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || registryPassword.isEmpty)

                if isLoggingInRegistry {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Spacer()

                Button("Close") {
                    showingRegistryLoginSheet = false
                }
            }

            Text("Per Docker Hub usa host `registry-1.docker.io` e un Personal Access Token.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 260)
    }

    private func parseList(_ raw: String) -> [String] {
        raw
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func runCreateContainer() {
        let image = createImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !image.isEmpty, !isCreatingContainer else { return }

        isCreatingContainer = true
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ports = parseList(createPorts)
        let volumes = parseList(createVolumes)
        let env = parseList(createEnv)

        Task {
            await containerManager.createContainer(
                image: image,
                name: name.isEmpty ? nil : name,
                publishedPorts: ports,
                volumes: volumes,
                environment: env
            )
            isCreatingContainer = false

            if containerManager.lastErrorMessage == nil {
                createImage = ""
                createName = ""
                createPorts = ""
                createHostPort = ""
                createContainerPort = ""
                createVolumes = ""
                createEnv = ""
                showingCreateContainerSheet = false
            }
        }
    }

    private var isRegistryAuthError: Bool {
        guard let message = containerManager.lastErrorMessage else { return false }
        return ContainerizationWrapper.isRegistryAuthError(message)
    }

    private var errorAlertMessage: String {
        guard let message = containerManager.lastErrorMessage else {
            return "Unknown error"
        }
        if isRegistryAuthError {
            return "Registry authentication required.\n\(message)\n\nApri il login guidato per autenticarti e riprovare."
        }
        return message
    }

    private func runRegistryLogin() {
        guard !isLoggingInRegistry else { return }
        isLoggingInRegistry = true

        let host = registryHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = registryUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = registryPassword

        Task {
            let success = await containerManager.loginRegistry(host: host, username: username, password: password)
            isLoggingInRegistry = false
            if success {
                registryPassword = ""
                showingRegistryLoginSheet = false
            }
        }
    }

    private func copyRegistryLoginCommand() {
        let host = registryHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = registryUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = host.isEmpty ? "registry-1.docker.io" : host
        let resolvedUser = username.isEmpty ? "<username>" : username
        let command = containerManager.registryLoginCommand(host: resolvedHost, username: resolvedUser)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func addPortMapping() {
        let host = createHostPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let container = createContainerPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !container.isEmpty else { return }
        let mapping = "\(host):\(container)"
        if createPorts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createPorts = mapping
        } else {
            createPorts += ", \(mapping)"
        }
        createHostPort = ""
        createContainerPort = ""
    }

    private var portMappings: [String] {
        parseList(createPorts)
    }

    private func removePortMapping(_ mapping: String) {
        let updated = portMappings.filter { $0 != mapping }
        createPorts = updated.joined(separator: ", ")
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
    let onNavigateToTab: (Int) -> Void
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingDeleteConfirmation = false
    @State private var showingStopConfirmation = false
    @State private var isDeleting = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
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
            }
            Divider()
            Button {
                onNavigateToTab(0)
            } label: {
                Label("Info", systemImage: "info.circle")
            }
            Button {
                onNavigateToTab(1)
            } label: {
                Label("Stats", systemImage: "chart.xyaxis.line")
            }
            Button {
                onNavigateToTab(2)
            } label: {
                Label("Shell", systemImage: "terminal")
            }
            Button {
                onNavigateToTab(3)
            } label: {
                Label("Logs", systemImage: "doc.plaintext")
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
