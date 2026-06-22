import SwiftUI

private let homeMountOptions = ["rw", "ro", "none"]

/// Sheet to create a new container machine via `container machine create`.
struct CreateMachineSheet: View {
    @EnvironmentObject var containerManager: ContainerizationWrapper
    /// Called with the new machine's name on success, so the caller can
    /// select it in the sidebar.
    let onCreated: (String) -> Void
    let onClose: () -> Void

    @State private var image = ""
    @State private var name = ""
    @State private var cpus = ""
    @State private var memory = ""
    @State private var homeMount = "rw"
    @State private var bootAfterCreate = true
    @State private var isCreating = false
    @State private var errorMessage: String?

    /// Machine names must start/end with a lowercase letter or digit and
    /// contain only lowercase letters, digits, and hyphens (CLI rule). An
    /// empty name is valid — the CLI assigns one.
    private var isNameValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        guard trimmed.allSatisfy({ allowed.contains($0) }) else { return false }
        return trimmed.first != "-" && trimmed.last != "-"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Machine").font(.headline)

            TextField("Image (e.g. alpine:3.22)", text: $image)
                .textFieldStyle(.roundedBorder)
            TextField("Name (optional)", text: $name)
                .textFieldStyle(.roundedBorder)
            if !isNameValid {
                Text("Name must use only lowercase letters, digits, and hyphens, starting and ending with a letter or digit.")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 10) {
                TextField("CPUs (optional)", text: $cpus)
                    .textFieldStyle(.roundedBorder)
                TextField("Memory, e.g. 4G (optional)", text: $memory)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Text("Home mount")
                Spacer()
                Picker("Home mount", selection: $homeMount) {
                    ForEach(homeMountOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Toggle("Boot after creation", isOn: $bootAfterCreate)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Create") { runCreate() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isCreating || image.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isNameValid)
                if isCreating { ProgressView().scaleEffect(0.8) }
                Spacer()
                Button("Close") { onClose() }
            }

            Text("Creating boots the machine unless turned off; downloads the image if needed.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 320)
    }

    private func runCreate() {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        containerManager.lastErrorMessage = nil
        Task {
            let created = await containerManager.createMachine(
                image: image,
                name: name,
                cpus: cpus,
                memory: memory,
                homeMount: homeMount,
                setDefault: false,
                boot: bootAfterCreate
            )
            isCreating = false
            if let created {
                onCreated(created)
            } else {
                errorMessage = containerManager.lastErrorMessage
                containerManager.lastErrorMessage = nil
            }
        }
    }
}

/// Sheet to change a machine's cpus / memory / home-mount. Changes apply
/// after the machine is restarted (per the CLI).
struct EditMachineConfigSheet: View {
    let machineId: String
    @EnvironmentObject var containerManager: ContainerizationWrapper
    @Environment(\.dismiss) private var dismiss

    @State private var cpus = ""
    @State private var memory = ""
    @State private var homeMount = "rw"
    @State private var isSaving = false
    @State private var saved = false
    @State private var isRestarting = false
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Machine Configuration").font(.headline)

            HStack(spacing: 10) {
                TextField("CPUs", text: $cpus)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: cpus) { _, _ in saved = false }
                TextField("Memory, e.g. 4G", text: $memory)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: memory) { _, _ in saved = false }
            }

            HStack {
                Text("Home mount")
                Spacer()
                Picker("Home mount", selection: $homeMount) {
                    ForEach(homeMountOptions, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: homeMount) { _, _ in saved = false }
            }

            if saved {
                Label(
                    isRunning
                        ? "Saved. Restart the machine to apply the new configuration."
                        : "Saved. The new configuration applies the next time the machine starts.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundColor(.green)
            }

            HStack {
                Button("Save") { runSave() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving || isRestarting)
                if isSaving || isRestarting { ProgressView().scaleEffect(0.8) }
                Spacer()
                if saved && isRunning {
                    Button("Restart now") { runRestart() }
                        .disabled(isRestarting)
                }
                Button(saved ? "Done" : "Close") { dismiss() }
            }

            Text("Changes take effect after the machine is restarted.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(minWidth: 480, minHeight: 240)
        .task {
            if let details = await containerManager.inspectMachine(machineId: machineId) {
                cpus = details.cpus.map(String.init) ?? ""
                memory = Self.memoryField(details.memoryBytes)
                homeMount = details.homeMount ?? "rw"
                isRunning = details.status.isRunning
            }
        }
    }

    /// Bytes → a `set`-compatible memory string (e.g. 2147483648 → "2G").
    static func memoryField(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "" }
        let gib = Double(bytes) / 1_073_741_824.0
        if gib == gib.rounded() { return "\(Int(gib))G" }
        return String(format: "%.1fG", gib)
    }

    private func runSave() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            let ok = await containerManager.setMachineConfig(
                machineId: machineId,
                cpus: cpus,
                memory: memory,
                homeMount: homeMount
            )
            isSaving = false
            saved = ok
        }
    }

    private func runRestart() {
        guard !isRestarting else { return }
        isRestarting = true
        Task {
            await containerManager.stopMachine(machineId: machineId)
            await containerManager.startMachine(machineId: machineId)
            isRestarting = false
            dismiss()
        }
    }
}
