import Foundation
import Combine
import SwiftUI
import ServiceManagement

// MARK: - Enums

nonisolated enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

nonisolated enum QuitBehavior: String, CaseIterable, Identifiable {
    case ask
    case stopService
    case leaveRunning

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ask: return "Ask each time"
        case .stopService: return "Always stop the container service"
        case .leaveRunning: return "Always leave the container service running"
        }
    }
}

nonisolated enum ShellPreference: String, CaseIterable, Identifiable {
    case sh
    case bash
    case zsh

    var id: String { rawValue }

    var label: String { rawValue }

    /// Absolute path that the in-container shell exec should try first.
    var containerPath: String {
        switch self {
        case .sh: return "/bin/sh"
        case .bash: return "/bin/bash"
        case .zsh: return "/bin/zsh"
        }
    }
}

/// Allowed refresh cadences for the polling timers. `manual` disables the
/// timer entirely and leaves the UI responsible for triggering refreshes.
nonisolated enum RefreshIntervalOption: Double, CaseIterable, Identifiable {
    case manual = 0
    case fast = 2
    case normal = 5
    case slow = 10

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .fast: return "2 seconds"
        case .normal: return "5 seconds"
        case .slow: return "10 seconds"
        }
    }

    /// Picks the closest option for a stored numeric value.
    static func from(_ value: Double) -> RefreshIntervalOption {
        Self.allCases.min(by: { abs($0.rawValue - value) < abs($1.rawValue - value) }) ?? .normal
    }
}

// MARK: - SettingsManager

@MainActor
final class SettingsManager: ObservableObject {
    /// Shared instance used by code paths that can't easily receive it via
    /// `@EnvironmentObject` (notably the cached `ContainerShellSession`).
    static let shared = SettingsManager()

    // UserDefaults keys and built-in defaults are exposed at the type
    // level so `nonisolated` helpers (Process-spawning code paths) and
    // App-scene `@AppStorage` declarations can read them without
    // crossing into MainActor isolation.
    nonisolated enum Keys {
        static let theme = "settings.theme"
        static let launchAtLogin = "settings.launchAtLogin"
        static let autoStartContainerSystem = "settings.autoStartContainerSystem"
        static let showMenuBarIcon = "settings.showMenuBarIcon"
        static let notifyContainerStopped = "settings.notifyContainerStopped"
        static let notifyActionFailed = "settings.notifyActionFailed"
        static let refreshIntervalSeconds = "settings.refreshIntervalSeconds"
        static let confirmStop = "settings.confirmStop"
        static let confirmDelete = "settings.confirmDelete"
        static let confirmPrune = "settings.confirmPrune"
        static let defaultShell = "settings.defaultShell"
        static let terminalFontName = "settings.terminalFontName"
        static let terminalFontSize = "settings.terminalFontSize"
        static let forceBlackTerminal = "settings.forceBlackTerminal"
        static let customCliPath = "settings.customCliPath"
        static let defaultRegistry = "settings.defaultRegistry"
        static let quitBehavior = "settings.quitBehavior"
        static let hideXPCNoiseInLogs = "settings.hideXPCNoiseInLogs"
        static let sidebarTinted = "settings.sidebarTinted"
    }

    nonisolated enum Defaults {
        static let theme: ThemePreference = .system
        static let launchAtLogin = false
        static let autoStartContainerSystem = false
        static let showMenuBarIcon = true
        static let notifyContainerStopped = true
        static let notifyActionFailed = true
        static let refreshIntervalSeconds: Double = 5
        static let confirmStop = true
        static let confirmDelete = true
        static let confirmPrune = true
        static let defaultShell: ShellPreference = .sh
        static let terminalFontName = "Menlo"
        static let terminalFontSize: Double = 12
        static let forceBlackTerminal = false
        static let customCliPath = ""
        static let defaultRegistry = "registry-1.docker.io"
        static let quitBehavior: QuitBehavior = .ask
        static let hideXPCNoiseInLogs = true
        static let sidebarTinted = true
    }

    // MARK: Published preferences

    @Published var theme: ThemePreference {
        didSet { store.set(theme.rawValue, forKey: Keys.theme) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            store.set(launchAtLogin, forKey: Keys.launchAtLogin)
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    @Published var autoStartContainerSystem: Bool {
        didSet { store.set(autoStartContainerSystem, forKey: Keys.autoStartContainerSystem) }
    }

    @Published var showMenuBarIcon: Bool {
        didSet { store.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon) }
    }

    @Published var notifyContainerStopped: Bool {
        didSet { store.set(notifyContainerStopped, forKey: Keys.notifyContainerStopped) }
    }

    @Published var notifyActionFailed: Bool {
        didSet { store.set(notifyActionFailed, forKey: Keys.notifyActionFailed) }
    }

    @Published var refreshIntervalSeconds: Double {
        didSet { store.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds) }
    }

    @Published var confirmStop: Bool {
        didSet { store.set(confirmStop, forKey: Keys.confirmStop) }
    }

    @Published var confirmDelete: Bool {
        didSet { store.set(confirmDelete, forKey: Keys.confirmDelete) }
    }

