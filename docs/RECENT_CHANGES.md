# Recent Changes

## Purpose
Short, practical log of recent product/code decisions discussed in chat and implemented in code.

## Timeline (latest first)

### 2026-05-23 — Release 1.3.3
- Added a status filter to the sidebar "Containers" group. A funnel
  icon next to the section label opens a small popover with
  `All` / `Running` / `Stopped`. The icon switches to its filled
  variant when a non-`All` filter is active.
- The filter is `AND`ed with the existing search query; the
  "No matching containers" empty-state caption now fires whenever
  either input zeroes the list out.

### 2026-05-23 — Release 1.3.2
- Fixed: deleting the currently-selected container left the detail pane
  showing a "cannot load" error for the now-missing id. `ContentView`
  watches `containerManager.containers` via `onChange` and snaps the
  selection back to the overview when the selected id disappears.
- Removed the `AppVersion.displayString` row from the menu bar extra:
  it duplicated the version already visible in the welcome header and
  added clutter above the action buttons.

### 2026-05-23 — Release 1.3.1
- Added a `Settings…` item to the menu bar extra
  (`MenuBarContainersView`), placed above `Quit`. Routes through
  `@Environment(\.openWindow)` and `AppNavigation.activateApp()` to
  open the same `Window(id: "settings")` scene used by ⌘, and the App
  menu, so all three entry points stay in sync.

### 2026-05-23 — Release 1.3.0 (Settings, notifications, polish)
- New Settings system (`Settings.swift`, `SettingsView.swift`):
  - dedicated `Window("Settings", id: "settings")` scene (workaround
    for a macOS 26 publish-during-view-update loop on the SwiftUI
    `Settings { ... }` scene)
  - `NavigationSplitView` sidebar with five sections: General,
    Notifications, Behavior, Terminal, Advanced
  - preferences cover theme, menu bar icon visibility, launch at login
    (`SMAppService`), auto-start container service on app open, quit
    behavior, notification toggles, refresh cadence, confirmation
    toggles (Stop/Delete/Prune), default in-container shell, terminal
    font + size, force-black terminal, custom CLI path, default
    registry host, and a "Reset all settings" action
  - opened via App ▸ `Settings…` (⌘,), routed through
    `AppNavigation.requestSettings` and
    `@Environment(\.openWindow)` in `ContentView`
- `NotificationService` wraps `UNUserNotificationCenter` with lazy
  permission. Two notifications today:
  - container stopped — diff-driven inside
    `ContainerizationWrapper.notifyStatusTransitions` so we don't fire
    on the initial poll
  - action failed — emitted from Start/Stop/Delete `catch` blocks
- `AppQuitDelegate` now honors the user's quit-behavior preference and
  only prompts when set to *Ask*; informative copy switched to English.
- `ContainerizationWrapper` and `ServiceManager` polling read
  `settings.refreshIntervalSeconds` at start time. **Manual** truly
  disables the timer.
- CLI path resolution in `ServiceManager`, `ContainerizationWrapper`,
  and `ContainerShellSession` checks the custom path from Settings
  before the built-in candidates.
- Default registry no longer hard-coded in the Login sheet or the
  "Copy command" fallback — both source `settings.defaultRegistry`.
- `ContainerShellSession` picks the user's preferred shell first and
  falls back to `/bin/sh`.
- `ContainerLogsView` and `ContainerShellView` honor the user's
  monospaced font/size and an optional high-contrast black background.
- Sidebar Stop/Delete buttons skip their dialog when the matching
  confirmation toggle is off.
- macOS 26 publish-loop guardrails:
  - Settings is a regular `Window` scene, surfaced via
    `CommandGroup(replacing: .appSettings)` so ⌘, still works
  - `MenuBarExtra(isInserted:)` reads `@AppStorage` but discards
    binding writes (set is a no-op)
  - `SettingsManager.init` uses `_property = Published(initialValue:)`
    to skip `objectWillChange` during scene installation

### 2026-05-22 — Menu bar commands and keyboard shortcuts
- Added a native macOS menu bar + keyboard shortcut layer via
  `.commands { … }` on the main `Window` scene in `iContainerApp.swift`.
  Every shortcut has a visible menu equivalent (HIG-compliant and
  discoverable from the menu bar).
