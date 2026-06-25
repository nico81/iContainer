# Changelog

All notable changes to iContainer will be documented in this file.

The format follows Keep a Changelog, and versions use semantic versioning:
`MAJOR.MINOR.PATCH`.

## [Unreleased]

### Fixed
- Container Logs now show the initial log snapshot immediately and always
  clear the loading spinner after refresh, instead of treating the first
  response only as a hidden delta baseline.

## [2.0.0] - 2026-06-23

### Added
- **Container machines** — full management of Apple's container machines
  (the Linux VMs that host containers), introduced at WWDC 2026:
  - A dedicated **Machines** sidebar section (between Containers and
    Images) listing machines with status, an inline start/stop button,
    and a subtitle showing `CPU · RAM · IP` (IP shown when running).
  - Per-machine detail with **Info / Shell / Logs** tabs:
    - **Info**: status, configuration (CPUs, memory, disk, home mount),
      network (IP with a copy button, when running), image reference and
      platform, created date, and user (with uid/gid).
    - **Shell**: a persistent interactive session
      (`container machine run -n <id> -i`), mirroring the container Shell
      tab; it boots the machine if stopped.
    - **Logs**: `container machine logs` with the same layout as the
      container Logs tab (filter, Follow, refresh/clear/copy, terminal
      font/contrast).
  - **Create** machines (image, name with live validation, cpus, memory,
    home-mount, boot toggle), **edit configuration** (cpus/memory/
    home-mount, with a "restart to apply" prompt), start, stop, and
    delete — from the sidebar, the detail view, the menu bar, and the
    dashboard.
  - Status filter (All / Running / Stopped) on the Machines section,
    matching Containers.
  - `Machine` / `MachineDetails` models and
    `CLIParsers.parseMachineList` / `parseMachineDetails`, unit-tested.
- Unified creation: the toolbar **+** is now a menu offering *New
  Container…* and *New Machine…*; the dashboard has both a Create
  Container and a Create Machine action.
- Dashboard "Available" area split into two columns — containers on the
  left, machines on the right — plus a Machines metric tile, with
  Running/Stopped counts now spanning containers and machines.
- Menu bar extra lists machines in their own labelled section alongside
  containers, with the same homogeneous action menu
  (`MachineActionsMenuItems`).
- Reorderable sidebar sections (Containers / Machines / Images) via a
  header context menu, with the order persisted; the section
  expand/collapse state and the status filters are persisted too.

### Changed
- Container sidebar rows keep the box icon in the subtitle even when
  showing the IP, so they still read as "containers" at a glance.

### Fixed
- Logs tabs (container and machine): the reload spinner now occupies a
  fixed-size slot, so it no longer resizes the toolbar row or nudges the
  terminal output while following.

## [1.6.0] - 2026-06-16

### Added
- `AppReleaseChecker`, a sibling of `ContainerReleaseChecker` that polls
  `https://api.github.com/repos/nico81/iContainer/releases/latest` (cached
  for one hour) and compares the running bundle's
  `CFBundleShortVersionString` against the latest published GitHub tag.
- In-app update notice for iContainer itself: a banner in
  `WelcomeDashboardView` and a one-shot per-version alert in `ContentView`,
  mirroring the existing CLI update flow. **iContainer ▸ Check for
  Updates…** menu item triggers an on-demand check and shows an
  "up to date" confirmation when no newer release is found.
- `ReleaseNotesSheet`, a modal sheet that renders the GitHub release
  `body` as markdown. Reachable from a "What's new" link in the update
  banner and a "Release Notes" button added to the iContainer update
  alert; the sheet exposes the same Download action.
