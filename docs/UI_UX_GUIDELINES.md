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

## Create Container Form
- Ports input must clearly distinguish:
  - local host port
  - container/exposed port
- Prefer guided composition (`host:container`) over ambiguous free-text-only entry.
- Existing/configured ports must be visually emphasized above the add-port controls.

## Shell Experience
- Shell output area should support selection/copy.
- Auto-scroll should be user-controllable.
- Startup must avoid noisy pseudo-TTY warnings.
- Session should persist while navigating tabs within the same container detail flow.

## Logs Experience
- Keep quick controls visible: filter, refresh, clear, copy.
- Auto-refresh and auto-scroll toggles should be explicit and independent.
- Empty state should be informative, not alarming.

## Labels and Copy
- Prefer explicit names over short generic labels.
- Service detail header text standard:
  - `Apple Container System Service`
- Avoid mixing synonyms for the same concept across views.
- For registry auth failures, prefer explicit guidance with action choices:
  - `Login now`
  - `Copy command`
  - `Cancel`

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