    @Published var confirmPrune: Bool {
        didSet { store.set(confirmPrune, forKey: Keys.confirmPrune) }
    }

    @Published var defaultShell: ShellPreference {
        didSet { store.set(defaultShell.rawValue, forKey: Keys.defaultShell) }
    }

    @Published var terminalFontName: String {
        didSet { store.set(terminalFontName, forKey: Keys.terminalFontName) }
    }

    @Published var terminalFontSize: Double {
        didSet { store.set(terminalFontSize, forKey: Keys.terminalFontSize) }
    }

    @Published var forceBlackTerminal: Bool {
        didSet { store.set(forceBlackTerminal, forKey: Keys.forceBlackTerminal) }
    }

    @Published var customCliPath: String {
        didSet { store.set(customCliPath, forKey: Keys.customCliPath) }
    }

    @Published var defaultRegistry: String {
        didSet { store.set(defaultRegistry, forKey: Keys.defaultRegistry) }
    }

    @Published var quitBehavior: QuitBehavior {
        didSet { store.set(quitBehavior.rawValue, forKey: Keys.quitBehavior) }
    }

    /// When on, filters out the verbose XPC connection lifecycle errors
    /// that Apple's `container` daemons emit on every CLI invocation
    /// (e.g. `Connection invalid` from `container-core-images`). These
    /// rows are cosmetic noise — they fire whenever a short-lived client
    /// disconnects — and iContainer's frequent polling makes them
    /// dominate the logs view. The setting only hides them from display;
    /// the underlying service logs are unchanged.
    @Published var hideXPCNoiseInLogs: Bool {
        didSet { store.set(hideXPCNoiseInLogs, forKey: Keys.hideXPCNoiseInLogs) }
    }

    /// When off, the sidebar drops its flat accent-color wash and stays
    /// fully transparent (the plain system sidebar material).
    @Published var sidebarTinted: Bool {
        didSet { store.set(sidebarTinted, forKey: Keys.sidebarTinted) }
    }

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store