- New menus:
  - **File**: `New Container…` (⌘N), `Pull Image…` (⇧⌘P) — disabled
    when the container service is stopped.
  - **View** (after `.sidebar`): `Show Overview` (⌘0), `Show Container
    Service` (⇧⌘0), `Refresh` (⌘R, disabled with service stopped).
  - **Container**: `Start` (⌘↩), `Stop` (⇧⌘.), `Restart` (⇧⌘R),
    `Show Info/Stats/Shell/Logs` (⌘1–⌘4), `Edit Settings…` (⌘E),
    `Delete` (⌘⌫). Items track the sidebar selection and the
    container's running/stopped status.
  - **Registry**: `Login…` (⇧⌘L).
- `AppNavigation` gained one-shot intent counters
  (`newContainerRequestID`, `pullImageRequestID`, `registryLoginRequestID`,
  `refreshRequestID`, `overviewRequestID`) plus a `containerCommandRequest`
  (typed `ContainerCommand`) and a `selectedContainerID` mirror of the
  sidebar selection so the App-scope command menu can enable/disable
  items.
- `ContentView` observes those intents via `.onReceive` and dispatches
  them through a single `handleContainerCommand(_:)`. Menu-triggered
  `Stop` and `Delete` use new confirmation alerts that match the inline
  `ContainerRowView` dialogs exactly (same title, copy, and destructive
  styling).
- ⌘. (system Cancel) is intentionally avoided; Stop uses ⇧⌘. instead.

### 2026-05-22 — Release 1.1.0
- Added sidebar search/filter:
  - case-insensitive filter on container name, container image, and
    image reference
  - shown only when the container service is running; the query is
    cleared automatically when the service stops
  - empty-state "No matching …" caption inside each section when the
    filter zeroes it out
- Extracted CLI parsing into `CLIParsers.swift`:
  - new `nonisolated`, side-effect free namespace covering image list,
    registry hosts, inspect → editable settings, service status, log
    truncation, and error classifiers
  - `ContainerizationWrapper` and `ServiceManager` now forward to this
    namespace instead of owning parsing logic
  - fixed `splitReference` so `localhost:5000/myapp` is no longer
    parsed as `("localhost", "5000/myapp")`
- Added `iContainerTests/` with ~45 XCTest cases on the new parser layer.
  The test bundle still has to be wired into Xcode via the UI; see
  `iContainerTests/README.md`.
- Split `ContentView.swift` (1752 → 1117 lines) into:
  - `WelcomeDashboardView.swift`
  - `SheetEditors.swift`
  - `SidebarComponents.swift`
  - `WindowResizeConfigurator.swift`
- Split `ContainerDetailView.swift` (1660 → 141 lines, now a thin
  TabView host) into one file per tab plus shared chrome:
  - `ContainerInfoView.swift`
  - `ContainerStatsView.swift`
  - `ContainerShellView.swift`
  - `ContainerLogsView.swift`
  - `ContainerInspectFallback.swift`
  - `DetailRowComponents.swift`
- Added `View.applyIf` extension (`ViewExtensions.swift`) for
  conditional modifier chains.

### 2026-05-16
- Added Apple Container System Service logs:
  - service detail page now has `Info` and `Logs` tabs
  - logs are loaded through the official `container system logs --last 15m` command
  - Logs tab includes manual refresh, clear, copy, and live follow actions
  - live follow uses `container system logs --last 15m -f` and stops the process when disabled

### 2026-05-06
- Improved Stats tab spacing:
  - resource summary box now has explicit vertical padding and top-leading content alignment
  - resource summary box no longer clips content when padding increases
- Added browser shortcuts for exposed ports:
  - container detail Network section now renders ports with browser links to `http://localhost:<hostPort>`
  - link extraction supports common inspect formats such as `8429:8429` and `0.0.0.0:8429->8429/tcp`
  - port rows now use body-sized monospaced text with extra spacing before the icon-only browser button
- Improved container detail Mounts section:
  - host and container paths now render vertically with a divider for better long-path readability
  - host paths include a compact Finder button with file/folder-specific icon