- `Casks/icontainer.rb` Homebrew Cask formula plus the
  [`nico81/homebrew-icontainer`](https://github.com/nico81/homebrew-icontainer)
  tap, documented in the README. Homebrew strips the quarantine flag
  automatically, which works around the Gatekeeper warning the
  ad-hoc-signed bundle would otherwise trigger on first launch.

## [1.5.4] - 2026-06-15

### Added
- `AccentTabPicker`, a custom accent-tinted segmented control used for
  the detail toolbars (per-container Info/Stats/Shell/Logs and service
  Info/Stats/Logs). The native segmented picker can't be tinted — SwiftUI
  ignores `.tint` on `.segmented`, and `NSSegmentedControl`'s selection
  color is overridden by Liquid Glass — so the selected segment is drawn
  as an accent-filled pill inside the toolbar's own capsule.
- `circular` option on `actionButtonStyle(...)` for icon-only action
  buttons (start/stop, delete, service controls), rendering them as round
  buttons.

### Removed
- The "Use Liquid Glass buttons" preference (added in 1.5.3) and its
  `settings.glassButtons` key. Action buttons now consistently use the
  standard bordered style; the glass toggle didn't earn its keep before
  the public release.

## [1.5.3] - 2026-06-14

### Added
- "Use Liquid Glass buttons" appearance preference (General ▸
  Appearance, default on). Action buttons use the Liquid Glass button
  style via a new `actionButtonStyle(prominent:glass:)` modifier; turning
  it off falls back to the standard bordered/`borderedProminent` style
  for higher contrast. Backed by `settings.glassButtons`, read by each
  view through `@AppStorage`.

### Changed
- The sidebar accent wash now respects the system **Reduce Transparency**
  accessibility setting: when that is on, the tint is dropped (it's brand
  decoration on the Liquid Glass layer, exactly what the setting strips).

### Documentation
- Documented the Stats chart conventions (shared `StatTimelineChart`,
  fixed time window, gap splitting, single-sample point, accent fill,
  cleared-on-stop history) in `docs/UI_UX_GUIDELINES.md`.

## [1.5.2] - 2026-06-13

### Changed
- Extracted a small design-system module (`DesignSystem.swift`) as the
  single source of truth for visual tokens that were previously
  duplicated with slight inconsistencies across views:
  - `AppRadius` (`card` = 12, `small` = 8) corner radii.
  - `Color.hairline` and a `cardOutline(_:)` view modifier replacing the
    repeated `.overlay(RoundedRectangle(...).stroke(...))`.
  - `StatusDot`, one definition of the running/stopped indicator dot
    (sidebar service row, container rows, welcome dashboard), with a
    configurable `size`.
  No behavior change — purely visual consistency and de-duplication.

## [1.5.1] - 2026-06-13

### Added
- "Tint the sidebar with the accent color" appearance preference
  (General ▸ Appearance, default on). A flat accent wash is laid over
  the whole sidebar — search field included — via a non-hit-testing
  overlay applied after `.searchable`; turning it off restores the plain
  system sidebar material. Backed by the `settings.sidebarTinted`
  preference, mirrored into `ContentView` through `@AppStorage` so the
  toggle updates the sidebar live.

## [1.5.0] - 2026-06-13

### Added
- Service-wide Stats tab in the Apple container service detail view.
  Shows aggregate CPU / memory / network across every running container
  (build workers included), with CPU normalized against the host core
  count (Activity-Monitor style). Sampled in the background via
  `container stats --no-stream` and stored in `ContainerStatsStore`'s
  `ServiceHistory`, so the chart is already populated on open.
- "Build Infrastructure" section in the Service detail view that surfaces
  the infrastructure containers Apple's CLI manages itself (currently the
  BuildKit shim). These are filtered out of the sidebar into a separate
  `systemContainers` list so they don't mix with the user's containers.
- Live build output: `container build` now streams progress
  (`--progress plain`) line-by-line into a scrollable, auto-scrolling
  panel in the create sheet instead of freezing until completion. Backed
  by a new `runCommandStreaming` helper.
- "Start after creation" checkbox in the create sheet. When enabled the
  new container is started and selected automatically; `createContainer`
  now returns the created id so the app can navigate to it.
- "Hide noisy XPC connection errors" setting (Logs section, default on).
  Filters the repetitive `Connection invalid` lifecycle errors Apple's
  `container` daemons emit on every CLI disconnect from the service logs
  view. Display-only — the underlying system logs are untouched.