        // Initialize the @Published storage directly via the property
        // wrapper (`_property = Published(initialValue:)`) instead of
        // through the wrappedValue setter. The setter fires
        // `objectWillChange.send()` on every assignment, and even though
        // there are no subscribers yet at init time, SwiftUI on macOS 26
        // can mis-attribute those publishes to the surrounding scene
        // installation and trigger a "Publishing changes from within
        // view updates" rebuild loop. Underscore-prefixed assignment
        // sets the storage and skips the publisher entirely.
        _theme = Published(initialValue: (store.string(forKey: Keys.theme).flatMap(ThemePreference.init(rawValue:))) ?? Defaults.theme)
        _launchAtLogin = Published(initialValue: store.object(forKey: Keys.launchAtLogin) as? Bool ?? Defaults.launchAtLogin)
        _autoStartContainerSystem = Published(initialValue: store.object(forKey: Keys.autoStartContainerSystem) as? Bool ?? Defaults.autoStartContainerSystem)
        _showMenuBarIcon = Published(initialValue: store.object(forKey: Keys.showMenuBarIcon) as? Bool ?? Defaults.showMenuBarIcon)
        _notifyContainerStopped = Published(initialValue: store.object(forKey: Keys.notifyContainerStopped) as? Bool ?? Defaults.notifyContainerStopped)
        _notifyActionFailed = Published(initialValue: store.object(forKey: Keys.notifyActionFailed) as? Bool ?? Defaults.notifyActionFailed)
        _refreshIntervalSeconds = Published(initialValue: store.object(forKey: Keys.refreshIntervalSeconds) as? Double ?? Defaults.refreshIntervalSeconds)
        _confirmStop = Published(initialValue: store.object(forKey: Keys.confirmStop) as? Bool ?? Defaults.confirmStop)
        _confirmDelete = Published(initialValue: store.object(forKey: Keys.confirmDelete) as? Bool ?? Defaults.confirmDelete)
        _confirmPrune = Published(initialValue: store.object(forKey: Keys.confirmPrune) as? Bool ?? Defaults.confirmPrune)
        _defaultShell = Published(initialValue: (store.string(forKey: Keys.defaultShell).flatMap(ShellPreference.init(rawValue:))) ?? Defaults.defaultShell)
        _terminalFontName = Published(initialValue: store.string(forKey: Keys.terminalFontName) ?? Defaults.terminalFontName)
        _terminalFontSize = Published(initialValue: store.object(forKey: Keys.terminalFontSize) as? Double ?? Defaults.terminalFontSize)
        _forceBlackTerminal = Published(initialValue: store.object(forKey: Keys.forceBlackTerminal) as? Bool ?? Defaults.forceBlackTerminal)
        _customCliPath = Published(initialValue: store.string(forKey: Keys.customCliPath) ?? Defaults.customCliPath)
        _defaultRegistry = Published(initialValue: store.string(forKey: Keys.defaultRegistry) ?? Defaults.defaultRegistry)
        _quitBehavior = Published(initialValue: (store.string(forKey: Keys.quitBehavior).flatMap(QuitBehavior.init(rawValue:))) ?? Defaults.quitBehavior)
        _hideXPCNoiseInLogs = Published(initialValue: store.object(forKey: Keys.hideXPCNoiseInLogs) as? Bool ?? Defaults.hideXPCNoiseInLogs)
        _sidebarTinted = Published(initialValue: store.object(forKey: Keys.sidebarTinted) as? Bool ?? Defaults.sidebarTinted)
    }

    // MARK: Helpers

    var refreshInterval: RefreshIntervalOption {
        RefreshIntervalOption.from(refreshIntervalSeconds)
    }

    func setRefreshInterval(_ option: RefreshIntervalOption) {
        refreshIntervalSeconds = option.rawValue
    }

    /// Removes all settings keys and snaps the in-memory state back to
    /// defaults. The matching `didSet` calls also re-apply side effects
    /// (e.g. unregistering launch-at-login).
    func resetAll() {
        let allKeys: [String] = [
            Keys.theme, Keys.launchAtLogin, Keys.autoStartContainerSystem, Keys.showMenuBarIcon,
            Keys.notifyContainerStopped, Keys.notifyActionFailed, Keys.refreshIntervalSeconds,
            Keys.confirmStop, Keys.confirmDelete, Keys.confirmPrune, Keys.defaultShell,
            Keys.terminalFontName, Keys.terminalFontSize, Keys.forceBlackTerminal,
            Keys.customCliPath, Keys.defaultRegistry, Keys.quitBehavior,
            Keys.hideXPCNoiseInLogs, Keys.sidebarTinted
        ]
        for key in allKeys { store.removeObject(forKey: key) }

        theme = Defaults.theme
        launchAtLogin = Defaults.launchAtLogin
        autoStartContainerSystem = Defaults.autoStartContainerSystem
        showMenuBarIcon = Defaults.showMenuBarIcon
        notifyContainerStopped = Defaults.notifyContainerStopped
        notifyActionFailed = Defaults.notifyActionFailed
        refreshIntervalSeconds = Defaults.refreshIntervalSeconds
        confirmStop = Defaults.confirmStop
        confirmDelete = Defaults.confirmDelete
        confirmPrune = Defaults.confirmPrune
        defaultShell = Defaults.defaultShell
        terminalFontName = Defaults.terminalFontName
        terminalFontSize = Defaults.terminalFontSize
        forceBlackTerminal = Defaults.forceBlackTerminal
        customCliPath = Defaults.customCliPath
        defaultRegistry = Defaults.defaultRegistry
        quitBehavior = Defaults.quitBehavior
        hideXPCNoiseInLogs = Defaults.hideXPCNoiseInLogs
        sidebarTinted = Defaults.sidebarTinted
    }

    /// Registers or unregisters the app as a login item via `SMAppService`.
    /// Errors are intentionally swallowed: the toggle reverts on its own if
    /// the user denies the system prompt.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status == .enabled {
                    try service.unregister()
                }
            }
        } catch {
            // Best-effort: the UI will reflect the actual status on next read
            // and the user can retry the toggle.
        }
    }
}

// MARK: - Nonisolated helpers

extension SettingsManager {
    // The two helpers below are called from `Process`-spawning code
    // (`ContainerizationWrapper.runCommandBlocking`, `ServiceManager`'s
    // background tasks, `ContainerShellSession.startIfNeeded`) which run
    // off the main actor. The keys and shell paths are duplicated here
    // as literals so we don't reach into MainActor-isolated state —
    // they must stay in sync with `Keys` / `ShellPreference`.

    /// Custom CLI path the user has typed into Settings, or `nil` when the
    /// field is blank or no longer points to an executable file.
    nonisolated static func storedCustomCLIPath() -> String? {
        let raw = UserDefaults.standard.string(forKey: "settings.customCliPath") ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return FileManager.default.isExecutableFile(atPath: trimmed) ? trimmed : nil
    }

    /// In-container shell path to try first when starting an exec session.
    nonisolated static func storedShellContainerPath() -> String {
        let raw = UserDefaults.standard.string(forKey: "settings.defaultShell") ?? "sh"
        switch raw {
        case "bash": return "/bin/bash"
        case "zsh": return "/bin/zsh"
        default: return "/bin/sh"
        }
    }

    /// Polling cadence read straight from UserDefaults. Used by code
    /// paths that need the current value without touching the MainActor-
    /// isolated singleton (which can cause a republish loop if accessed
    /// during view installation).
    nonisolated static func storedRefreshIntervalSeconds() -> Double {
        let raw = UserDefaults.standard.object(forKey: "settings.refreshIntervalSeconds") as? Double
        return raw ?? 5
    }

    /// Quit-time behavior, read straight from UserDefaults so
    /// `AppQuitDelegate` doesn't have to touch the singleton from inside
    /// `applicationShouldTerminate`.
    nonisolated static func storedQuitBehavior() -> QuitBehavior {
        let raw = UserDefaults.standard.string(forKey: "settings.quitBehavior") ?? ""
        return QuitBehavior(rawValue: raw) ?? .ask
    }
}
