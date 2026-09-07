import SwiftUI

/// "Import Image from Docker": lists the tagged images of the local Docker
/// installation and copies the selected one into Apple's `container` store
/// via `docker save` → `container image load`. Docker is never modified.
///
/// Importing a reference that already exists in the Apple store re-points
/// that tag at the imported image, so the sheet asks for confirmation first.
struct DockerImportSheet: View {
    @EnvironmentObject var dockerManager: DockerWrapper
    @EnvironmentObject var containerManager: ContainerizationWrapper
    let onClose: () -> Void

    private enum Phase: Equatable {
        case idle
        case saving(String)
        case loading(String)
        case done([String])
        case failed(String)
    }

    @State private var searchQuery = ""
    @State private var selectedID: DockerImage.ID?
    @State private var phase: Phase = .idle
    @State private var lastNote: String?
    @State private var showingOverwriteConfirmation = false
    @State private var pendingImage: DockerImage?

    private var importableImages: [DockerImage] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return dockerManager.images
            .filter { $0.reference != nil }
            .filter { query.isEmpty || ($0.reference ?? "").localizedCaseInsensitiveContains(query) }
    }

    private var selectedImage: DockerImage? {
        importableImages.first { $0.id == selectedID }
    }

    private var isBusy: Bool {
        switch phase {
        case .saving, .loading: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import Image from Docker")
                .font(.headline)

            content

            Spacer(minLength: 0)

            statusBox

            HStack {
                Button(importButtonTitle) { requestImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedImage == nil || isBusy || !dockerManager.availability.isAvailable)
                if isBusy {
                    ProgressView().scaleEffect(0.8)
                }
                Spacer()
                Button("Close") { onClose() }
                    .disabled(isBusy)
            }

            Text("Images are exported with `docker save` (linux/arm64 when available) and loaded with `container image load`. If the same reference already exists in Apple Container, its tag is moved to the imported image.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 600, idealWidth: 680, maxWidth: .infinity, minHeight: 460, idealHeight: 560, maxHeight: .infinity)
        .task {
            await dockerManager.refreshAvailability()
            await dockerManager.refreshImages()
        }
        .confirmationDialog(
            "Replace existing image?",
            isPresented: $showingOverwriteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace \(pendingImage?.reference ?? "")", role: .destructive) {
                if let image = pendingImage { runImport(image) }
                pendingImage = nil
            }
            Button("Cancel", role: .cancel) { pendingImage = nil }
        } message: {
            Text("\"\(pendingImage?.reference ?? "")\" already exists in Apple Container. Importing moves that tag to the Docker image; the current image stays available by digest.")
        }
    }

    // MARK: - Content per availability state

    @ViewBuilder
    private var content: some View {
        switch dockerManager.availability {
        case .unknown:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Checking Docker…").foregroundColor(.secondary)
            }
        case .notInstalled:
            unavailableBox(
                title: "Docker CLI not found",
                message: "Install Docker Desktop, or set the path to the `docker` binary in Settings → Advanced.",
                showOpenDocker: false
            )
        case .daemonUnavailable(let message):
            unavailableBox(
                title: "Docker isn't running",
                message: message,
                showOpenDocker: DockerWrapper.isDockerDesktopInstalled
            )
        case .available(let version):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Filter images", text: $searchQuery)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await dockerManager.refreshImages() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                    .disabled(dockerManager.isRefreshing)
                }
                imageList
                Text("Docker Engine \(version) · \(importableImages.count) tagged image\(importableImages.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var imageList: some View {
        List(importableImages, selection: $selectedID) { image in
            HStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .foregroundColor(.secondary)
                Text(image.reference ?? "")
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                if containerManager.hasImage(reference: image.reference ?? "") {
                    Text("in Apple Container")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .help("A reference with this name already exists in Apple Container")
                }
                Spacer()
                Text(image.sizeText)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                if let since = image.createdSince {
                    Text(since)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .trailing)
                }
            }
            .tag(image.id)
        }
        .frame(minHeight: 220)
        .overlay {
            if importableImages.isEmpty && !dockerManager.isRefreshing {
                Text(searchQuery.isEmpty ? "No tagged images in Docker." : "No images match the filter.")
                    .foregroundColor(.secondary)
            }
        }
    }

    private func unavailableBox(title: String, message: String, showOpenDocker: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
            HStack {
                if showOpenDocker {
                    Button("Open Docker Desktop") { DockerWrapper.openDockerDesktop() }
                }
                Button("Retry") { Task { await dockerManager.refreshAll() } }
            }
            .buttonStyle(.bordered)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    @ViewBuilder
    private var statusBox: some View {
        switch phase {
        case .idle:
            EmptyView()
        case .saving(let ref):
            Text("Exporting \(ref) from Docker…").font(.caption).foregroundColor(.secondary)
        case .loading(let ref):
            Text("Loading \(ref) into Apple Container…").font(.caption).foregroundColor(.secondary)
        case .done(let refs):
            VStack(alignment: .leading, spacing: 4) {
                Label("Imported \(refs.joined(separator: ", "))", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                if let lastNote {
                    Text(lastNote).font(.caption2).foregroundColor(.secondary)
                }
            }
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .textSelection(.enabled)
        }
    }

    private var importButtonTitle: String {
        if let image = selectedImage, let ref = image.reference, containerManager.hasImage(reference: ref) {
            return "Import & Replace"
        }
        return "Import"
    }

    // MARK: - Actions

    private func requestImport() {
        guard let image = selectedImage, let ref = image.reference else { return }
        if containerManager.hasImage(reference: ref) {
            pendingImage = image
            showingOverwriteConfirmation = true
        } else {
            runImport(image)
        }
    }

    private func runImport(_ image: DockerImage) {
        guard let ref = image.reference, !isBusy else { return }
        phase = .saving(ref)
        lastNote = nil
        Task {
            do {
                let outcome = try await dockerManager.saveImage(reference: ref, to: FileManager.default.temporaryDirectory)
                phase = .loading(ref)
                let loaded = await containerManager.loadImage(fromArchive: outcome.archiveURL)
                try? FileManager.default.removeItem(at: outcome.archiveURL)
                if let loaded {
                    if !outcome.filteredToArm64 {
                        lastNote = "The image has no linux/arm64 variant, so the full multi-platform image was imported."
                    }
                    phase = .done(loaded.isEmpty ? [ref] : loaded)
                } else {
                    phase = .failed(containerManager.lastErrorMessage ?? "container image load failed.")
                    containerManager.lastErrorMessage = nil
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
