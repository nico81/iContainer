## Summary

<!-- What does this change, and why? -->

## How verified

<!-- Build, tests, manual run against the container CLI, screenshots… -->

## Checklist

- [ ] Build is green (`xcodebuild -project iContainer.xcodeproj -scheme iContainer build`)
- [ ] Tests pass (`xcodebuild -project iContainer.xcodeproj -scheme iContainer test`)
- [ ] `container` CLI output parsing changes live in `CLIParsers.swift` with tests (if applicable)
- [ ] New UI reuses the shared tokens in `DesignSystem.swift`
- [ ] Added a `CHANGELOG.md` entry under `[Unreleased]` (if user-visible)
