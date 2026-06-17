# iContainer

<!-- The release badge is dynamic — shields.io reads it from the GitHub
     API and updates on each published release once the repo is public. -->
[![Latest release](https://img.shields.io/github/v/release/nico81/iContainer?sort=semver)](https://github.com/nico81/iContainer/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-lightgrey?logo=apple)
![Built with SwiftUI](https://img.shields.io/badge/SwiftUI-%E2%9C%93-orange?logo=swift&logoColor=white)
![Vibe-coded with Claude Code](https://img.shields.io/badge/vibe--coded%20with-Claude%20Code-8A2BE2)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-ffdd00?logo=buymeacoffee&logoColor=black)](https://www.buymeacoffee.com/nicoemanuelli)

A native macOS app to manage [Apple Container](https://github.com/apple/container) workloads — containers, images, logs, stats, and an interactive shell — built with SwiftUI on top of the official `container` CLI.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/home-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/images/home-light.png">
  <img alt="iContainer dashboard" src="docs/images/home-dark.png" width="900">
</picture>

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

## Roadmap

- 🚧 **Container machines** — support for the new container machines
  announced at WWDC 2026 is on the way.

(It's a hobby project, so "on the way" runs at hobby-project speed — but
it's coming. Ideas and PRs welcome.)

## Requirements

- macOS 26 or later (Apple silicon)
- [Apple Container CLI](https://github.com/apple/container/releases) installed

## Getting started

1. Install the Apple Container CLI: download the latest `.pkg` from the
   [releases page](https://github.com/apple/container/releases) and install it,
   confirming the recommended default kernel.
2. Download the latest iContainer build from
   [Releases](../../releases), or install via Homebrew (see below), or
   build from source (see below).
3. Start the container service from the app — everything else flows from there.

If the CLI is missing, the app shows a setup screen with a download link instead of the main UI.

The app checks GitHub for new iContainer releases on launch (cached for one
hour) and surfaces an in-app banner plus a one-shot popup whenever your
running version is older than the latest published tag. You can also trigger
a check on demand from the **iContainer ▸ Check for Updates…** menu item.

> **Note on the first launch** — release builds are currently not notarized
> (the project doesn't have a paid Apple Developer account yet). macOS will
> block the app the first time: right-click the app → **Open**, or allow it
> under **System Settings → Privacy & Security → Open Anyway**.
> Alternatively, clear the quarantine flag from the terminal:
>
> ```sh
> xattr -d com.apple.quarantine /Applications/iContainer.app
> ```

### Install via Homebrew

A dedicated Homebrew tap is the easiest way to keep iContainer up to date
without re-authorising the bundle on every release — Homebrew strips the
quarantine flag automatically, which sidesteps the Gatekeeper warning above.

```sh
brew tap nico81/icontainer
brew install --cask icontainer

# Later, to upgrade to the newest release:
brew upgrade --cask icontainer
```

> Recent Homebrew versions ask you to trust casks from third-party taps. If
> the install stops with *"Refusing to load cask … from untrusted tap"*, run
> `brew trust nico81/icontainer` (as the error suggests) and re-run the
> install.

The tap lives at
[nico81/homebrew-icontainer](https://github.com/nico81/homebrew-icontainer);
the canonical copy of the cask formula is vendored here as
[`Casks/icontainer.rb`](Casks/icontainer.rb) and mirrored to the tap on
each release.

## Building from source

```sh
git clone https://github.com/nico81/iContainer.git
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

## Built with vibes 🤖

Full disclosure: iContainer was **vibe-coded** — designed and written
hand-in-hand with [Claude Code](https://claude.com/claude-code). The ideas,
the direction, and every "no, not like that" are human; a lot of the typing
isn't. It ships with unit tests and gets manually run on each change, but
it's a hobby project built for fun on top of brand-new Apple tech — so read
the code, kick the tires, and don't run it anywhere you'd cry about. PRs and
issues very welcome.

If it saves you some clicks, you can
[buy me a coffee](https://www.buymeacoffee.com/nicoemanuelli) ☕ — entirely
optional, always appreciated.

## License

[MIT](LICENSE)
