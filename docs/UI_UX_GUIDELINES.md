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
- When container system service is **stopped**:
  - keep `Images` section visible
  - hide image rows
  - hide pull-image icon
  - hide add-container (`+`) icon

## Containers List Behavior
- Sort order must remain:
  1. running containers
  2. stopped containers
  3. alphabetical by name within each status group
- Status should be immediately recognizable (green/red indicator pattern is acceptable).

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

## Visual Consistency
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
