# iContainer - Project Context

## Scope
iContainer is a macOS SwiftUI app that manages Apple Container workloads through the `container` CLI.

## Main Components

### Entry point and shell
- `iContainer/iContainerApp.swift`: app entry point, injects shared
  managers. Also owns the `.commands { … }` block that defines the
  File/View/Container/Registry menus and their keyboard shortcuts, the
  custom `Window("Settings", id: "settings")` scene (used instead of
  the SwiftUI `Settings` scene because of a macOS 26 publish loop),
  and the theme (`preferredColorScheme`) + menu bar icon visibility
  bindings driven by `@AppStorage`.
- `iContainer/ContentView.swift`: sidebar + detail navigation host, owns
  the create/edit/registry-login sheet state. Observes the
  `AppNavigation` intents fired by menu commands and resolves
  `ContainerCommand`s against the live selection via
  `handleContainerCommand(_:)`; also owns confirmation alerts for
  menu-triggered Stop/Delete and opens the Settings window through
  `@Environment(\.openWindow)`.
- `iContainer/AppNavigation.swift`: navigation state shared across menu
  bar extras and main window. Hosts the `ContainerCommand` enum and
  `ContainerCommandRequest` token used by the App-scope command menu,
  plus the `selectedContainerID` mirror and `settingsRequestID` intent
  that let menu items enable/disable themselves and open the Settings
  window.
- `iContainer/AppQuitDelegate.swift`: honors the user's "Container
  service on quit" preference (`SettingsManager.storedQuitBehavior()`),
  skipping the confirmation prompt when set to *Always stop* or
  *Always leave running*.

### Sidebar and welcome screen
- `iContainer/SidebarComponents.swift`: `ServiceStatusView` and
  `ContainerRowView` rows used in the sidebar list.
- `iContainer/WelcomeDashboardView.swift`: home screen shown when nothing
  is selected (metrics + recent containers preview).
- `iContainer/SheetEditors.swift`: shared editors used by the create and
  edit sheets (`MappingPairsEditor`, `EnvironmentVariablesEditor`,
  `MappingRow`, `PathPickerRow`, etc).
- `iContainer/WindowResizeConfigurator.swift`: `NSViewRepresentable` that
  makes sheets resizable with a minimum size.
- `iContainer/ViewExtensions.swift`: `View.applyIf` for conditional
  modifier chains.

### Service layer
- `iContainer/ContainerizationWrapper.swift`: async wrapper around the
  `container` CLI (containers/images/logs/stats/exec/registry). Pure
  parsing is delegated to `CLIParsers`.
- `iContainer/ServiceManager.swift`: polls the container system service,
  tracks status and follows logs. Pure parsing is delegated to
  `CLIParsers`.
- `iContainer/CLIParsers.swift`: single namespace holding every pure
  parser used to read `container` CLI output. Side-effect free and
  exhaustively unit-tested.

### Per-container detail
- `iContainer/ContainerDetailView.swift`: thin TabView host for the
  Info / Stats / Shell / Logs tabs.
- `iContainer/ContainerInfoView.swift`: Info tab, including port links
  and mount links.
- `iContainer/ContainerStatsView.swift`: Stats tab, including chart
  panel and the stats parser.
- `iContainer/ContainerShellView.swift`: Shell tab plus the persistent
  `ContainerShellSession` per container.
- `iContainer/ContainerLogsView.swift`: Logs tab with delta polling.
- `iContainer/ContainerInspectFallback.swift`: untyped-dictionary inspect
  parser for fields that the typed `Decodable` does not cover.
- `iContainer/DetailRowComponents.swift`: `DetailSection`, `DetailRow`,
  `StatusBadge`, `InfoTextStyle`. Shared chrome across the four tabs.

### System service detail
- `iContainer/ServiceDetailView.swift`: system service detail page with
  Info and Logs tabs.

### Settings and notifications
- `iContainer/Settings.swift`: `SettingsManager` (`ObservableObject`
  singleton backed by `UserDefaults`), plus the `ThemePreference`,
  `QuitBehavior`, `ShellPreference`, and `RefreshIntervalOption`
  enums. Exposes `nonisolated static` helpers
  (`storedCustomCLIPath`, `storedShellContainerPath`,
  `storedRefreshIntervalSeconds`, `storedQuitBehavior`) so
  Process-spawning code paths can read prefs without touching the
  MainActor-isolated singleton. The init bypasses the `@Published`
  setter via `_property = Published(initialValue:)` to avoid a macOS
  26 publish-during-view-update loop.
- `iContainer/SettingsView.swift`: Settings UI hosted in the dedicated
  `Window("Settings", id: "settings")` scene. Uses a
  `NavigationSplitView` sidebar (TabView's tab bar doesn't render
  reliably inside a non-`Settings` window on macOS 26) with five
  sections: **General**, **Notifications**, **Behavior**, **Terminal**,
  **Advanced**. Includes a "Reset all settings" confirmation dialog.
