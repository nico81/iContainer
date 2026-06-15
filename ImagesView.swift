import SwiftUI

struct ImagesView: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingPullAlert = false
    @State private var pullReference = ""

    var body: some View {
        List {
            ForEach(containerManager.images) { image in
                ImageRowView(image: image)
            }
        }
        .navigationTitle("Images")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingPullAlert = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
            }
        }
        .task {
            await containerManager.refreshImages()
        }
        .alert("Pull Image", isPresented: $showingPullAlert) {
            TextField("repository:tag", text: $pullReference)
            Button("Pull") {
                let reference = pullReference.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reference.isEmpty {
                    Task {
                        await containerManager.pullImage(reference: reference)
                        pullReference = ""
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pullReference = ""
            }
        } message: {
            Text("Enter the image reference to pull from the registry.")
        }
    }
}

struct ImageRowView: View {
    let image: ContainerImage
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var rowInspectDetails: ImageInspectDetails?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink {
                ImageDetailView(image: image)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(image.displayName)
                        .font(.headline)
                    Text(rowInspectDetails?.variantsTotalText ?? image.displaySize)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                if isDeleting || containerManager.updatingImageIDs.contains(image.id) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                        .padding(3)
                } else {
                    Image(systemName: "trash")
                        .frame(width: 16, height: 16)
                        .padding(3)
                }
            }
            .actionButtonStyle(circular: true)
            .controlSize(.small)
            .disabled(isDeleting || containerManager.updatingImageIDs.contains(image.id))
            // Same 60pt trailing area as the container rows' start/stop
            // buttons, so the delete buttons line up across both lists.
            .frame(width: 60)
        }
        .confirmationDialog("Delete Image?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                Task {
                    await containerManager.deleteImage(reference: image.reference.isEmpty ? image.id : image.reference)
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete image \"\(image.displayName)\"? This may affect containers using it.")
        }
        .task(id: image.id) {
            let reference = image.reference.isEmpty ? image.id : image.reference
            if let output = await containerManager.inspectImage(reference: reference) {
                rowInspectDetails = parseInspectDetails(output)
            } else {
                rowInspectDetails = nil
            }
        }
    }
}

struct ImageDetailView: View {
    let image: ContainerImage
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @State private var rawDetailsText: String = ""
    @State private var inspectDetails: ImageInspectDetails?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading Details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(image.displayName)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("ID: \(image.id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospaced()
                    }

                    DetailSection(title: "Image Information", icon: "shippingbox") {
                        DetailRow(label: "Reference", value: inspectDetails?.reference ?? image.reference)
                        DetailRow(label: "Digest", value: inspectDetails?.digest ?? image.id)
                        DetailRow(label: "Media Type", value: inspectDetails?.mediaType ?? "-")
                        DetailRow(label: "OS/Arch", value: inspectDetails?.platform ?? "-")
                        DetailRow(label: "Created", value: inspectDetails?.created ?? image.displayCreated)
                        let onDisk = image.displaySize == "-" ? (inspectDetails?.variantsTotalText ?? "-") : image.displaySize
                        DetailRow(label: "On Disk", value: onDisk)
                        if let indexSize = inspectDetails?.indexSizeText {
                            DetailRow(label: "Index Size", value: indexSize)
                        }
                        if let variantsSize = inspectDetails?.variantsTotalText {
                            DetailRow(label: "Variants Total", value: variantsSize)
                        }
                    }

                    DetailSection(title: "Raw Inspect Output", icon: "terminal") {
                        Text(formattedInspectOutput)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Image Details")
        .task(id: image.id) {
            await loadDetails()
        }
    }

    private func loadDetails() async {
        isLoading = true
        let reference = image.reference.isEmpty ? image.id : image.reference
        if let output = await containerManager.inspectImage(reference: reference) {
            rawDetailsText = output.trimmingCharacters(in: .whitespacesAndNewlines)
            inspectDetails = parseInspectDetails(rawDetailsText)
        } else {
            rawDetailsText = ""
            inspectDetails = nil
        }
        isLoading = false
    }

    private var formattedInspectOutput: String {
        let trimmed = rawDetailsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No details available." }
        guard let data = trimmed.data(using: .utf8) else { return trimmed }
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            return String(data: pretty, encoding: .utf8) ?? trimmed
        } catch {
            return trimmed
        }
    }
}

private struct ImageInspectDetails: Equatable {
    let reference: String?
    let digest: String?
    let created: String?
    let indexSizeText: String?
    let variantsTotalText: String?
    let platform: String?
    let mediaType: String?
}

