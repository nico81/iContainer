# UI/UX Guidelines

## Goal
Keep iContainer clear, predictable, and fast for container operations, with minimal ambiguity between service state and available actions.

## Core Principles
- Prioritize operational clarity over visual density.
- Never show actionable controls that are not currently meaningful.
- Keep labels explicit and stable across views.
- Minimize mode-switching friction (important for shell/log workflows).

## Information Architecture
- Sidebar primary areas:
  - `Container System Service`
  - `Containers`
  - `Images`
- Detail area is context-driven by selected sidebar item.
- Container detail tabs:
  - `Info`
  - `Stats`
  - `Shell`
  - `Logs`
- Registry auth visibility:
  - do not show registry auth state in left sidebar status row
  - show registry auth only in Service Detail page
  - place registry auth section after status/version/path/output sections (last block)

## Service State Rules
- When container system service is **running**:
  - show container list
  - show image rows
  - show pull-image icon
  - show add-container (`+`) icon
  - show sidebar search field
- When container system service is **stopped**:
  - keep `Images` section visible
  - hide image rows
  - hide pull-image icon
  - hide add-container (`+`) icon
  - hide the sidebar search field (both lists are empty in this state)
  - clear any leftover search query so a new session starts unfiltered

## Containers List Behavior
- Sort order must remain:
  1. running containers
  2. stopped containers
  3. alphabetical by name within each status group
- Status should be immediately recognizable (green/red indicator pattern is acceptable).
- When the sidebar search field is non-empty, both `Containers` and
  `Images` sections show only matches; an explicit "No matching …"
  caption is shown inside the section when the filter zeroes it out.
- Search is case-insensitive and matches on container name + image
  reference for containers, and on the full `name:tag` reference for
  images.
- A status filter is available next to the `Containers` group label
  (funnel icon → popover with `All` / `Running` / `Stopped`). The icon
  uses its filled variant when a non-`All` filter is active so the
  current state is visible at a glance. The status filter is `AND`ed
  with the search query; the "No matching containers" caption fires
  whenever either input zeroes the list.

## Container Actions
- `Exec` flow is deprecated in UI and must not be reintroduced casually.
- Preferred interaction path is `Shell` tab with persistent session behavior.
- Context menu entries must map 1:1 to real tab indexes (`Info`, `Stats`, `Shell`, `Logs`).
- Context menu should also expose `Edit` for container reconfiguration.
- Editing settings must clearly communicate that apply action recreates the container.
- Edit sheets must prefill existing values before allowing save, especially ports, volumes, env, image, and name.
- The container context menu label for reconfiguration is `Edit`.
- Create and edit forms must stay visually coherent and share the same ports interaction.
- Create/edit sheets should be resizable on macOS, with a useful minimum size and centered initial presentation.

## Create Container Form
- Ports input must clearly distinguish:
  - `Host Port`: port exposed on the Mac/host
  - `Container Port`: port the service listens on inside the container
- Prefer guided composition (`host:container`) over ambiguous free-text-only entry.
- Existing/configured ports must be visually emphasized above the add-port controls.
- Browser actions for exposed ports belong in the container `Info` tab, not in create/edit forms.
- Do not show a redundant raw mapping text field when the visual configured-list editor is available.
- Long configured mappings should wrap in two equal columns instead of truncating the full string.
- Volumes input must mirror the ports interaction:
  - `Host Path`: path on the Mac/host
  - `Container Path`: mount path inside the container
- Existing/configured volumes must be visually emphasized above the add-volume controls.
- `Host Path` should provide a Finder picker that supports both files and folders.

## Shell Experience
- Shell output area should support selection/copy.
- Auto-scroll should be user-controllable.
- Startup must avoid noisy pseudo-TTY warnings.
- Session should persist while navigating tabs within the same container detail flow.

## Logs Experience
- Keep quick controls visible: filter, refresh, clear, copy.
- Auto-refresh and auto-scroll toggles should be explicit and independent.
- Empty state should be informative, not alarming.
- Service logs belong in a dedicated `Logs` tab inside the Apple Container System Service detail page, separate from per-container logs.
- Service logs should provide refresh, follow, clear, and copy actions.
- Live service log follow should terminate its child process when disabled or when the app closes.

## Labels and Copy
- Prefer explicit names over short generic labels.
- Service detail header text standard:
  - `Apple Container System Service`
- Avoid mixing synonyms for the same concept across views.
- For registry auth failures, prefer explicit guidance with action choices:
  - `Login now`
  - `Copy command`
  - `Cancel`

## Container Info
- Info cards should use consistent text hierarchy across Basic Information, Network, Mounts, DNS, and Environment Variables.
- Technical values in Info cards should share the same compact monospaced style.
- Exposed ports should use the same technical-value style and an icon-only browser button with clear spacing.
- Mount rows should show `Host Path` above `Container Path` with a clear divider for long-path readability.
- Host mount paths should offer a compact Finder action with file/folder-specific icon.

## Menu Bar and Keyboard Shortcuts
- Every keyboard shortcut must have a visible menu equivalent in the
  macOS menu bar (HIG requirement; also keeps shortcuts discoverable).
- Shortcuts and their menu items are declared in one place
  (`iContainerApp.appCommands`), never scattered across views.
