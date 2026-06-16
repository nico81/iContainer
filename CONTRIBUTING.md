# Contributing to iContainer

Thanks for taking a look! iContainer is a hobby project, but issues and
pull requests are genuinely welcome.

## Requirements

- macOS 26 or later (Apple silicon)
- Xcode (matching the macOS 26 SDK)
- The [Apple Container CLI](https://github.com/apple/container/releases)
  installed, for running the app against a real service

## Build and test

```sh
# Build
xcodebuild -project iContainer.xcodeproj -scheme iContainer -configuration Debug build

# Test (covers the CLI-output parsing layer)
xcodebuild -project iContainer.xcodeproj -scheme iContainer test
```

Please make sure the build is green and the tests pass before opening a PR.

## Project layout

- [`docs/PROJECT_CONTEXT.md`](docs/PROJECT_CONTEXT.md) — architecture and a
  map of every component. Start here.
- [`docs/UI_UX_GUIDELINES.md`](docs/UI_UX_GUIDELINES.md) — UI/UX conventions
  the app follows; please keep new UI consistent with them.
- [`docs/VERSIONING.md`](docs/VERSIONING.md) — release/versioning workflow.
- [`CHANGELOG.md`](CHANGELOG.md) — every user-visible change is recorded here.

## Pull requests

- Keep changes focused; one logical change per PR.
- All `container` CLI output parsing belongs in `CLIParsers.swift` (pure,
  unit-tested) — add or update tests in `iContainerTests/` when you touch it.
- Reuse the shared tokens in `DesignSystem.swift` (radii, outline, status
  dot, button style, tab picker) instead of hardcoding styles.
- Add a `CHANGELOG.md` entry under `[Unreleased]` for anything user-visible.
- Describe what you changed and how you verified it.

## A note on how this is built

iContainer is vibe-coded — designed and written hand-in-hand with
[Claude Code](https://claude.com/claude-code). Human-reviewed, but read the
code with that in mind. If something looks off, a PR or an issue is the best
way to flag it.
