# iContainer

A native macOS app to manage [Apple Container](https://github.com/apple/container) workloads — containers, images, logs, stats, and an interactive shell — built with SwiftUI on top of the official `container` CLI.

<!-- screenshot -->

## Features

- **Dashboard** — container/image counts at a glance, quick actions, recent containers.
- **Container lifecycle** — create (from an image or a Dockerfile build), start, stop, restart, edit settings (ports, volumes, environment), delete. Editing recreates the container with the new configuration.
- **Sidebar** — running/stopped sorting, search, and a status filter; live status indicators.
- **Per-container detail tabs** — Info (network, mounts, DNS, env, exposed-port browser links), Stats with charts, persistent Shell session, Logs with follow mode.
- **Images** — list, pull, inspect, delete; registry login with guided error handling for auth failures.
- **Apple container service** — start/stop the system service, view its status, version, and live system logs.
- **Update check** — notifies you when a newer release of the `container` CLI is available on GitHub.
- **Notifications** — optional system notifications when a container stops or an action fails.
- **Settings** — theme, launch at login, auto-start service, quit behavior, polling cadence, confirmation dialogs, default shell, terminal font, custom CLI path, default registry.
- **Menu bar extra** — control containers and the service without opening the main window.
- **Keyboard shortcuts** — full menu bar command set (⌘N new container, ⇧⌘P pull image, ⌘1–⌘4 detail tabs, and more).

## Requirements

- macOS 26 or later (Apple silicon)
- [Apple Container CLI](https://github.com/apple/container/releases) installed

## Getting started

1. Install the Apple Container CLI: download the latest `.pkg` from the
   [releases page](https://github.com/apple/container/releases) and install it,
   confirming the recommended default kernel.
2. Download the latest iContainer build from
   [Releases](../../releases), or build from source (see below).
3. Start the container service from the app — everything else flows from there.

If the CLI is missing, the app shows a setup screen with a download link instead of the main UI.

> **Note on the first launch** — release builds are currently not notarized.
> macOS will block the app the first time: right-click the app → **Open**, or
> allow it under **System Settings → Privacy & Security → Open Anyway**.
> Alternatively, clear the quarantine flag from the terminal:
>
> ```sh
> xattr -d com.apple.quarantine /Applications/iContainer.app
> ```

## Building from source

```sh
git clone https://github.com/<you>/iContainer.git
cd iContainer
open iContainer.xcodeproj
```

Then build and run the `iContainer` scheme in Xcode. You will need to set your own development team in Signing & Capabilities. From the command line:

```sh
xcodebuild -project iContainer.xcodeproj -scheme iContainer -configuration Debug build
```

Unit tests cover the CLI-output parsing layer:

```sh
xcodebuild -project iContainer.xcodeproj -scheme iContainer -testPlan iContainer test
```

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — release history
- [docs/PROJECT_CONTEXT.md](docs/PROJECT_CONTEXT.md) — architecture and component map
- [docs/UI_UX_GUIDELINES.md](docs/UI_UX_GUIDELINES.md) — UI/UX conventions
- [docs/VERSIONING.md](docs/VERSIONING.md) — release workflow

## License

[MIT](LICENSE)