private func parseInspectDetails(_ raw: String) -> ImageInspectDetails? {
    guard let data = raw.data(using: .utf8) else { return nil }
    do {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        let dict: [String: Any]
        if let array = json as? [[String: Any]], let first = array.first {
            dict = first
        } else if let object = json as? [String: Any] {
            dict = object
        } else {
            return nil
        }
        let descriptor = dict["descriptor"] as? [String: Any]
        let annotations = descriptor?["annotations"] as? [String: Any]
        let index = dict["index"] as? [String: Any]
        let variants = dict["variants"] as? [[String: Any]] ?? []

        let reference = stringIn(dict, keys: ["reference", "name"])
            ?? stringIn(annotations ?? [:], keys: ["io.containerd.image.name", "org.opencontainers.image.ref.name"])
        let digest = stringIn(index ?? [:], keys: ["digest"])
            ?? stringIn(descriptor ?? [:], keys: ["digest"])
            ?? stringIn(dict, keys: ["digest"])
        let mediaType = stringIn(index ?? [:], keys: ["mediaType"])
            ?? stringIn(descriptor ?? [:], keys: ["mediaType"])
            ?? stringIn(dict, keys: ["mediaType"])
        let created = stringIn(annotations ?? [:], keys: ["org.opencontainers.image.created"])
            ?? createdFromVariants(variants)
            ?? deepString(in: dict, keys: ["created", "createdAt", "created_at"])
            ?? deepString(in: dict, keys: ["config", "created"])

        let indexSizeBytes = (index?["size"] as? NSNumber)?.int64Value
        let variantsTotalBytes = totalVariantsSizeBytes(variants)
        let indexSizeText = indexSizeBytes != nil
            ? ByteCountFormatter.string(fromByteCount: indexSizeBytes!, countStyle: .file)
            : nil
        let variantsTotalText = variantsTotalBytes != nil
            ? ByteCountFormatter.string(fromByteCount: variantsTotalBytes!, countStyle: .file)
            : nil

        let platform = platformFromVariants(variants)
        return ImageInspectDetails(
            reference: reference,
            digest: digest,
            created: created,
            indexSizeText: indexSizeText,
            variantsTotalText: variantsTotalText,
            platform: platform,
            mediaType: mediaType
        )
    } catch {
        return nil
    }
}

private func stringIn(_ dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = dict[key] as? String {
            return value
        }
        if let value = dict[key] as? NSNumber {
            return value.stringValue
        }
    }
    return nil
}

private func deepString(in dict: [String: Any], keys: [String]) -> String? {
    if keys.count == 1, let value = dict[keys[0]] as? String {
        return value
    }
    if keys.count == 2, let inner = dict[keys[0]] as? [String: Any] {
        return deepString(in: inner, keys: [keys[1]])
    }
    for (_, value) in dict {
        if let inner = value as? [String: Any], let found = deepString(in: inner, keys: keys) {
            return found
        }
        if let array = value as? [[String: Any]] {
            for element in array {
                if let found = deepString(in: element, keys: keys) {
                    return found
                }
            }
        }
    }
    return nil
}

private func deepNumber(in dict: [String: Any], keys: [String]) -> NSNumber? {
    if keys.count == 1, let value = dict[keys[0]] as? NSNumber {
        return value
    }
    if keys.count == 2, let inner = dict[keys[0]] as? [String: Any] {
        return deepNumber(in: inner, keys: [keys[1]])
    }
    for (_, value) in dict {
        if let inner = value as? [String: Any], let found = deepNumber(in: inner, keys: keys) {
            return found
        }
        if let array = value as? [[String: Any]] {
            for element in array {
                if let found = deepNumber(in: element, keys: keys) {
                    return found
                }
            }
        }
    }
    return nil
}

private func numberFromIndexOrVariant(index: [String: Any]?, variants: [[String: Any]]) -> Int64? {
    if let size = index?["size"] as? NSNumber {
        return size.int64Value
    }
    for variant in variants {
        if let size = variant["size"] as? NSNumber, size.int64Value > 0 {
            return size.int64Value
        }
    }
    return nil
}

private func platformFromVariants(_ variants: [[String: Any]]) -> String? {
    for variant in variants {
        guard let platform = variant["platform"] as? [String: Any] else { continue }
        let os = platform["os"] as? String
        let arch = platform["architecture"] as? String
        let variantName = platform["variant"] as? String
        if let os, let arch, os != "unknown", arch != "unknown" {
            if let variantName, !variantName.isEmpty {
                return "\(os)/\(arch)/\(variantName)"
            }
            return "\(os)/\(arch)"
        }
    }
    return nil
}

private func createdFromVariants(_ variants: [[String: Any]]) -> String? {
    for variant in variants {
        if let config = variant["config"] as? [String: Any],
           let created = config["created"] as? String {
            return created
        }
    }
    return nil
}

private func totalVariantsSizeBytes(_ variants: [[String: Any]]) -> Int64? {
    var total: Int64 = 0
    var found = false
    for variant in variants {
        if let size = variant["size"] as? NSNumber {
            total += size.int64Value
            found = true
        }
    }
    return found ? total : nil
}
