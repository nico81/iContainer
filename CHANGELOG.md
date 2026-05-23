# Changelog

All notable changes to iContainer will be documented in this file.

The format follows Keep a Changelog, and versions use semantic versioning:
`MAJOR.MINOR.PATCH`.

## [Unreleased]

## [1.3.0] - 2026-05-23

### Added
- Native macOS menu bar commands with keyboard shortcuts, exposed through
  a `.commands { … }` block on the main `Window` scene:
  - **App**: `Settings…` (⌘,) — opens the custom Settings window.
  - **File**: `New Container…` (⌘N), `Pull Image…` (⇧⌘P) — both disabled
    when the container service is stopped.
  - **View**: `Show Overview` (⌘0), `Show Container Service` (⇧⌘0),
    `Refresh` (⌘R, disabled when service stopped).
  - **Container**: `Start` (⌘↩), `Stop` (⇧⌘.), `Restart` (⇧⌘R), `Show
    Info/Stats/Shell/Logs` (⌘1–⌘4), `Edit Settings…` (⌘E), `Delete`
    (⌘⌫). Items react to the current sidebar selection and the
    container's running/stopped status.
  - **Registry**: `Login…` (⇧⌘L).
- `ContainerCommand` enum and `ContainerCommandRequest` token in
  `AppNavigation`, so menu items publish one-shot intents that
  `ContentView` resolves against the live selection. `AppNavigation`
  also mirrors the sidebar selection (`selectedContainerID`) so command
  items can be enabled/disabled correctly.
- Confirmation dialogs for menu-triggered `Stop` and `Delete` matching
  the inline sidebar row behaviour (same titles, copy, and destructive
  styling).
- Full Settings system (`Settings.swift`, `SettingsView.swift`) backed
  by `UserDefaults` and exposed through a dedicated `Window("Settings",
  id: "settings")` scene with a `NavigationSplitView` sidebar. Sections:
  - **General**: theme (System/Light/Dark), menu bar icon toggle,
    launch at login (via `SMAppService`), auto-start container service
    on app open, quit behavior (Ask / Always stop / Always leave
    running).
  - **Notifications**: master toggles for "Container stopped" and
    "Action failed" notifications.
  - **Behavior**: refresh interval (Manual / 2s / 5s / 10s),
    confirmation toggles for Stop, Delete, and Prune.
  - **Terminal**: default in-container shell (`sh` / `bash` / `zsh`),
    monospaced font name and size, force-black terminal background.
  - **Advanced**: custom `container` CLI path (with executable check)
    and default registry host. Includes a "Reset all settings"
    confirmation dialog.
- `NotificationService` wrapping `UNUserNotificationCenter` with lazy
  permission request. Emits:
  - **Container stopped** — triggered when a container that was
    previously seen running flips to stopped (covers both explicit user
    stops and crashes); driven by a `lastKnownStatuses` diff inside
    `ContainerizationWrapper.refreshContainers`.
  - **Action failed** — fired from Start/Stop/Delete failures with the
    underlying error message.
- "Container service on quit" preference is now honored by
  `AppQuitDelegate`, which skips the confirmation dialog when the user
  has chosen *Always stop* or *Always leave running*.
- Configurable polling cadence: `ContainerizationWrapper` and
  `ServiceManager` now read `settings.refreshIntervalSeconds` at
  `startPolling` time and disable the timer entirely when the user
  picks **Manual**.
- Terminal customization (`ContainerLogsView`, `ContainerShellView`)
  honors the user's monospaced font, font size, and an optional
  high-contrast black background.
- Persistent `ContainerShellSession` now prefers the user's default
  shell (`/bin/bash` / `/bin/zsh` / `/bin/sh`) and falls back to
  `/bin/sh` if the preferred binary isn't available in the container.
- Custom CLI path: `ServiceManager`, `ContainerizationWrapper`, and
  `ContainerShellSession` check `settings.customCliPath` before the
  built-in `/usr/local/bin/container` and `/opt/homebrew/bin/container`
  candidates.
- Default registry host: the Registry Login sheet and the "Copy
  command" fallback both source the default host from
  `settings.defaultRegistry`.

### Changed
- Sidebar Stop and Delete buttons skip their confirmation dialog when
  the matching `confirmStop` / `confirmDelete` preference is off.
- `AppQuitDelegate` informative copy switched to English to match the
  rest of the UI.

### Fixed
- macOS 26 publish-during-view-update loop that caused a 100% CPU spin:
  - Settings is now a regular `Window` scene (not the SwiftUI
    `Settings` scene) accessed through a `CommandGroup(replacing:
    .appSettings)` so ⌘, and the App menu still work.
  - `MenuBarExtra(isInserted:)` is driven by a get-only `Binding`
    over `@AppStorage("settings.showMenuBarIcon")` so macOS can't
    feed the binding's value back into `UserDefaults`.
  - `SettingsManager.init` writes initial values via
    `_property = Published(initialValue:)` to skip `objectWillChange`
    publishes during scene installation.

## [1.2.0] - 2026-05-22

### Added
- `ContainerReleaseChecker`, a lightweight `ObservableObject` that polls
  `https://api.github.com/repos/apple/container/releases/latest` (cached
  for one hour) and compares the latest GitHub release tag against the
  container CLI version reported by `container system status`.
- Update-available banner in `WelcomeDashboardView`, shown beneath the
  header when the installed CLI is older than the latest published
  release. Surfaces installed/latest versions and a direct link to the
  release page.
- "Latest release" row in the Service detail Info tab plus an inline
  "Download" link that appears only when an update is available.
- Native alert (popup) presented at most once per detected version per
  app session, with **Download** (opens the release URL) and **Later**
  actions.

## [1.1.0] - 2026-05-22

### Added
- Sidebar search field that filters containers and images by name or
  image reference (case-insensitive). The field is hidden while the
  container service is stopped — both lists are empty then — and any
  leftover query is cleared on stop so the next session starts clean.
- `CLIParsers.swift`, a single namespace that centralises every pure
  parser used to read `container` CLI output (image list, registry hosts,
  inspect → editable settings, system status, log truncation, error
  classifiers).
- `iContainerTests/` folder with about 45 XCTest cases that cover the new
  parser layer end-to-end. The test bundle itself is not yet wired into
  the Xcode project — see `iContainerTests/README.md` for the one-time
  UI step to add it.
- `View.applyIf` extension for conditional modifier chains, used to drive
  the sidebar searchable visibility.
- Visible app version/build information in the app UI (from the previous
  Unreleased section).

### Changed
- Split `ContentView.swift` (1752 → 1117 lines) into dedicated files:
  `WelcomeDashboardView.swift`, `SheetEditors.swift`,
  `SidebarComponents.swift`, `WindowResizeConfigurator.swift`.
- Split `ContainerDetailView.swift` (1660 → 141 lines, now a thin
  TabView host) into one file per tab plus shared chrome:
  `ContainerInfoView.swift`, `ContainerStatsView.swift`,
  `ContainerShellView.swift`, `ContainerLogsView.swift`,
  `ContainerInspectFallback.swift`, `DetailRowComponents.swift`.
- `ContainerizationWrapper` and `ServiceManager` are now thin proxies
  over `CLIParsers`; behaviour is identical but the parsing surface is
  finally unit-testable.
- Started app versioning and changelog tracking in earnest (moved from
  the previous Unreleased section).

### Fixed
- `splitReference` no longer mistakes the port of a registry reference
  like `localhost:5000/myapp` for a tag. Fully qualified references and
  references with an explicit tag continue to work.

## [1.0.0] - 2026-05-19

### Added
- Initial versioning baseline for the current app state.

