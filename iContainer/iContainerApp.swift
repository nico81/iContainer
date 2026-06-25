//
//  iContainerApp.swift
//  iContainer
//
//  Created by Nico Emanuelli on 11/07/25.
//

import SwiftUI
import AppKit

@main
struct iContainerApp: App {
    @NSApplicationDelegateAdaptor(AppQuitDelegate.self) private var appQuitDelegate
    @StateObject private var containerManager = ContainerizationWrapper()
    @StateObject private var serviceManager = ServiceManager()
    @StateObject private var appNavigation = AppNavigation()
    @StateObject private var releaseChecker = ContainerReleaseChecker()
    @StateObject private var appReleaseChecker = AppReleaseChecker()

    // Scene-level prefs use `@AppStorage` (SwiftUI-safe) directly on
    // the UserDefaults keys that `SettingsManager` writes to. This
    // keeps the bindings out of the singleton's publish chain, which
    // is what caused the publish-during-view-update loop on macOS 26.
    @AppStorage("settings.theme") private var themeRaw = "system"
    @AppStorage("settings.autoStartContainerSystem") private var autoStartContainerSystem = false
    @AppStorage("settings.showMenuBarIcon") private var showMenuBarIcon = true

    private var themeColorScheme: ColorScheme? {
        ThemePreference(rawValue: themeRaw)?.colorScheme
    }

    /// `MenuBarExtra(isInserted:)` on macOS 26 keeps invoking the
    /// binding's `set`, which — with `@AppStorage` — would write back
    /// to `UserDefaults` and re-trigger the observer, looping forever.
    /// We expose the `@AppStorage` value via a get-only binding whose
    /// `set` discards writes: SwiftUI still observes external changes
    /// (via `@AppStorage`), but macOS can't feed the value back in.
    private var menuBarIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarIcon },
            set: { _ in /* intentionally ignored — see comment above */ }
        )
    }

    var body: some Scene {
        Window("iContainer", id: "main") {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(containerManager.statsStore)
                .environmentObject(serviceManager)
                .environmentObject(appNavigation)
                .environmentObject(releaseChecker)
                .environmentObject(appReleaseChecker)
                .preferredColorScheme(themeColorScheme)
                .onAppear {
                    appQuitDelegate.serviceManager = serviceManager
                    if autoStartContainerSystem, !serviceManager.isServiceRunning {
                        Task { await serviceManager.startService() }
                    }
                }
        }
        .commands {
            appCommands
        }

        // Custom Settings window. SwiftUI's `Settings { ... }` scene
        // causes a publish-during-view-update loop on macOS 26 (spinner
        // + 100% CPU), so we use a regular `Window` instead and surface
        // it through a `CommandGroup(replacing: .appSettings)` so Cmd+,
        // and the app menu item still work. The main window applies the
        // in-app theme preference, but this Settings window intentionally
        // stays on the system appearance: on macOS 26, live-changing a
        // custom Window's preferred color scheme from the picker inside that
        // same window can blank its content until AppKit forces a redraw.
        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(SettingsManager.shared)
        }
        .defaultPosition(.center)

        // `isInserted:` with a get-only binding (set is a no-op) lets
        // us honor the user's preference *live* via `@AppStorage`
        // without giving macOS 26 a writable binding to feed back into
        // — that loop is what made the app spin at 100% CPU before.
        MenuBarExtra(isInserted: menuBarIconBinding) {
            MenuBarContainersView()
                .environmentObject(containerManager)
                .environmentObject(serviceManager)
                .environmentObject(appNavigation)
        } label: {
            Image(menuBarIconName)
                .renderingMode(.template)
                .id(serviceManager.isServiceRunning)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarIconName: String {
        serviceManager.isServiceRunning ? "MenuBarIcon" : "MenuBarIconInactive"
    }

    /// Container currently selected in the sidebar, resolved against the
    /// live container list so menu items can read its status (running /
    /// stopped) for enable/disable logic.
    private var selectedContainer: Container? {
        guard let id = appNavigation.selectedContainerID else { return nil }
        return containerManager.containers.first(where: { $0.id == id })
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        // App ▸ Settings… — replaces the default disabled item with one
        // that opens our custom Settings window via AppNavigation, which
        // ContentView translates into an `openWindow` call.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                appNavigation.requestSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        // App ▸ Check for Updates… — sits in the standard "appInfo" group
        // so it shows up right under the "About iContainer" item, matching
        // the placement users expect from native macOS apps.
        CommandGroup(after: .appInfo) {
            Button {
                Task {
                    await appReleaseChecker.checkForUpdateIfNeeded(force: true)
                    if appReleaseChecker.isUpdateAvailable {
                        appReleaseChecker.presentUpdateAlertIfAvailable()
                    } else {
                        let alert = NSAlert()
                        alert.messageText = "You're up to date"
                        alert.informativeText = "iContainer v\(appReleaseChecker.installedVersion) is the latest version."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                }
            } label: {
                Label("Check for Updates…", systemImage: "arrow.down.circle")
            }
        }

        // File ▸ New / Pull — replaces the default "New Item" group.
        CommandGroup(replacing: .newItem) {
            Button("New Container…") {
                appNavigation.requestNewContainer()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(!serviceManager.isServiceRunning)

            Button("Pull Image…") {
                appNavigation.requestPullImage()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(!serviceManager.isServiceRunning)
        }

        // View ▸ Overview / Service / Refresh — appended after the standard
        // sidebar toggle so it sits naturally inside the View menu.
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Show Overview") {
                appNavigation.requestOverview()
            }
            .keyboardShortcut("0", modifiers: .command)

            Button("Show Container Service") {
                appNavigation.showService()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])

            Divider()

            Button("Refresh") {
                appNavigation.requestRefresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!serviceManager.isServiceRunning)
        }

        // Container menu — actions for the container selected in the
        // sidebar. The whole menu's items are disabled when nothing is
        // selected; start/stop/restart also react to the current status.
        CommandMenu("Container") {
            let selected = selectedContainer
            let hasSelection = selected != nil
            let isRunning = selected?.status == .running
            let isStopped = selected?.status == .stopped

            Button("Start") {
                appNavigation.requestContainerCommand(.start)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!isStopped)

            Button("Stop") {
                appNavigation.requestContainerCommand(.stop)
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .disabled(!isRunning)

            Button("Restart") {
                appNavigation.requestContainerCommand(.restart)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!isRunning)

            Divider()

            Button("Show Info") {
                appNavigation.requestContainerCommand(.showTab(0))
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(!hasSelection)

            Button("Show Stats") {
                appNavigation.requestContainerCommand(.showTab(1))
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(!hasSelection)

            Button("Show Shell") {
                appNavigation.requestContainerCommand(.showTab(2))
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(!hasSelection)

            Button("Show Logs") {
                appNavigation.requestContainerCommand(.showTab(3))
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(!hasSelection)

            Divider()

            Button("Edit Settings…") {
                appNavigation.requestContainerCommand(.edit)
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!hasSelection)

            Button("Delete") {
                appNavigation.requestContainerCommand(.delete)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!hasSelection)
        }

        CommandMenu("Registry") {
            Button("Login…") {
                appNavigation.requestRegistryLogin()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
