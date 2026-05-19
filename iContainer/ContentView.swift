import SwiftUI
import AppKit
import Combine

struct ContainerNavigationTarget: Hashable {
    let id: String
    let tab: Int
}

enum SidebarSelection: Hashable {
    case service
    case container(ContainerNavigationTarget)
}

private enum CreateImageSource: String, CaseIterable, Identifiable {
    case image = "Image"
    case dockerfile = "Build from Dockerfile"

    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var appNavigation: AppNavigation
    @State private var showingCreateContainerSheet = false
    @State private var createImageSource: CreateImageSource = .image
    @State private var createImage = ""
    @State private var createBuildTag = ""
    @State private var createDockerfilePath = ""
    @State private var createBuildContextPath = ""
    @State private var isCreateOptionsExpanded = false
    @State private var createName = ""
    @State private var createPorts = ""
    @State private var createHostPort = ""
    @State private var createContainerPort = ""
    @State private var createVolumes = ""
    @State private var createHostPath = ""
    @State private var createContainerPath = ""
    @State private var createEnv = ""
    @State private var createEnvKey = ""
    @State private var createEnvValue = ""
    @State private var isCreatingContainer = false
    @State private var createErrorMessage: String?
    @State private var shouldOpenRegistryLoginAfterCreateSheet = false
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
    @State private var shouldReturnToCreateAfterRegistryLogin = false
    @State private var showingEditContainerSheet = false
    @State private var editingContainerId: String?
    @State private var editImage = ""
    @State private var editName = ""
    @State private var editPorts = ""
    @State private var editHostPort = ""
    @State private var editContainerPort = ""
    @State private var editVolumes = ""
    @State private var editHostPath = ""
    @State private var editContainerPath = ""
    @State private var editEnv = ""
    @State private var editEnvKey = ""
    @State private var editEnvValue = ""
    @State private var isLoadingContainerEditSettings = false
    @State private var isSavingContainerEdit = false
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
        .sheet(isPresented: $showingEditContainerSheet) {
            editContainerSheet
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
        .onReceive(appNavigation.$containerTarget.compactMap { $0 }) { target in
            selection = .container(target)
        }
        .onChange(of: showingCreateContainerSheet) { isPresented in
            guard !isPresented else { return }
            createErrorMessage = nil
            containerManager.lastErrorMessage = nil
            if shouldOpenRegistryLoginAfterCreateSheet {
                shouldOpenRegistryLoginAfterCreateSheet = false
                DispatchQueue.main.async {
                    showingRegistryLoginSheet = true
                }
            }
        }
        .onChange(of: showingRegistryLoginSheet) { isPresented in
            guard !isPresented, shouldReturnToCreateAfterRegistryLogin else { return }
            shouldReturnToCreateAfterRegistryLogin = false
            DispatchQueue.main.async {
                showingCreateContainerSheet = true
            }
        }
        .onReceive(appNavigation.$editContainerId.compactMap { $0 }) { containerId in
            openEditContainerSheet(containerId: containerId)
            appNavigation.editContainerId = nil
        }
        .onReceive(appNavigation.$serviceRequestID.dropFirst()) { _ in
            selection = .service
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section(header: Text("Container service")) {
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
                                },
                                onEditSettings: {
                                    openEditContainerSheet(containerId: container.id)
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
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        .navigationTitle("iContainer")
        .toolbar { addToolbar }
        .alert("Operation Failed", isPresented: errorAlertBinding) {
            if shouldShowRegistryLoginActions {
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
            welcomeDashboard
        }
    }

    private var welcomeDashboard: some View {
        WelcomeDashboardView(
            containers: containerManager.containers,
            imageCount: containerManager.images.count,
            isServiceRunning: serviceManager.isServiceRunning,
            onCreateContainer: {
                createErrorMessage = nil
                containerManager.lastErrorMessage = nil
                containerManager.lastBuildOutput = nil
                showingCreateContainerSheet = true
            },
            onPullImage: {
                showingPullImageAlert = true
            },
            onShowService: {
                selection = .service
            },
            onSelectContainer: { container in
                selection = .container(ContainerNavigationTarget(id: container.id, tab: 0))
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { !showingCreateContainerSheet && containerManager.lastErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    containerManager.lastErrorMessage = nil
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var addToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if serviceManager.isServiceRunning {
                Button {
                    createErrorMessage = nil
                    containerManager.lastErrorMessage = nil
                    containerManager.lastBuildOutput = nil
                    showingCreateContainerSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create container")
            }

            Button {
                selection = nil
            } label: {
                Image(systemName: "house")
            }
            .help("Show overview")
        }
    }

    private var createContainerSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create Container")
                    .font(.headline)

                Picker("Image Source", selection: $createImageSource) {
                    ForEach(CreateImageSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                createImageSourceFields

                if let message = createErrorMessage {
                    createErrorView(message: message)
                }

                TextField("Name (optional)", text: $createName)
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup("Container Options", isExpanded: $isCreateOptionsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        MappingPairsEditor(
                            title: "Ports",
                            mappingsText: $createPorts,
                            firstValue: $createHostPort,
                            secondValue: $createContainerPort,
                            isLoading: false,
                            emptyText: "No port mappings added yet.",
                            firstTitle: "Host Port",
                            secondTitle: "Container Port",
                            firstPlaceholder: "Host Port e.g. 8080",
                            secondPlaceholder: "Container Port e.g. 80",
                            formatText: "Format: host:container",
                            iconName: "network",
                            addAction: addPortMapping,
                            removeAction: removePortMapping,
                            browseFirstAction: nil
                        )

                        MappingPairsEditor(
                            title: "Volumes",
                            mappingsText: $createVolumes,
                            firstValue: $createHostPath,
                            secondValue: $createContainerPath,
                            isLoading: false,
                            emptyText: "No volume mappings added yet.",
                            firstTitle: "Host Path",
                            secondTitle: "Container Path",
                            firstPlaceholder: "Host Path e.g. /Users/me/data",
                            secondPlaceholder: "Container Path e.g. /data",
                            formatText: "Format: host-path:container-path",
                            iconName: "externaldrive",
                            addAction: addVolumeMapping,
                            removeAction: removeVolumeMapping,
                            browseFirstAction: browseCreateHostPath
                        )

                        EnvironmentVariablesEditor(
                            environmentText: $createEnv,
                            key: $createEnvKey,
                            value: $createEnvValue,
                            isLoading: false,
                            emptyText: "No environment variables added yet.",
                            addAction: addEnvVariable,
                            removeAction: removeEnvVariable
                        )
                    }
                    .padding(.top, 8)
                }

                HStack {
                    Button(createActionTitle) {
                        runCreateContainer()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreateContainer || isCreatingContainer)

                    if isCreatingContainer {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Spacer()

                    Button("Close") {
                        createErrorMessage = nil
                        containerManager.lastErrorMessage = nil
                        showingCreateContainerSheet = false
                    }
                }

                Text("Image references can be local or remote. Remote images are fetched by the container CLI when needed.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 720, idealWidth: 920, maxWidth: .infinity, minHeight: 560, idealHeight: 720, maxHeight: .infinity)
        .background(WindowResizeConfigurator(minSize: CGSize(width: 720, height: 560), shouldCenter: showingCreateContainerSheet))
    }

    private func createErrorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Create failed", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))

            Text(errorMessage(for: message))
                .font(.caption)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if shouldOfferRegistryLogin(for: message) {
                    Button("Login now") {
                        createErrorMessage = nil
                        containerManager.lastErrorMessage = nil
                        shouldReturnToCreateAfterRegistryLogin = true
                        shouldOpenRegistryLoginAfterCreateSheet = true
                        showingCreateContainerSheet = false
                    }

                    Button("Copy command") {
                        copyRegistryLoginCommand()
                        createErrorMessage = nil
                        containerManager.lastErrorMessage = nil
                    }
                }

                Button("Dismiss") {
                    createErrorMessage = nil
                    containerManager.lastErrorMessage = nil
                }
            }
            .buttonStyle(.bordered)
        }
        .foregroundColor(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var createImageSourceFields: some View {
        switch createImageSource {
        case .image:
            HStack(spacing: 8) {
                TextField("Image (local or registry reference)", text: $createImage)
                    .textFieldStyle(.roundedBorder)

                if !containerManager.images.isEmpty {
                    Menu {
                        ForEach(containerManager.images) { image in
                            Button(image.reference) {
                                createImage = image.reference
                                createErrorMessage = nil
                                containerManager.lastErrorMessage = nil
                            }
                        }
                    } label: {
                        Image(systemName: "shippingbox")
                            .frame(width: 16, height: 16)
                    }
                    .menuStyle(.button)
                    .help("Choose local image")
                }
            }
        case .dockerfile:
            VStack(alignment: .leading, spacing: 8) {
                TextField("Image Tag (required)", text: $createBuildTag)
                    .textFieldStyle(.roundedBorder)
                PathPickerRow(
                    title: "Context Folder",
                    placeholder: "Build context folder",
                    path: $createBuildContextPath,
                    systemImage: "folder",
                    action: browseCreateBuildContext
                )
                PathPickerRow(
                    title: "Dockerfile",
                    placeholder: "Dockerfile path",
                    path: $createDockerfilePath,
                    systemImage: "doc.text",
                    action: browseCreateDockerfile
                )
                if let output = containerManager.lastBuildOutput, !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(output)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(6)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var editContainerSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Edit Container Settings")
                    .font(.headline)

                TextField("Image (required)", text: $editImage)
                    .textFieldStyle(.roundedBorder)
                TextField("Name (optional)", text: $editName)
                    .textFieldStyle(.roundedBorder)

                MappingPairsEditor(
                    title: "Ports",
                    mappingsText: $editPorts,
                    firstValue: $editHostPort,
                    secondValue: $editContainerPort,
                    isLoading: isLoadingContainerEditSettings,
                    emptyText: "No port mappings configured.",
                    firstTitle: "Host Port",
                    secondTitle: "Container Port",
                    firstPlaceholder: "Host Port e.g. 8080",
                    secondPlaceholder: "Container Port e.g. 80",
                formatText: "Format: host:container",
                iconName: "network",
                addAction: addEditPortMapping,
                removeAction: removeEditPortMapping,
                browseFirstAction: nil
            )

                MappingPairsEditor(
                    title: "Volumes",
                    mappingsText: $editVolumes,
                    firstValue: $editHostPath,
                    secondValue: $editContainerPath,
                    isLoading: isLoadingContainerEditSettings,
                    emptyText: "No volume mappings configured.",
                    firstTitle: "Host Path",
                    secondTitle: "Container Path",
                    firstPlaceholder: "Host Path e.g. /Users/me/data",
                    secondPlaceholder: "Container Path e.g. /data",
                formatText: "Format: host-path:container-path",
                iconName: "externaldrive",
                addAction: addEditVolumeMapping,
                removeAction: removeEditVolumeMapping,
                browseFirstAction: browseEditHostPath
            )

                EnvironmentVariablesEditor(
                    environmentText: $editEnv,
                    key: $editEnvKey,
                    value: $editEnvValue,
                    isLoading: isLoadingContainerEditSettings,
                    emptyText: "No environment variables configured.",
                    addAction: addEditEnvVariable,
                    removeAction: removeEditEnvVariable
                )

                HStack {
                    Button("Save") {
                        runSaveContainerEdit()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isLoadingContainerEditSettings || isSavingContainerEdit || editImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isLoadingContainerEditSettings || isSavingContainerEdit {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Spacer()

                    Button("Close") {
                        showingEditContainerSheet = false
                    }
                }

                Text("Applying settings recreates the container with the new configuration.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 720, idealWidth: 920, maxWidth: .infinity, minHeight: 560, idealHeight: 720, maxHeight: .infinity)
        .background(WindowResizeConfigurator(minSize: CGSize(width: 720, height: 560), shouldCenter: showingEditContainerSheet))
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

    private var canCreateContainer: Bool {
        switch createImageSource {
        case .image:
            return !createImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .dockerfile:
            return !createBuildTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !createDockerfilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !createBuildContextPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var createActionTitle: String {
        switch createImageSource {
        case .image:
            return "Create"
        case .dockerfile:
            return "Build & Create"
        }
    }

    private func runCreateContainer() {
        guard canCreateContainer, !isCreatingContainer else { return }

        isCreatingContainer = true
        createErrorMessage = nil
        containerManager.lastErrorMessage = nil
        let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ports = parseList(createPorts)
        let volumes = parseList(createVolumes)
        let env = parseList(createEnv)

        Task {
            let image: String
            switch createImageSource {
            case .image:
                image = createImage.trimmingCharacters(in: .whitespacesAndNewlines)
            case .dockerfile:
                image = createBuildTag.trimmingCharacters(in: .whitespacesAndNewlines)
                let built = await containerManager.buildImage(
                    tag: image,
                    dockerfilePath: createDockerfilePath,
                    contextDirectory: createBuildContextPath
                )
                if !built {
                    createErrorMessage = containerManager.lastErrorMessage
                    containerManager.lastErrorMessage = nil
                    isCreatingContainer = false
                    return
                }
            }

            await containerManager.createContainer(
                image: image,
                name: name.isEmpty ? nil : name,
                publishedPorts: ports,
                volumes: volumes,
                environment: env
            )
            isCreatingContainer = false

            if let message = containerManager.lastErrorMessage {
                createErrorMessage = message
                containerManager.lastErrorMessage = nil
            } else {
                createImageSource = .image
                createImage = ""
                createBuildTag = ""
                createDockerfilePath = ""
                createBuildContextPath = ""
                isCreateOptionsExpanded = false
                containerManager.lastBuildOutput = nil
                createName = ""
                createPorts = ""
                createHostPort = ""
                createContainerPort = ""
                createVolumes = ""
                createHostPath = ""
                createContainerPath = ""
                createEnv = ""
                createEnvKey = ""
                createEnvValue = ""
                showingCreateContainerSheet = false
            }
        }
    }

    private func openEditContainerSheet(containerId: String) {
        editingContainerId = containerId
        let listed = containerManager.containers.first(where: { $0.id == containerId })
        editImage = listed?.image ?? ""
        editName = listed?.name ?? ""
        editPorts = ""
        editHostPort = ""
        editContainerPort = ""
        editVolumes = ""
        editHostPath = ""
        editContainerPath = ""
        editEnv = ""
        editEnvKey = ""
        editEnvValue = ""
        isLoadingContainerEditSettings = true
        showingEditContainerSheet = true

        Task {
            if let settings = await containerManager.editableSettings(containerId: containerId) {
                editImage = settings.image
                editName = settings.name
                editPorts = settings.ports.joined(separator: ", ")
                editVolumes = settings.volumes.joined(separator: ", ")
                editEnv = settings.environment.joined(separator: ", ")
            }
            isLoadingContainerEditSettings = false
        }
    }

    private func runSaveContainerEdit() {
        guard let containerId = editingContainerId, !isSavingContainerEdit else { return }
        let image = editImage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !image.isEmpty else { return }

        isSavingContainerEdit = true
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ports = parseList(editPorts)
        let volumes = parseList(editVolumes)
        let env = parseList(editEnv)

        Task {
            let success = await containerManager.updateContainerSettings(
                containerId: containerId,
                image: image,
                name: name.isEmpty ? nil : name,
                publishedPorts: ports,
                volumes: volumes,
                environment: env
            )
            isSavingContainerEdit = false
            if success {
                let targetTab: Int
                if case .container(let target) = selection {
                    targetTab = target.tab
                } else {
                    targetTab = 0
                }
                if !name.isEmpty,
                   let recreated = containerManager.containers.first(where: { $0.name == name }) {
                    selection = .container(ContainerNavigationTarget(id: recreated.id, tab: targetTab))
                } else if let recreated = containerManager.containers.last(where: { ($0.image ?? "") == image }) {
                    selection = .container(ContainerNavigationTarget(id: recreated.id, tab: targetTab))
                }
                showingEditContainerSheet = false
            }
        }
    }

    private var isRegistryAuthError: Bool {
        guard let message = containerManager.lastErrorMessage else { return false }
        return isRegistryAuthError(message)
    }

    private var shouldShowRegistryLoginActions: Bool {
        guard let message = containerManager.lastErrorMessage else { return false }
        return shouldOfferRegistryLogin(for: message)
    }

    private var errorAlertMessage: String {
        guard let message = containerManager.lastErrorMessage else {
            return "Unknown error"
        }
        return errorMessage(for: message)
    }

    private func isRegistryAuthError(_ message: String) -> Bool {
        ContainerizationWrapper.isRegistryAuthError(message)
    }

    private func shouldOfferRegistryLogin(for message: String) -> Bool {
        isRegistryAuthError(message)
            && !isLikelyImageReferenceError(message)
    }

    private func errorMessage(for message: String) -> String {
        if isLikelyImageReferenceError(message) {
            return "Image reference not found or incomplete.\n\(message)\n\nDocker Hub looked under the official `library` namespace, which usually means the image name is missing its owner/namespace or is misspelled. Use the full reference, for example `owner/image:tag`, or choose a local image from the image picker."
        }
        if isRegistryAuthError(message) {
            if let hosts = authenticatedRegistryHosts, !hosts.isEmpty {
                return "Registry rejected the image pull.\n\(message)\n\nSaved credentials exist for \(hosts.joined(separator: ", ")). Check that the image reference includes the correct namespace, for example owner/image:tag, that the repository is accessible, and that the saved token has permission."
            }
            return "Registry authentication required.\n\(message)\n\nApri il login guidato per autenticarti e riprovare."
        }
        return message
    }

    private func isLikelyImageReferenceError(_ message: String) -> Bool {
        hasSavedRegistryCredentials
            && ContainerizationWrapper.isLikelyDockerHubImageReferenceError(message)
    }

    private var hasSavedRegistryCredentials: Bool {
        guard let hosts = authenticatedRegistryHosts else { return false }
        return !hosts.isEmpty
    }

    private var authenticatedRegistryHosts: [String]? {
        if case .authenticated(let hosts) = containerManager.registryAuthState {
            return hosts
        }
        return nil
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

    private func addEditPortMapping() {
        let host = editHostPort.trimmingCharacters(in: .whitespacesAndNewlines)
        let container = editContainerPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !container.isEmpty else { return }
        let mapping = "\(host):\(container)"
        if editPorts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editPorts = mapping
        } else {
            editPorts += ", \(mapping)"
        }
        editHostPort = ""
        editContainerPort = ""
    }

    private func addVolumeMapping() {
        let host = createHostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let container = createContainerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !container.isEmpty else { return }
        let mapping = "\(host):\(container)"
        if createVolumes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createVolumes = mapping
        } else {
            createVolumes += ", \(mapping)"
        }
        createHostPath = ""
        createContainerPath = ""
    }

    private func addEditVolumeMapping() {
        let host = editHostPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let container = editContainerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, !container.isEmpty else { return }
        let mapping = "\(host):\(container)"
        if editVolumes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editVolumes = mapping
        } else {
            editVolumes += ", \(mapping)"
        }
        editHostPath = ""
        editContainerPath = ""
    }

    private func browseCreateHostPath() {
        if let path = chooseHostPath() {
            createHostPath = path
        }
    }

    private func browseEditHostPath() {
        if let path = chooseHostPath() {
            editHostPath = path
        }
    }

    private func browseCreateBuildContext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder used as the Docker build context."
        if panel.runModal() == .OK, let url = panel.url {
            createBuildContextPath = url.path
            let defaultDockerfile = url.appendingPathComponent("Dockerfile").path
            if createDockerfilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               FileManager.default.fileExists(atPath: defaultDockerfile) {
                createDockerfilePath = defaultDockerfile
            }
        }
    }

    private func browseCreateDockerfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = "Choose a Dockerfile or Containerfile."
        if panel.runModal() == .OK, let url = panel.url {
            createDockerfilePath = url.path
            if createBuildContextPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                createBuildContextPath = url.deletingLastPathComponent().path
            }
        }
    }

    private func chooseHostPath() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose a file or folder to mount from the host."
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private var portMappings: [String] {
        parseList(createPorts)
    }

    private var editPortMappings: [String] {
        parseList(editPorts)
    }

    private var volumeMappings: [String] {
        parseList(createVolumes)
    }

    private var editVolumeMappings: [String] {
        parseList(editVolumes)
    }

    private var envVariables: [String] {
        parseList(createEnv)
    }

    private var editEnvVariables: [String] {
        parseList(editEnv)
    }

    private func removePortMapping(_ mapping: String) {
        let updated = portMappings.filter { $0 != mapping }
        createPorts = updated.joined(separator: ", ")
    }

    private func removeEditPortMapping(_ mapping: String) {
        let updated = editPortMappings.filter { $0 != mapping }
        editPorts = updated.joined(separator: ", ")
    }

    private func removeVolumeMapping(_ mapping: String) {
        let updated = volumeMappings.filter { $0 != mapping }
        createVolumes = updated.joined(separator: ", ")
    }

    private func removeEditVolumeMapping(_ mapping: String) {
        let updated = editVolumeMappings.filter { $0 != mapping }
        editVolumes = updated.joined(separator: ", ")
    }

    private func addEnvVariable() {
        let key = createEnvKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let value = createEnvValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = value.isEmpty ? key : "\(key)=\(value)"
        if createEnv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createEnv = entry
        } else {
            createEnv += ", \(entry)"
        }
        createEnvKey = ""
        createEnvValue = ""
    }

    private func addEditEnvVariable() {
        let key = editEnvKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let value = editEnvValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = value.isEmpty ? key : "\(key)=\(value)"
        if editEnv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editEnv = entry
        } else {
            editEnv += ", \(entry)"
        }
        editEnvKey = ""
        editEnvValue = ""
    }

    private func removeEnvVariable(_ variable: String) {
        let updated = envVariables.filter { $0 != variable }
        createEnv = updated.joined(separator: ", ")
    }

    private func removeEditEnvVariable(_ variable: String) {
        let updated = editEnvVariables.filter { $0 != variable }
        editEnv = updated.joined(separator: ", ")
    }
}

private struct WelcomeDashboardView: View {
    let containers: [Container]
    let imageCount: Int
    let isServiceRunning: Bool
    let onCreateContainer: () -> Void
    let onPullImage: () -> Void
    let onShowService: () -> Void
    let onSelectContainer: (Container) -> Void

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
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            Image("LogoHome")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("iContainer")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                HStack(spacing: 8) {
                    Circle()
                        .fill(isServiceRunning ? Color.green : Color.red)
                        .brightness(isServiceRunning ? 0.15 : 0.05)
                        .frame(width: 10, height: 10)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isServiceRunning)

            Button(action: onPullImage) {
                Label("Pull Image", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!isServiceRunning)

            if isServiceRunning {
                Button(action: onShowService) {
                    Label("Apple container service details", systemImage: "server.rack")
                }
                .buttonStyle(.bordered)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WelcomeContainerRow: View {
    let container: Container

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(container.status == .running ? Color.green : Color.red)
                .brightness(container.status == .running ? 0.15 : 0.05)
                .frame(width: 10, height: 10)
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
                Text("Container service")
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

private struct PathPickerRow: View {
    let title: String
    let placeholder: String
    @Binding var path: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField(placeholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                Button(action: action) {
                    Image(systemName: systemImage)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.bordered)
                .help("Choose \(title.lowercased())")
            }
        }
    }
}

private struct MappingPairsEditor: View {
    let title: String
    @Binding var mappingsText: String
    @Binding var firstValue: String
    @Binding var secondValue: String
    let isLoading: Bool
    let emptyText: String
    let firstTitle: String
    let secondTitle: String
    let firstPlaceholder: String
    let secondPlaceholder: String
    let formatText: String
    let iconName: String
    let addAction: () -> Void
    let removeAction: (String) -> Void
    let browseFirstAction: (() -> Void)?

    private var mappings: [String] {
        mappingsText
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, count: mappings.count)

            if mappings.isEmpty {
                Text(isLoading ? "Loading..." : emptyText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(mappings, id: \.self) { mapping in
                        let pair = splitMapping(mapping)
                        MappingRow(
                            iconName: iconName,
                            firstTitle: firstTitle,
                            firstValue: pair.first,
                            secondTitle: secondTitle,
                            secondValue: pair.second,
                            separator: ":",
                            removeAction: { removeAction(mapping) }
                        )
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                TextField(firstPlaceholder, text: $firstValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                if let browseFirstAction {
                    Button {
                        browseFirstAction()
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.bordered)
                    .help("Choose file or folder")
                }
                Text(":")
                    .foregroundColor(.secondary)
                TextField(secondPlaceholder, text: $secondValue)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Add \(title.lowercased())")
                .disabled(firstValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || secondValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text(formatText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func splitMapping(_ mapping: String) -> (first: String, second: String) {
        let parts = mapping.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (mapping, "")
        }
        return (String(parts[0]), String(parts[1]))
    }
}

private struct EnvironmentVariablesEditor: View {
    @Binding var environmentText: String
    @Binding var key: String
    @Binding var value: String
    let isLoading: Bool
    let emptyText: String
    let addAction: () -> Void
    let removeAction: (String) -> Void

    private var variables: [String] {
        environmentText
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Environment Variables", count: variables.count)

            if variables.isEmpty {
                Text(isLoading ? "Loading..." : emptyText)
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(variables, id: \.self) { variable in
                        let pair = splitVariable(variable)
                        MappingRow(
                            iconName: "textformat",
                            firstTitle: "Variable",
                            firstValue: pair.key,
                            secondTitle: "Value",
                            secondValue: pair.value,
                            separator: "=",
                            removeAction: { removeAction(variable) }
                        )
                    }
                }
            }

            HStack(alignment: .center, spacing: 10) {
                TextField("Variable", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Text("=")
                    .foregroundColor(.secondary)
                TextField("Value", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                Button {
                    addAction()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .help("Add environment variable")
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func splitVariable(_ variable: String) -> (key: String, value: String) {
        let parts = variable.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (variable, "")
        }
        return (String(parts[0]), String(parts[1]))
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if count > 0 {
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Spacer()
        }
    }
}

private struct MappingRow: View {
    let iconName: String
    let firstTitle: String
    let firstValue: String
    let secondTitle: String
    let secondValue: String
    let separator: String
    let removeAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundColor(.secondary)
                .frame(width: 18, height: 18)
                .padding(.top, 12)
            MappingValueColumn(title: firstTitle, value: firstValue)
            Text(separator)
                .foregroundColor(.secondary)
                .font(.callout.monospaced())
                .padding(.top, 22)
            MappingValueColumn(title: secondTitle, value: secondValue)
            Button(action: removeAction) {
                Image(systemName: "xmark.circle.fill")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .padding(.top, 12)
            .help("Remove")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MappingValueColumn: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "-" : value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WindowResizeConfigurator: NSViewRepresentable {
    let minSize: CGSize
    let shouldCenter: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(from: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(from: nsView, context: context)
    }

    private func configure(from view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = minSize
            if shouldCenter && !context.coordinator.didCenter {
                window.center()
                context.coordinator.didCenter = true
            }
        }
    }

    final class Coordinator {
        var didCenter = false
    }
}

struct ContainerRowView: View {
    let container: Container
    let onNavigateToTab: (Int) -> Void
    let onEditSettings: () -> Void
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
            ContainerActionsMenuItems(
                container: container,
                onNavigateToTab: onNavigateToTab,
                onEditSettings: onEditSettings,
                onRequestStop: {
                    showingStopConfirmation = true
                },
                onDelete: {
                    showingDeleteConfirmation = true
                }
            )
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
