# Recent Changes

## Purpose
Short, practical log of recent product/code decisions discussed in chat and implemented in code.

## Timeline (latest first)

### 2026-05-05
- Refined container create/edit consistency:
  - create and edit now share the same ports editor UI
  - configured ports are shown above the add-port form and made more prominent
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