### Changed
- Logs tab consolidates the separate "Auto Refresh" and "Auto Scroll"
  toggles into a single "Follow" switch (they always moved together):
  following polls for new lines and pins the scroll to the latest entry;
  off means manual refresh and free scrolling.

## [1.4.0] - 2026-06-13

### Added
- Support for the Apple Container CLI 1.0.0 JSON formats (released
  alongside WWDC 2026), kept backward compatible with older CLIs:
  - `container list` now reads the nested `status` object
    (`{state, networks, startedDate}`) in addition to the legacy
    plain-string `status` and top-level `networks` array; IP addresses
    are read from `ipv4Address` (CIDR form, prefix stripped) or the
    legacy `address`.
  - `container inspect` parsing (typed model and untyped fallback)
    accepts the same nested `status` shape.
  - `container image list` reads the nested `configuration` object
    (`name`, `descriptor`, `creationDate`) in addition to the legacy
    top-level `reference`/`descriptor`.
- Background per-container stats history (`ContainerStatsStore`): the
  polling loop samples `container stats` for every running container, so
  the Stats tab chart is already populated when opened. History lives in
  a dedicated `ObservableObject` so frequent samples don't re-render the
  sidebar, list, or menu bar; it is pruned/cleared when a container
  stops or is removed.

### Fixed
- Pipe deadlock on large CLI output. `runCommandBlocking` (in both
  `ContainerizationWrapper` and `ServiceManager`) now drains the output
  pipe before `waitUntilExit()`. The CLI 1.0.0 image list (~140 KB)
  exceeded the 64 KB pipe buffer, so the child blocked on write while
  the app blocked on exit — the images list silently stayed empty.

### Changed
- Sidebar rows are less cluttered:
  - image rows show only the size under the name (the creation date was
    removed).
  - container rows show a single subtitle — the IP address when the
    container is running and has one, otherwise the image reference.

## [1.3.4] - 2026-06-12

### Added
- MIT `LICENSE` and a proper English `README.md` (features,
  requirements, getting started with a first-launch Gatekeeper note,
  build-from-source instructions, documentation links). The old
  Italian `readme.txt` is gone; its install notes moved into the
  README.
- `scripts/make-release.sh`: builds the Release configuration, ad-hoc
  signs the app, and packages `dist/iContainer-v<version>.zip` ready to
  attach to a GitHub release. `SIGN_IDENTITY` is overridable for a
  future Developer ID + notarization flow.

### Changed
- All remaining Italian user-facing strings, log messages, and code
  comments translated to English (CLI-not-found errors, registry login
  hints, required-field validation, `logger.error` calls).

### Removed
- Design sources (`Logo/`), `.DS_Store` files, `xcuserdata/`, the
  `container_data/web-test` Dockerfile, and `docs/RECENT_CHANGES.md`
  (kept as local working notes) are no longer tracked; `.gitignore`
  extended accordingly.

## [1.3.3] - 2026-05-23

### Added
- Container status filter in the sidebar. A funnel icon next to the
  "Containers" group title opens a small popover with `All`, `Running`,
  and `Stopped` options. The icon switches to its filled variant when
  any filter other than `All` is active, so the current state is
  visible at a glance. The status filter is `AND`ed with the existing
  search query, and the existing "No matching containers" caption now
  shows whenever either input narrows the list to zero.

## [1.3.2] - 2026-05-23

### Fixed
- Detail pane no longer shows a "cannot load" error for a container that
  was just deleted. `ContentView` now watches
  `containerManager.containers` and falls back to the overview when the
  currently-selected container id disappears from the list, covering
  deletes triggered from the sidebar row, the Container menu, or the
  menu bar extra.

### Removed
- Plain-text `AppVersion.displayString` row from the menu bar extra
  (`MenuBarContainersView`). The version is still visible in the
  welcome dashboard header, so the duplicate row was just noise.

## [1.3.1] - 2026-05-23

### Added
- "Settings…" entry in the menu bar extra (`MenuBarContainersView`),
  placed above the existing "Quit" item. Opens the same `Window(id:
  "settings")` scene as ⌘, and the App ▸ Settings… menu item, via
  `@Environment(\.openWindow)` and `AppNavigation.activateApp()`.

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