- Menu items must reflect availability:
  - service-dependent items (`New Container…`, `Pull Image…`,
    `Refresh`) are disabled when the container service is stopped.
  - container-scoped items (`Container` menu) require a container
    selection in the sidebar.
  - `Start` is enabled only when the selected container is stopped;
    `Stop` and `Restart` only when it is running.
- Reserved combos to avoid:
  - `⌘.` is macOS Cancel — never bind app actions to it. `Stop` uses
    `⇧⌘.` instead.
- Destructive shortcut actions (`Stop`, `Delete`) must show the same
  confirmation alert as their inline sidebar equivalents — never
  "fire and forget" destructive operations from the keyboard.
- Current shortcut surface (kept in sync with `PROJECT_CONTEXT.md`):
  - App: `Settings…` ⌘,
  - File: `New Container…` ⌘N · `Pull Image…` ⇧⌘P
  - View: `Show Overview` ⌘0 · `Show Container Service` ⇧⌘0 ·
    `Refresh` ⌘R
  - Container: `Start` ⌘↩ · `Stop` ⇧⌘. · `Restart` ⇧⌘R ·
    `Show Info/Stats/Shell/Logs` ⌘1–⌘4 · `Edit Settings…` ⌘E ·
    `Delete` ⌘⌫
  - Registry: `Login…` ⇧⌘L

## Settings and preferences
- Settings open in their own window (⌘, or App menu ▸ Settings…) and use
  a sidebar layout with five sections: General, Notifications, Behavior,
  Terminal, Advanced. Keep section copy short and use grouped panels
  with a one-line caption above each toggle group.
- Every preference must have a sensible default and a reversible UI
  control — destructive defaults (forcing notifications on, defaulting
  to "Always stop service on quit", etc.) are not allowed.
- Confirmation toggles (`Confirm Stop`, `Confirm Delete`, `Confirm
  Prune`) are user-controllable but default to **on**. Both sidebar
  buttons and menu commands must consult the matching toggle before
  showing the dialog.
- The default registry shown in Registry Login defaults to
  `settings.defaultRegistry`. Don't hard-code Docker Hub aliases in
  new code — read the preference.
- Refresh interval ranges from Manual (no timer) to 10 s. **Manual**
  must actually disable the timer — don't fall back to a hidden minimum
  cadence.
- Theme selection (System/Light/Dark) is applied via
  `preferredColorScheme` on both the main and Settings windows.

## Notifications
- Two notification types are exposed: container stopped and action
  failed. Each is gated by its own master toggle; never bypass the
  toggle.
- Notifications must not duplicate in-app feedback for the same user
  intent — they exist so the user can leave the app and still know
  when something happens. Status-change notifications are diff-driven
  (running → stopped) and avoid firing on the initial poll.
- Body copy stays short and concrete: container name in quotes, plain
  English, no shell traces.

## Service Stats and Build Infrastructure
- The Apple container service detail has its own Stats tab showing a
  service-wide aggregate (CPU/memory/network across all running
  containers). CPU is normalized against the host core count
  (Activity-Monitor style: 100% = host fully busy), and the chart is
  pre-populated from background sampling — never start from an empty
  chart when data is already available.
- Infrastructure containers the CLI manages itself (BuildKit shim) must
  not appear in the sidebar. Surface them only in the Service detail
  "Build Infrastructure" section, with a one-line explanation that they
  are managed automatically. This mirrors Docker Desktop / OrbStack.

## Container creation
- The create sheet offers a "Start after creation" checkbox (default
  on). On success, navigate to the newly created container.
- Build output must stream live into a scrollable, auto-scrolling panel
  — never freeze the sheet until the build finishes.

## Logs
- The per-container Logs tab uses a single "Follow" toggle (not separate
  Auto Refresh / Auto Scroll): following both polls for new lines and
  pins the scroll to the latest entry; off means manual refresh and free
  scrolling. Refresh is disabled while following.
- Cosmetic daemon noise (XPC `Connection invalid`) is hidden by default
  in the service logs view; the filter is display-only and user-toggleable
  in Settings → Terminal/Logs.

## Terminal customization
- The Shell and Logs panels honor the user's monospaced font, font
  size, and an optional high-contrast black background. New
  text-heavy panels that show CLI output should follow the same
  pattern (`SettingsManager.shared.terminalFontName`, `terminalFontSize`,
  `forceBlackTerminal`).

## Visual Consistency
- Reuse the shared visual tokens in `DesignSystem.swift`: `AppRadius`
  for corner radii, `cardOutline(_:)` for the hairline outline, and
  `StatusDot` for the running/stopped indicator. Don't hardcode radii,
  stroke overlays, or status circles in new views.
- Reuse existing component language (`DetailSection`, `DetailRow`, status badge style).
- Keep icon semantics consistent:
  - play/start = start
  - stop = stop
  - terminal = shell
  - plaintext doc = logs
- Avoid introducing decorative styles that reduce readability for operational data.

## Pre-Release UX Checklist
- Verify service ON/OFF state transitions update sidebar actions correctly.
- Verify context-menu tab targets open the expected tab.
- Verify shell still works after stopping/starting service.
- Verify hidden actions are truly hidden (not only disabled) where specified.
- Verify no stale copy remains for removed features (e.g., old Exec references).
