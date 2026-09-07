# iContainerTests

Unit tests for the pure parsers in `CLIParsers.swift`. All tests run without
spawning a process, touching the network, or hitting the filesystem.

## Files

| File | Covers |
|------|--------|
| `CLIParsersImageTests.swift` | `splitReference`, `parseImageList` |
| `CLIParsersRegistryTests.swift` | `parseRegistryHosts`, `registryLoginHosts`, `isRegistryAuthError`, `isLikelyDockerHubImageReferenceError`, `looksLikeTopLevelHelp` |
| `CLIParsersInspectTests.swift` | `parseEditableSettings`, `normalizedContainerName` |
| `CLIParsersServiceTests.swift` | `parseServiceDetails`, `limitedLogOutput`, `parseSystemProperties` / `systemDNSDomain` |
| `ComposeParserTests.swift` | `ComposeParser` (compose-file subset, ordering, unsupported directives) |
| `ContainerCLIArgumentsTests.swift` | `ContainerCreateSpec` → `container create` flag builder |
| `DockerParsersTests.swift` (+ `DockerFixtures.swift`) | Docker `images`/`ps` NDJSON, `inspect`, Docker → `container` translation rules, reference normalisation, `image load` output |

About **128 test cases** in total.

## Setup

The test target is already declared in `iContainer.xcodeproj` and uses
a file-system synchronised group rooted at this folder, so any `*.swift`
file dropped in here is picked up automatically — no Xcode edits needed.

If you ever recreate the target from scratch (e.g. on a fresh project):

1. Open `iContainer.xcodeproj` in Xcode.
2. **File → New → Target…** (or `⌘⇧T` on the project navigator).
3. Choose **macOS → Unit Testing Bundle** and click Next.
4. Set **Product Name**: `iContainerTests`.
5. Set **Target to be Tested**: `iContainer`.
6. **Language**: Swift. **Project**: iContainer. Click Finish.
7. Delete the auto-generated `iContainerTests.swift` placeholder
   (Xcode creates it with Swift Testing; this project uses XCTest).
8. In the test target's **Build Settings**, ensure **Default Actor
   Isolation** is set to `MainActor` (matches the app target).

### Xcode 26 logging quirk

On first run, Xcode may surface:

> Logging Error: Failed to initialize logging system due to time out.

The tests still execute and pass — it's a known logging glitch in
Xcode 26. To silence it, edit the `iContainer` scheme:

**Product → Scheme → Edit Scheme… → Test → Arguments → Environment
Variables**, add `IDEPreferLogStreaming = YES`.

## Running the tests

- `⌘U` in Xcode, or
- From CLI:
  ```bash
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild test \
    -project iContainer.xcodeproj \
    -scheme iContainer \
    -destination 'platform=macOS'
  ```

## Adding new tests

Drop a new `*.swift` file in this folder. Because the target is configured
as a file-system synchronised root group, Xcode picks it up automatically —
no `pbxproj` edits required.

All test files should:
- `@testable import iContainer`
- subclass `XCTestCase`
- exercise only `CLIParsers` (or other pure types). Anything that touches
  `Process`, `Pipe`, the network, or `MainActor`-isolated state belongs in
  the app target, not here.
