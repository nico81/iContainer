import XCTest
@testable import iContainer

/// `CLIParsers.parseReleaseNotes` on real `apple/container` release bodies.
final class CLIReleaseNotesTests: XCTestCase {

    /// 1.6.1 has no `## Highlights` header (starts with the legend).
    static let notes161 = #"""
⌨️ denotes breaking CLI changes.

👩‍💻 denotes breaking API changes.

- Core
  - [Fix signals not properly passed to container processes](https://github.com/apple/container/pull/2276)
- Kubernetes
  - [Fix problems when creating clusters concurrently](https://github.com/apple/container/pull/2276)
  - [Rename to `container cluster`](https://github.com/apple/container/pull/2427)

## What's Changed
* Fix host port conflicts and leftover failed nodes during cluster creation by @dkovba in https://github.com/apple/container/pull/2399
* Fix forwarded process signal encoding by @vincent-peng in https://github.com/apple/container/pull/1778
* Remove SIGWINCH from signal kill set by @ArasanDev in https://github.com/apple/container/pull/1854
* Infer platform and runtime from OCI image by @noah-thor in https://github.com/apple/container/pull/2422
* rename to container cluster by @crosbymichael in https://github.com/apple/container/pull/2427

## New Contributors
* @vincent-peng made their first contribution in https://github.com/apple/container/pull/1778
* @ArasanDev made their first contribution in https://github.com/apple/container/pull/1854

**Full Changelog**: https://github.com/apple/container/compare/1.6.0...1.6.1
"""#

    /// 1.5.0: `## Highlights`, a security group, ⌨️ breaking item.
    static let notes150 = #"""
## Highlights

⌨️ denotes breaking CLI changes.

👩‍💻 denotes breaking API changes.

- Security
  - [GHSA-44v5-vx46-ghv6](https://github.com/apple/container/security/advisories/GHSA-44v5-vx46-ghv6) - K8s Plugin: sanitize kubeconfig values from guest before merging with host kubeconfig
- Core
  - [Commands now run when the image entrypoint is empty](https://github.com/apple/container/pull/2296)
  - [Fixed container egress loss after localhost DNS changes](https://github.com/apple/container/pull/2256)
  - [Better error message for unknown commands](https://github.com/apple/container/pull/2311)
- Kubernetes
  - ⌨️ [Removed `container k8s start` for now. To restart a stopped node, delete the cluster and create it again](https://github.com/apple/container/pull/2290)
  - [New `--cni` option on `container k8s create` for a custom CNI manifest](https://github.com/apple/container/pull/2254)
## What's Changed
* Update README as v1.0.0 has been reached by @gvenzl in https://github.com/apple/container/pull/2233
* Fix a compilation warning by @dkovba in https://github.com/apple/container/pull/2251
* Fix container egress loss after localhost DNS changes by @realrajaryan in https://github.com/apple/container/pull/2256
* forwarder: close backend channel immediately if frontend closes by @egernst in https://github.com/apple/container/pull/2260
* docs: use an existing kindest/node tag in the k8s node image example by @saiyam1814 in https://github.com/apple/container/pull/2257
* K8s plugin: Support custom CNI manifest by @katiewasnothere in https://github.com/apple/container/pull/2254
* fix(k8s): correct k8s control plane components version using the user specified node image version by @zdk in https://github.com/apple/container/pull/2271
* Fix Globber dropping directory contents under a symlinked ancestor by @JaewonHur in https://github.com/apple/container/pull/2252
* Remove k8s start command for now by @katiewasnothere in https://github.com/apple/container/pull/2290
* Sync command reference with current CLI options by @rishabhsai in https://github.com/apple/container/pull/2265
* Run commands when image entrypoint is empty by @danielsyauqi in https://github.com/apple/container/pull/2296
* fix(k8s): use the node's configured iptables backend for node prep by @guanchzhou in https://github.com/apple/container/pull/2145
* Update to latest containerization@0.47.0 by @katiewasnothere in https://github.com/apple/container/pull/2301
* Better error message for unknown commands by @realrajaryan in https://github.com/apple/container/pull/2311
* Remove PLUGINS section from help message by @JaewonHur in https://github.com/apple/container/pull/2309
* K8s Plugin: sanitize kubeconfig values from guest before merging with host kubeconfig by @katiewasnothere in https://github.com/apple/container/pull/2310
* Update plugin error test by @realrajaryan in https://github.com/apple/container/pull/2313

## New Contributors
* @gvenzl made their first contribution in https://github.com/apple/container/pull/2233
* @saiyam1814 made their first contribution in https://github.com/apple/container/pull/2257
* @rishabhsai made their first contribution in https://github.com/apple/container/pull/2265
* @danielsyauqi made their first contribution in https://github.com/apple/container/pull/2296
* @guanchzhou made their first contribution in https://github.com/apple/container/pull/2145

**Full Changelog**: https://github.com/apple/container/compare/1.4.1...1.5.0
"""#

    func testPatchReleaseWithoutHighlightsHeader() {
        let notes = CLIParsers.parseReleaseNotes(Self.notes161)
        XCTAssertEqual(notes.highlights.map(\.title), ["Core", "Kubernetes"])
        XCTAssertEqual(notes.highlights[0].items.map(\.text), ["Fix signals not properly passed to container processes"])
        XCTAssertEqual(notes.highlights[0].items[0].url?.absoluteString, "https://github.com/apple/container/pull/2276")
        XCTAssertEqual(notes.highlights[1].items.count, 2)
        XCTAssertEqual(notes.highlights[1].items[1].text, "Rename to `container cluster`", "inline code kept for Markdown rendering")
        XCTAssertTrue(notes.breakingItems.isEmpty)
        XCTAssertEqual(notes.changes.count, 5)
        XCTAssertEqual(notes.changes[0].author, "dkovba")
        XCTAssertEqual(notes.changes[0].url?.absoluteString, "https://github.com/apple/container/pull/2399")
        XCTAssertEqual(notes.changes.last?.title, "rename to container cluster")
        XCTAssertFalse(notes.highlights.flatMap(\.items).contains { $0.text.contains("denotes") }, "legend is not an item")
    }

    func testMinorReleaseWithHighlightsAndBreakingChange() {
        let notes = CLIParsers.parseReleaseNotes(Self.notes150)
        XCTAssertEqual(notes.highlights.map(\.title), ["Security", "Core", "Kubernetes"])
        let breaking = notes.breakingItems
        XCTAssertEqual(breaking.count, 1)
        XCTAssertTrue(breaking[0].isBreakingCLI)
        XCTAssertTrue(breaking[0].text.hasPrefix("Removed `container k8s start` for now"))
        XCTAssertEqual(breaking[0].url?.absoluteString, "https://github.com/apple/container/pull/2290")
        XCTAssertEqual(notes.highlightCount, 6, "Security 1 + Core 3 + Kubernetes 2")
        XCTAssertTrue(notes.changes.count > 10)
        XCTAssertFalse(notes.changes.contains { $0.title.contains("first contribution") }, "New Contributors excluded")
    }

    func testUngroupedItemsAndGarbage() {
        let notes = CLIParsers.parseReleaseNotes("""
        ## Highlights
        - [Standalone fix](https://example.com/1)
        - 👩‍💻 [API change](https://example.com/2)
        """)
        XCTAssertEqual(notes.highlights.count, 1)
        XCTAssertNil(notes.highlights[0].title)
        XCTAssertEqual(notes.highlights[0].items.map(\.text), ["Standalone fix", "API change"])
        XCTAssertTrue(notes.highlights[0].items[1].isBreakingAPI)
        XCTAssertTrue(CLIParsers.parseReleaseNotes("").isEmpty)
        XCTAssertTrue(CLIParsers.parseReleaseNotes("just some text").isEmpty)
    }

    /// GitHub serves the bodies with CRLF line endings.
    func testCRLFLineEndings() {
        let crlf = Self.notes150.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(CLIParsers.parseReleaseNotes(crlf), CLIParsers.parseReleaseNotes(Self.notes150))
    }
}