- Normalized Info tab typography:
  - Basic Information, Network, Mounts, DNS, and Environment Variables now share consistent label/value sizing
  - technical values use the same compact monospaced style across cards
- Added Finder picker for volume host paths:
  - `Host Path` now has a browse button in create/edit volume forms
  - the picker supports both files and folders
- Improved create/edit container mapping layout:
  - removed the redundant raw mapping text field from ports and volumes
  - configured mappings now render as two 50/50 columns (`host` side and `container` side)
  - long paths wrap inside their own column instead of truncating the full mapping
  - create/edit sheets now have larger minimum sizing and are configured as resizable centered windows

### 2026-05-05
- Updated container create/edit volume UX:
  - volumes now use the same guided interaction as ports
  - configured volumes are shown prominently above the add-volume form
  - added `Host Path` and `Container Path` fields with automatic `host-path:container-path` composition
- Refined container create/edit consistency:
  - create and edit now share the same ports editor UI
  - configured ports are shown above the add-port form and made more prominent
  - port labels now use standard terms: `Host Port` and `Container Port`
  - container context menu action label shortened from `Edit Settings` to `Edit`
- Fixed edit name prefill from inspect hostnames:
  - fully qualified hostnames such as `name.test.` are normalized back to `name`
- Fixed container settings edit prefill:
  - edit sheet now uses robust raw inspect parsing instead of only minimal `Decodable` fields
  - name and image are prefilled immediately from the container list as fallback
  - ports, volumes, and env are loaded from inspect data before save is enabled
  - edit ports now show a visible mapping list with remove actions, matching create flow

### 2026-05-04
- Added container settings edit flow:
  - new `Edit Settings` action in container context menu
  - new edit sheet prefilled from container inspect data (image, name, ports, volumes, env)
  - save flow applies changes by recreate strategy (stop/delete/create and restart if previously running)
- Improved create-container ports UX:
  - added separate inputs for local host port and container port
  - added `Add` action to compose mapping automatically (`host:container`)
  - added visible mappings list under the input to confirm inserted ports
  - added remove action per mapping
  - clarified label/copy to distinguish local vs external/container side
- Added registry authentication UX improvements:
  - auth-aware error handling for pull/create failures (`Login now`, `Copy command`, `Cancel`)
  - in-app `Registry Login` sheet (host, username, password/token)
  - `Registry Login` voice in System Service context menu
  - registry auth status block added in Service Detail page
- Fixed registry status false-positive:
  - top-level CLI help output is no longer interpreted as authenticated login
  - Docker Hub login now tries host aliases (`registry-1.docker.io`, `docker.io`, `index.docker.io`)
- Reduced registry auth block flicker:
  - removed duplicate refresh in Service Detail view task
  - registry status refresh is now silent by default (no repeated loading-state blink)
- Registry status removed from left sidebar status row; kept only in service detail and moved as last section.
- Updated service detail title from `System Service` to `Apple Container System Service`.
- Sidebar behavior refined for service-off state:
  - `Images` section remains visible, but image rows are hidden.
  - Pull-image icon is hidden when service is not running.
  - Add-container (`+`) icon is hidden when service is not running.
- Container ordering updated in `ContainerizationWrapper.refreshContainers()`:
  - running first
  - stopped second
  - alphabetical by name within each group.

### 2026-03-17 / previous session history
- Introduced persistent shell tab in container detail:
  - dedicated `Shell` tab
  - session reused per container.
- Removed obsolete `Exec` UI flow:
  - removed exec sheet
  - removed exec context-menu actions.
- Fixed context-menu tab mapping:
  - added explicit `Shell` entry
  - corrected `Logs` to open logs tab.
- Shell startup warning cleanup:
  - removed interactive `-i` invocation pattern that caused job-control warnings without TTY.

## Known Non-Blocking Notes
- Build logs may include AppIntents metadata warning:
  - `Metadata extraction skipped. No AppIntents.framework dependency found.`
  - currently treated as non-blocking.
- LaunchServices occasionally returns transient `open` errors (`-609` / `-600`) immediately after process kill; retrying open usually succeeds.
