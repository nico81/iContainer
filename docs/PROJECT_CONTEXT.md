# iContainer - Project Context

## Scope
iContainer is a macOS SwiftUI app that manages Apple Container workloads through the `container` CLI.

## Main Components
- `iContainer/iContainerApp.swift`: app entry point, injects shared managers.
- `iContainer/ContentView.swift`: main sidebar + detail navigation.
- `iContainer/ContainerizationWrapper.swift`: async wrapper around `container` commands (containers/images/logs/stats/exec support).
- `iContainer/ServiceManager.swift`: polling and parsing of container system service status/details.
- `iContainer/ContainerDetailView.swift`: per-container detail tabs (`Info`, `Stats`, `Shell`, `Logs`).
- `iContainer/ServiceDetailView.swift`: system service detail page.

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
- `Exec` feature has been removed from UI (replaced by persistent shell workflow).
- Registry auth UX:
  - auth errors (`401`, `unauthorized`, missing credentials) are detected and shown with guided actions
  - `Operation Failed` can show `Login now`, `Copy command`, `Cancel` for registry auth failures
  - `Registry Login` is available from system service context menu
  - registry auth status is shown only in service detail page (not in left sidebar)
  - registry auth panel is rendered after all other service detail sections

## Shell Model
- Container shell is persistent per container (session cache by `containerId`).
- Shell starts automatically when opening the Shell tab.
- Commands are sent through a long-lived `container exec ... /bin/sh` process.

## Service Detail Naming
- Service detail header title is:
  - `Apple Container System Service`

## Build/Run Workflow
- Standard build command:
  - `xcodebuild -project iContainer.xcodeproj -scheme iContainer -configuration Debug build`
- During manual relaunch, this sequence is reliable:
  - `pkill -x iContainer || true`
  - `open /Users/nico/Library/Developer/Xcode/DerivedData/iContainer-fpbjeiozuugbpjglzrjgziqvmlne/Build/Products/Debug/iContainer.app`

## Registry Auth Notes
- Current login flow tries Docker Hub aliases:
  - `registry-1.docker.io`
  - `docker.io`
  - `index.docker.io`
- Status parsing guards against false positives:
  - top-level CLI help output must never be treated as authenticated state
