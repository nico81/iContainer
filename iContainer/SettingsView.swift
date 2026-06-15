import SwiftUI
import AppKit

/// Settings window content. Hosted by the `Window("Settings", id: "settings")`
/// scene in `iContainerApp` (a regular `Window` instead of the `Settings`
/// scene to avoid a SwiftUI publish-loop on macOS 26).
///
/// Uses a `NavigationSplitView` sidebar — `TabView`'s tab bar doesn't
/// render reliably inside a non-`Settings` window on macOS 26, so we
/// surface the sections as sidebar entries instead, which also matches
/// the System Settings look introduced in recent macOS releases.
struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var showingResetConfirmation = false
    @State private var selection: SettingsSection = .general

    enum SettingsSection: String, Hashable, CaseIterable, Identifiable {
        case general
        case notifications
        case behavior
        case terminal
        case advanced

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general: return "General"
            case .notifications: return "Notifications"
            case .behavior: return "Behavior"
            case .terminal: return "Terminal"
            case .advanced: return "Advanced"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .notifications: return "bell.badge"
            case .behavior: return "slider.horizontal.3"
            case .terminal: return "terminal"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 220)
        } detail: {
            ScrollView {
                detailContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selection.label)
        }
        .frame(minWidth: 700, idealWidth: 760, minHeight: 480, idealHeight: 540)
        .confirmationDialog(
            "Reset all settings?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                settings.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All preferences will be restored to their default values.")
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .general: generalSection
        case .notifications: notificationsSection
        case .behavior: behaviorSection
        case .terminal: terminalSection
        case .advanced: advancedSection
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupBox("Appearance") {
                HStack {
                    Text("Theme")
                    Spacer()
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(ThemePreference.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
                Toggle("Show icon in menu bar", isOn: $settings.showMenuBarIcon)
                Toggle("Tint the sidebar with the accent color", isOn: $settings.sidebarTinted)
            }

            groupBox("Startup") {
                Toggle("Launch iContainer at login", isOn: $settings.launchAtLogin)
                Toggle("Start the container service when the app opens", isOn: $settings.autoStartContainerSystem)
            }

            groupBox("Container service on quit") {
                HStack {
                    Text("When quitting iContainer")
                    Spacer()
                    Picker("When quitting iContainer", selection: $settings.quitBehavior) {
                        ForEach(QuitBehavior.allCases) { behavior in
                            Text(behavior.label).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                }
                Text("Controls whether the Apple container service keeps running after iContainer quits. Choosing anything other than \"Ask each time\" skips the confirmation dialog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupBox("System notifications") {
                Toggle("Notify when a container stops or crashes", isOn: $settings.notifyContainerStopped)
                Toggle("Notify when an action fails", isOn: $settings.notifyActionFailed)
            }

            Text("Notifications are delivered by macOS. The first time one is posted, iContainer will ask for permission.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupBox("List refresh") {
                HStack {
                    Text("Refresh interval")
                    Spacer()
                    Picker("Refresh interval", selection: Binding(
                        get: { settings.refreshInterval },
                        set: { settings.setRefreshInterval($0) }
                    )) {
                        ForEach(RefreshIntervalOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
                Text("\"Manual\" disables polling. Changes to the interval take effect on the next app launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            groupBox("Confirmations for destructive actions") {
                Toggle("Ask before stopping a container", isOn: $settings.confirmStop)
                Toggle("Ask before deleting a container", isOn: $settings.confirmDelete)
                Toggle("Ask before prune", isOn: $settings.confirmPrune)
            }
        }
    }

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupBox("Shell") {
                HStack {
                    Text("Default shell")
                    Spacer()
                    Picker("Default shell", selection: $settings.defaultShell) {
                        ForEach(ShellPreference.allCases) { shell in
                            Text(shell.label).tag(shell)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }
                Text("If the chosen shell isn't available inside the container, iContainer falls back to /bin/sh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            groupBox("Font") {
                HStack {
                    Text("Font")
                    Spacer()
                    Picker("Font", selection: $settings.terminalFontName) {
                        ForEach(monospaceFontNames(), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                Stepper(value: $settings.terminalFontSize, in: 9...20, step: 1) {
                    HStack {
                        Text("Size")
                        Spacer()
                        Text("\(Int(settings.terminalFontSize)) pt")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            groupBox("Appearance") {
                Toggle("Force black background for terminal and logs", isOn: $settings.forceBlackTerminal)
            }

            groupBox("Logs") {
                Toggle("Hide noisy XPC connection errors", isOn: $settings.hideXPCNoiseInLogs)
                Text("Apple's `container` daemons log a `Connection invalid` error every time a CLI client disconnects. With frequent polling these dominate the service log view. The full logs are still produced by the system — only the display is filtered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            groupBox("CLI") {
                HStack {
                    TextField("Path to the `container` binary", text: $settings.customCliPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") {
                        if let path = chooseFile() {
                            settings.customCliPath = path
                        }
                    }
                }
                Text("Leave empty to search /usr/local/bin, /opt/homebrew/bin, and $PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            groupBox("Registry") {
                TextField("Default registry for pulls", text: $settings.defaultRegistry)
                    .textFieldStyle(.roundedBorder)
                Text("Used as the initial value of the Host field in the Registry Login sheet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Reset settings…", role: .destructive) {
                    showingResetConfirmation = true
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func groupBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } label: {
            Text(title)
                .font(.headline)
        }
    }

    private func monospaceFontNames() -> [String] {
        let candidates = [
            "Menlo", "Monaco", "Courier", "Courier New",
            "SF Mono", "Andale Mono", "PT Mono"
        ]
        let installed = NSFontManager.shared.availableFonts
        let filtered = candidates.filter { installed.contains($0) }
        if filtered.contains(settings.terminalFontName) || settings.terminalFontName.isEmpty {
            return filtered
        }
        return filtered + [settings.terminalFontName]
    }

    private func chooseFile() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the `container` binary."
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
