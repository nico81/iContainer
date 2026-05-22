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
    @EnvironmentObject var releaseChecker: ContainerReleaseChecker
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
    @State private var sidebarSearchQuery: String = ""

    /// Containers filtered by the sidebar search query (case-insensitive match
    /// on name and image reference). An empty query returns all containers.
    private var filteredContainers: [Container] {
        let query = sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return containerManager.containers }
        return containerManager.containers.filter { container in
            container.name.localizedCaseInsensitiveContains(query)
                || (container.image?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Images filtered by the sidebar search query (case-insensitive match on
    /// the full reference `name:tag`). An empty query returns all images.
    private var filteredImages: [ContainerImage] {
        let query = sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return containerManager.images }
        return containerManager.images.filter { image in
            image.reference.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if !containerManager.missingDependencies.isEmpty {
                DependencyErrorView(errors: containerManager.missingDependencies)
            } else {
                mainContent
            }
        }
        .alert(
            "Container update available",
            isPresented: $releaseChecker.shouldPresentUpdateAlert
        ) {
            Button("Download") {
                let url = releaseChecker.latestReleaseURL ?? ContainerReleaseChecker.releasesPageURL
                NSWorkspace.shared.open(url)
            }
            Button("Later", role: .cancel) { }
        } message: {
            let latest = releaseChecker.latestVersion ?? "?"
            let installed = releaseChecker.installedVersion ?? "?"
            Text("A newer version of the Apple container service is available.\nInstalled v\(installed) · Latest v\(latest)")
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
        .onReceive(serviceManager.$serviceDetails) { details in
            releaseChecker.updateInstalledVersion(details?.version)
        }
        .task {
            await releaseChecker.checkForUpdateIfNeeded()
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
                    ForEach(filteredContainers) { container in
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
                    if filteredContainers.isEmpty && !sidebarSearchQuery.isEmpty {
                        Text("No matching containers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                DisclosureGroup(isExpanded: $isImagesExpanded) {
                    if serviceManager.isServiceRunning {
                        ForEach(filteredImages) { image in
                            ImageRowView(image: image)
                        }
                        if filteredImages.isEmpty && !sidebarSearchQuery.isEmpty {
                            Text("No matching images")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
        // The search field only makes sense when the service is running:
        // when it's stopped both containers and images are empty, so a
        // filter would just dangle next to a blank sidebar. We also reset
        // any leftover query so the next session starts clean.
        .applyIf(serviceManager.isServiceRunning) { view in
            view.searchable(
                text: $sidebarSearchQuery,
                placement: .sidebar,
                prompt: "Filter containers and images"
            )
        }
        .onChange(of: serviceManager.isServiceRunning) { _, isRunning in
            if !isRunning {
                sidebarSearchQuery = ""
            }
        }
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


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ContainerizationWrapper())
            .environmentObject(ServiceManager())
            .environmentObject(AppNavigation())
            .environmentObject(ContainerReleaseChecker())
    }
}
