import SwiftUI

/// Sheet for the docker-compose MVP: shows what a parsed compose file would
/// create (and what it had to ignore), then drives `composeUp` / `composeDown`.
/// One sheet covers both directions — Down only needs the project name,
/// which is derived the same way Up derives it, from the file's parent
/// directory — so there's no separate "active projects" list to maintain.
struct ComposeSheet: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    let fileURL: URL
    let parsed: ParsedComposeFile
    let onClose: () -> Void

    @State private var isRunning = false
    @State private var outcomes: [ContainerizationWrapper.ComposeServiceOutcome] = []
    @State private var downResultMessage: String?
    @State private var downSucceeded = true

    private var projectName: String {
        ComposeParser.sanitizedProjectName(fileURL.deletingLastPathComponent().lastPathComponent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compose Project: \(projectName)")
                        .font(.headline)
                    Text(fileURL.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                dnsStatusLine

                if !parsed.ignoredDirectives.isEmpty {
                    ignoredDirectivesBox
                }

                servicesList

                if !outcomes.isEmpty {
                    upResultBox
                }

                if let downResultMessage {
                    Text(downResultMessage)
                        .font(.caption)
                        .foregroundColor(downSucceeded ? .green : .red)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Up") { runUp() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isRunning || parsed.services.isEmpty)

                    Button("Down") { runDown() }
                        .disabled(isRunning)

                    if isRunning {
                        ProgressView().scaleEffect(0.8)
                    }

                    Spacer()

                    Button("Close") { onClose() }
                }

                Text("Containers are named \"\(projectName)-<service>\" (unless a service sets container_name) and share a single per-project network. Directives the container CLI can't map are ignored, not fatal.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
        .frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity, minHeight: 420, idealHeight: 560, maxHeight: .infinity)
    }

    /// Whether services will be able to find each other by name depends on
    /// the container service having a DNS domain configured — surface that
    /// up front instead of letting the user discover it from a failing app.
    @ViewBuilder
    private var dnsStatusLine: some View {
        if let domain = containerManager.systemDNSDomain {
            Label("Services reach each other by container name (\(projectName)-<service>, or <name>.\(domain)) through the service DNS domain \"\(domain)\". Compose service names alone (e.g. \"db\") are not aliased.", systemImage: "network")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label("No DNS domain is configured for the container service — services can only reach each other by IP address.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("To enable names: add `[dns]` and `domain = \"test\"` to ~/.config/container/config.toml, restart the container service, then run `sudo container system dns create test` once.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var ignoredDirectivesBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Ignored directives", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.orange)
            ForEach(parsed.ignoredDirectives, id: \.self) { message in
                Text("• \(message)")
                    .font(.caption)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    private var servicesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Services", count: parsed.services.count)
            if parsed.services.isEmpty {
                Text("No services found in this file.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(parsed.services, id: \.name) { service in
                        serviceRow(service)
                    }
                }
            }
        }
    }

    private func serviceRow(_ service: ComposeService) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "shippingbox")
                    .foregroundColor(.secondary)
                Text(service.resolvedContainerName(project: projectName))
                    .font(.callout.monospaced())
                Spacer()
                if service.image?.isEmpty ?? true {
                    Text("no image").font(.caption2).foregroundColor(.red)
                }
            }
            if let image = service.image, !image.isEmpty {
                Text(image).font(.caption).foregroundColor(.secondary)
            }
            if !service.ports.isEmpty {
                Text("Ports: \(service.ports.joined(separator: ", "))").font(.caption2).foregroundColor(.secondary)
            }
            if !service.volumes.isEmpty {
                Text("Volumes: \(service.volumes.joined(separator: ", "))").font(.caption2).foregroundColor(.secondary)
            }
            if !service.environment.isEmpty {
                Text("Env: \(service.environment.joined(separator: ", "))").font(.caption2).foregroundColor(.secondary)
            }
            if !service.command.isEmpty {
                Text("Command: \(service.command.joined(separator: " "))").font(.caption2).foregroundColor(.secondary)
            }
            if !service.dependsOn.isEmpty {
                Text("Depends on: \(service.dependsOn.joined(separator: ", "))").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    private var upResultBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(outcomes) { outcome in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(outcome.succeeded ? .green : .red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(outcome.containerName)
                            .font(.caption.monospaced())
                        if let detail = outcome.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: AppRadius.small))
    }

    private func runUp() {
        guard !isRunning else { return }
        isRunning = true
        downResultMessage = nil
        Task {
            let result = await containerManager.composeUp(parsedFile: parsed, project: projectName)
            outcomes = result
            isRunning = false
        }
    }

    private func runDown() {
        guard !isRunning else { return }
        isRunning = true
        outcomes = []
        Task {
            let ok = await containerManager.composeDown(project: projectName)
            downSucceeded = ok
            downResultMessage = ok
                ? "Project \"\(projectName)\" stopped and removed."
                : "Some containers could not be stopped or removed. \(containerManager.lastErrorMessage ?? "")"
            isRunning = false
        }
    }
}
