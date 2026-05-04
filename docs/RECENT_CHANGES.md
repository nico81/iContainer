# Recent Changes

## Purpose
Short, practical log of recent product/code decisions discussed in chat and implemented in code.

## Timeline (latest first)

### 2026-05-04
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

