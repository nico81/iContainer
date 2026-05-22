# Changelog

All notable changes to iContainer will be documented in this file.

The format follows Keep a Changelog, and versions use semantic versioning:
`MAJOR.MINOR.PATCH`.

## [Unreleased]

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