- `iContainer/NotificationService.swift`: thin wrapper around
  `UNUserNotificationCenter`. Posts a notification when a container
  transitions from running to stopped or when a Start/Stop/Delete
  action fails. Permission is requested lazily on first post; both
  notification types have a master toggle in Settings.
- `iContainer/ContainerReleaseChecker.swift`: polls the
  `apple/container` GitHub releases API and exposes whether the
  installed CLI is older than the latest published release; surfaces
  a popup (one per detected version per session) and inline banners
  on the welcome dashboard and Service Info tab.

### Tests
- `iContainerTests/CLIParsers*Tests.swift`: ~45 XCTest cases that cover
  the parser surface end-to-end. The test target is declared in the
  pbxproj as a file-system synchronised group, so any new `*.swift`
  file in `iContainerTests/` is picked up automatically.

## Menu bar and keyboard shortcuts
- All keyboard shortcuts must have a visible menu equivalent (macOS HIG).
  They are declared in `iContainerApp.appCommands`, not scattered across
  views.
- Menus and shortcuts (current set):
  - **App**: `Settings…` ⌘, (replaces the default disabled item via
    `CommandGroup(replacing: .appSettings)` and opens the custom
    Settings window through `AppNavigation.requestSettings`).
  - **File**: `New Container…` ⌘N, `Pull Image…` ⇧⌘P. Both disabled with
    service stopped.
  - **View** (appended after `.sidebar`): `Show Overview` ⌘0, `Show
    Container Service` ⇧⌘0, `Refresh` ⌘R (disabled with service
    stopped).
  - **Container**: `Start` ⌘↩, `Stop` ⇧⌘., `Restart` ⇧⌘R, `Show
    Info/Stats/Shell/Logs` ⌘1–⌘4, `Edit Settings…` ⌘E, `Delete` ⌘⌫.
    Items react to the selected container's status; nothing is enabled
    when no container is selected.
  - **Registry**: `Login…` ⇧⌘L.
- `⌘.` is reserved by macOS for Cancel; Stop uses `⇧⌘.` instead.
- Menu items publish one-shot intents through `AppNavigation` (counters
  for the simple ones, `ContainerCommandRequest` for selection-bound
  actions); `ContentView` consumes them via `.onReceive` so the App
  scene never reaches into view-local state directly.
- Menu-triggered Stop/Delete must show a confirmation alert that
  matches the inline `ContainerRowView` dialog exactly (same title,
  copy, destructive styling).

## Settings and preferences
- All user-facing preferences live in `SettingsManager` (single
  singleton, MainActor-isolated, backed by `UserDefaults`) and are
  exposed through the Settings window. Code paths that can't reach the
  MainActor (Process spawning, `@AppStorage` in the App scene, the
  cached `ContainerShellSession`) must use the `nonisolated static`
  accessors on `SettingsManager` — never reach into the singleton from
  a non-MainActor context.
- Preference inventory (default in parentheses):
  - **General**: theme (System), menu bar icon (on), launch at login
    (off, via `SMAppService.mainApp`), auto-start container service on
    app open (off), quit behavior (Ask).
  - **Notifications**: container stopped (on), action failed (on).
  - **Behavior**: refresh interval seconds (5; allowed values are
    Manual / 2 / 5 / 10), confirm Stop (on), confirm Delete (on),
    confirm Prune (on).
  - **Terminal**: default in-container shell (`sh`), font name (Menlo),
    font size (12), force-black terminal (off).
  - **Advanced**: custom CLI path (empty), default registry
    (`registry-1.docker.io`).
- Side effects:
  - `launchAtLogin` registers/unregisters the main app via
    `SMAppService` inside `applyLaunchAtLogin`. Errors are swallowed —
    the OS prompt is the source of truth, and the toggle reverts on
    its own if the user denies.
  - Refresh interval is read at polling-start time; changing it takes
    effect the next time the timers are restarted.
  - Custom CLI path is consulted by every `Process` spawn helper
    (`ServiceManager.resolveCLIPath`,
    `ContainerizationWrapper.resolveCLIPath`,
    `ContainerShellSession.resolveContainerCLIPath`).
- macOS 26 publish-loop guardrails (do not regress):
  - Settings is a dedicated `Window("Settings", id: "settings")` scene,
    not the SwiftUI `Settings { ... }` scene.
  - The `MenuBarExtra(isInserted:)` binding's `set` is a no-op; reads
    come from `@AppStorage("settings.showMenuBarIcon")`.
  - `SettingsManager.init` assigns initial values via the underscore-
    prefixed storage form (`_property = Published(initialValue:)`).

## Notifications
- `NotificationService.shared` is the only entry point. It funnels
  every notification through `UNUserNotificationCenter`, requesting
  permission lazily the first time a notification is actually posted.
- Two notification types are emitted today, each gated by its master
  toggle in Settings:
  - **Container stopped** — fired by
    `ContainerizationWrapper.notifyStatusTransitions` whenever a
    container that was previously seen `.running` flips to `.stopped`.
    Initial poll seeds the `lastKnownStatuses` map without firing.
  - **Action failed** — posted from the `catch` blocks of
    `startContainer`, `stopContainer`, and `deleteContainer`.
- Notifications are deliberately diff-driven (not toast-driven on every
  user click) so the same UI action doesn't produce two visible
  artefacts (in-app alert + system banner).

## Current UX Rules (Important)
- The app shows a dependency error screen if CLI `container` is not available.
- Sidebar container list is sorted:
  - running containers first
  - stopped containers second
  - alphabetical order inside each status group
- `Images` section behavior:
  - section is always visible
  - image rows are shown only when service is running
  - pull-image icon is hidden when service is stopped
- add-container (`+`) toolbar icon is hidden when service is stopped
- Sidebar search field:
  - case-insensitive filter on container name + image reference and on
    image reference
  - shown only when the container service is running (otherwise both
    lists are empty and the field would dangle next to a blank sidebar)
  - the query is cleared automatically when the service stops, so the
    next session starts unfiltered
- Sidebar container status filter:
  - funnel icon next to the "Containers" group label opens a popover
    with `All` / `Running` / `Stopped`; defaults to `All`
  - icon switches to its filled variant when a non-`All` filter is
    active so the user can see the state at a glance
  - the filter is `AND`ed with the search query, and the
    "No matching containers" empty-state fires when either input
    zeroes the list
- `Exec` feature has been removed from UI (replaced by persistent shell workflow).
- Registry auth UX:
  - auth errors (`401`, `unauthorized`, missing credentials) are detected and shown with guided actions
  - `Operation Failed` can show `Login now`, `Copy command`, `Cancel` for registry auth failures
  - `Registry Login` is available from system service context menu
  - registry auth status is shown only in service detail page (not in left sidebar)
  - registry auth panel is rendered after all other service detail sections
- Container settings editing:
  - available from container context menu (`Edit`)
  - opens a guided edit sheet prefilled from inspect data
  - name and image use sidebar/list data as immediate fallback while inspect loads
  - fully qualified inspect hostnames such as `name.test.` are normalized to `name`
  - ports and volumes use the same guided mapping editor pattern
  - mapping editors show configured values in two wrapping columns and do not show a redundant raw mapping field
  - exposed port browser links are shown in the container `Info` tab, not in create/edit forms
  - volume `Host Path` fields include a Finder picker for files or folders
  - create/edit sheets are resizable with a larger centered minimum window
  - save is disabled while edit settings are loading to avoid accidental loss of existing values
  - applying changes recreates the container with updated settings

## Shell Model
- Container shell is persistent per container (session cache by `containerId`).
- Shell starts automatically when opening the Shell tab.
- Commands are sent through a long-lived `container exec ... /bin/sh` process.

## Service Detail Naming
- Service detail header title is:
  - `Apple Container System Service`

## Service Logs
- Apple Container System Service detail uses tabs: `Info` and `Logs`.
- Service logs come from the official `container system logs --last 15m` command and are capped before display.
- Service logs can be followed live with `container system logs --last 15m -f`; disabling follow terminates the child process.
- The Logs tab supports refresh, follow, clear, and copy actions.
- Service logs are global service/runtime diagnostics and are separate from per-container stdout/stderr logs.

## Build/Run Workflow
- Standard build command:
  - `xcodebuild -project iContainer.xcodeproj -scheme iContainer -configuration Debug build`
- During manual relaunch, this sequence is reliable:
  - `pkill -x iContainer || true`
  - `open /Users/nico/Library/Developer/Xcode/DerivedData/iContainer-fpbjeiozuugbpjglzrjgziqvmlne/Build/Products/Debug/iContainer.app`

## Parsing Layer
- All parsing of `container` CLI output lives in `CLIParsers.swift` and
  is `nonisolated`, side-effect free, and unit-testable.
- `ContainerizationWrapper` and `ServiceManager` keep their old static
  parser entry points as thin forwarders to `CLIParsers` so the rest of
  the codebase is unchanged.
- Registry references with a port (e.g. `localhost:5000/myapp`) are
  parsed correctly: the colon in the port is preserved instead of being
  treated as a tag separator.

## Tests
- Unit tests live in `iContainerTests/` and only cover pure types
  (mostly `CLIParsers`). Anything that touches `Process`, `Pipe`, the
  filesystem, or `MainActor`-isolated state belongs in the app target,
  not in tests.
- The test target is already wired in `iContainer.xcodeproj` as a
  file-system synchronised group; new test files in `iContainerTests/`
  are picked up automatically. See `iContainerTests/README.md`.

## Registry Auth Notes
- Current login flow tries Docker Hub aliases:
  - `registry-1.docker.io`
  - `docker.io`
  - `index.docker.io`
- Status parsing guards against false positives:
  - top-level CLI help output must never be treated as authenticated state
