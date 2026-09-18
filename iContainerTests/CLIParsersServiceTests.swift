import XCTest
@testable import iContainer

/// Tests for `CLIParsers.parseServiceDetails` and
/// `CLIParsers.limitedLogOutput`.
final class CLIParsersServiceTests: XCTestCase {

    // MARK: - parseServiceDetails

    func testParseServiceDetailsEmpty() {
        let details = CLIParsers.parseServiceDetails("")
        XCTAssertNil(details.version)
        XCTAssertNil(details.commit)
        XCTAssertNil(details.dataRoot)
        XCTAssertNil(details.installRoot)
    }

    func testParseServiceDetailsTabularFormat() {
        let output = """
        Field                          Value
        apiserver.version              0.3.1
        apiserver.commit               deadbeef1234
        dataRoot                       /var/lib/container
        installRoot                    /usr/local
        """
        let details = CLIParsers.parseServiceDetails(output)
        XCTAssertEqual(details.version, "0.3.1")
        XCTAssertEqual(details.commit, "deadbeef1234")
        XCTAssertEqual(details.dataRoot, "/var/lib/container")
        XCTAssertEqual(details.installRoot, "/usr/local")
    }

    func testParseServiceDetailsAlternateKeys() {
        let output = """
        container-apiserver.version    1.2.3
        container-apiserver.commit     cafebabe
        data_root                      /var/data
        install_root                   /opt
        """
        let details = CLIParsers.parseServiceDetails(output)
        XCTAssertEqual(details.version, "1.2.3")
        XCTAssertEqual(details.commit, "cafebabe")
        XCTAssertEqual(details.dataRoot, "/var/data")
        XCTAssertEqual(details.installRoot, "/opt")
    }

    func testParseServiceDetailsInlineVersionAndCommit() {
        // Heuristic-style line: version embedded together with commit hash.
        let output = "version: 2.0.0 (commit abc123)"
        let details = CLIParsers.parseServiceDetails(output)
        XCTAssertEqual(details.version, "2.0.0")
        XCTAssertEqual(details.commit, "abc123")
    }

    func testParseServiceDetailsIgnoresHeader() {
        let output = """
        Field Value
        version  9.9.9
        """
        let details = CLIParsers.parseServiceDetails(output)
        XCTAssertEqual(details.version, "9.9.9")
    }

    /// Real `container system status` output from CLI 1.4.1 (2026-09-18):
    /// dotted `server.*` / `client.*` / `host.*` / `paths.*` keys plus
    /// container/image counters. `paths.logRoot` is present but empty.
    func testParseServiceDetailsCLI141Table() {
        let output = #"""
FIELD               VALUE
status              running
client.version      1.4.1
client.build        release
client.commit       9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d
host.os             Version 27.0 (Build 26A428)
host.architecture   arm64
host.cpus           8
server.version      1.4.1
server.build        release
server.commit       9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d
server.appName      container-apiserver
paths.appRoot       /Users/nico/Library/Application Support/com.apple.container/
paths.installRoot   /usr/local/
paths.logRoot       
containers.total    10
containers.running  0
images.total        27
"""#
        let d = CLIParsers.parseServiceDetails(output)
        XCTAssertEqual(d.status, "running")
        XCTAssertEqual(d.version, "1.4.1")
        XCTAssertEqual(d.build, "release")
        XCTAssertEqual(d.commit, "9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d")
        XCTAssertEqual(d.serverAppName, "container-apiserver")
        XCTAssertEqual(d.clientVersion, "1.4.1")
        XCTAssertEqual(d.clientBuild, "release")
        XCTAssertEqual(d.clientCommit, "9a8917ca2da5cd6ba059b9ba5ca5a74892e9bb7d")
        XCTAssertEqual(d.hostOS, "Version 27.0 (Build 26A428)")
        XCTAssertEqual(d.hostArchitecture, "arm64")
        XCTAssertEqual(d.hostCPUs, 8)
        XCTAssertEqual(d.dataRoot, "/Users/nico/Library/Application Support/com.apple.container/")
        XCTAssertEqual(d.installRoot, "/usr/local/")
        XCTAssertNil(d.logRoot, "empty value must stay nil")
        XCTAssertEqual(d.containersTotal, 10)
        XCTAssertEqual(d.containersRunning, 0)
        XCTAssertEqual(d.imagesTotal, 27)
        XCTAssertFalse(d.hasVersionMismatch)
    }

    /// CLI 1.0–1.3 layout: long-form `apiserver.version` line carrying build
    /// and commit, `appRoot` instead of `paths.appRoot`.
    func testParseServiceDetailsCLI13Table() {
        let output = """
        FIELD              VALUE
        status             running
        appRoot            /Users/demo/Library/Application Support/com.apple.container/
        installRoot        /usr/local/
        logRoot            
        apiserver.version  container-apiserver version 1.3.1 (build: release, commit: a9a62e2)
        apiserver.commit   a9a62e28f6beb88940122a3d7b286f2d5ae8053a
        apiserver.build    release
        """
        let d = CLIParsers.parseServiceDetails(output)
        XCTAssertEqual(d.status, "running")
        XCTAssertEqual(d.version, "1.3.1")
        XCTAssertEqual(d.commit, "a9a62e28f6beb88940122a3d7b286f2d5ae8053a", "full-hash row wins over the inline short hash")
        XCTAssertEqual(d.build, "release")
        XCTAssertEqual(d.dataRoot, "/Users/demo/Library/Application Support/com.apple.container/")
        XCTAssertEqual(d.installRoot, "/usr/local/")
        XCTAssertNil(d.clientVersion)
        XCTAssertNil(d.hostCPUs)
    }

    func testVersionMismatchDetection() {
        var d = ServiceDetails()
        d.version = "1.3.1"; d.clientVersion = "1.4.1"
        XCTAssertTrue(d.hasVersionMismatch)
        d.version = "1.4.1"
        XCTAssertFalse(d.hasVersionMismatch)
    }

    // MARK: - system df

    func testParseSystemDiskUsage() {
        let output = #"""
{
  "containers" : {
    "active" : 0,
    "reclaimable" : 6646988800,
    "sizeInBytes" : 6646988800,
    "total" : 10
  },
  "images" : {
    "active" : 10,
    "reclaimable" : 6789218304,
    "sizeInBytes" : 16901574656,
    "total" : 27
  },
  "volumes" : {
    "active" : 0,
    "reclaimable" : 555122688,
    "sizeInBytes" : 555122688,
    "total" : 8
  }
}
"""#
        let usage = CLIParsers.parseSystemDiskUsage(output)
        XCTAssertEqual(usage?.images?.total, 27)
        XCTAssertEqual(usage?.images?.active, 10)
        XCTAssertEqual(usage?.images?.sizeBytes, 16_901_574_656)
        XCTAssertEqual(usage?.images?.reclaimableBytes, 6_789_218_304)
        XCTAssertEqual(usage?.containers?.total, 10)
        XCTAssertEqual(usage?.containers?.active, 0)
        XCTAssertEqual(usage?.volumes?.total, 8)
        XCTAssertEqual(usage?.volumes?.sizeBytes, 555_122_688)
    }

    func testParseSystemDiskUsageMalformed() {
        XCTAssertNil(CLIParsers.parseSystemDiskUsage(""))
        XCTAssertNil(CLIParsers.parseSystemDiskUsage("[]"))
        XCTAssertNil(CLIParsers.parseSystemDiskUsage("{\"unrelated\": 1}"))
    }

    // MARK: - container CLI path selection

    func testContainerCLIPathCandidatesPreferAppleSiliconHomebrewOverLegacyUsrLocal() {
        let candidates = SettingsManager.containerCLIPathCandidates(
            pathEnvironment: "/usr/local/bin:/opt/homebrew/bin:/usr/bin"
        )

        XCTAssertEqual(candidates.prefix(2), [
            "/opt/homebrew/bin/container",
            "/usr/local/bin/container"
        ])
    }

    func testContainerCLIPathCandidatesDeduplicatePathEntries() {
        let candidates = SettingsManager.containerCLIPathCandidates(
            pathEnvironment: "/opt/homebrew/bin:/usr/local/bin:/custom/bin"
        )

        XCTAssertEqual(candidates, [
            "/opt/homebrew/bin/container",
            "/usr/local/bin/container",
            "/custom/bin/container"
        ])
    }

    func testParseCLIVersionComponents() {
        XCTAssertEqual(
            SettingsManager.parseCLIVersionComponents("container CLI version 1.0.0 (build: release, commit: ee848e3)"),
            [1, 0, 0]
        )
        XCTAssertEqual(SettingsManager.parseCLIVersionComponents("v0.4.1"), [0, 4, 1])
        XCTAssertNil(SettingsManager.parseCLIVersionComponents("no version here"))
    }

    func testVersionComparisonPicksHigherAndHandlesUnequalLengths() {
        XCTAssertTrue(SettingsManager.versionIsLower([0, 4, 1], than: [1, 0, 0]))
        XCTAssertFalse(SettingsManager.versionIsLower([1, 0, 0], than: [0, 9, 9]))
        XCTAssertFalse(SettingsManager.versionIsLower([1, 0], than: [1, 0, 0])) // equal
        XCTAssertTrue(SettingsManager.versionIsLower([], than: [1]))            // missing → 0
    }

    // MARK: - limitedLogOutput

    func testLimitedLogOutputShortPasses() {
        let short = "line1\nline2\nline3"
        XCTAssertEqual(CLIParsers.limitedLogOutput(short, maxLines: 500), short)
    }

    func testLimitedLogOutputTruncatesAndAnnotates() {
        let lines = (1...600).map { "line\($0)" }
        let full = lines.joined(separator: "\n")
        let limited = CLIParsers.limitedLogOutput(full, maxLines: 500)

        XCTAssertTrue(
            limited.hasPrefix("Showing the latest 500 of 600 log lines."),
            "Expected a truncation banner, got: \(limited.prefix(80))"
        )
        // The last line must still be present.
        XCTAssertTrue(limited.hasSuffix("line600"))
        // The first line should have been dropped.
        XCTAssertFalse(limited.contains("line1\n"))
    }

    func testLimitedLogOutputRespectsCustomMax() {
        let lines = (1...20).map { "L\($0)" }.joined(separator: "\n")
        let limited = CLIParsers.limitedLogOutput(lines, maxLines: 5)
        XCTAssertTrue(limited.contains("Showing the latest 5 of 20 log lines."))
        XCTAssertTrue(limited.hasSuffix("L20"))
    }

    func testLimitedLogOutputBoundaryEqual() {
        // Exactly maxLines: no truncation.
        let lines = (1...500).map { "L\($0)" }.joined(separator: "\n")
        XCTAssertEqual(CLIParsers.limitedLogOutput(lines, maxLines: 500), lines)
    }

    // MARK: - system property list

    func testParseSystemPropertiesSectionsAndValues() {
        let output = """

        [build]
        cpus = 2
        image = "ghcr.io/apple/container-builder-shim/builder:0.13.1"
        memory = "2048mb"
        rosetta = true

        [container]
        cpus = 4
        memory = "1gb"

        [dns]
        """
        let props = CLIParsers.parseSystemProperties(output)
        XCTAssertEqual(props["build"]?["cpus"], "2")
        XCTAssertEqual(props["build"]?["image"], "ghcr.io/apple/container-builder-shim/builder:0.13.1")
        XCTAssertEqual(props["container"]?["memory"], "1gb")
        XCTAssertEqual(props["dns"], [:], "empty section is present but has no keys")
        XCTAssertNil(CLIParsers.systemDNSDomain(from: output))
    }

    func testSystemDNSDomainWhenConfigured() {
        let output = """
        [container]
        cpus = 4

        [dns]
        domain = "test"
        """
        XCTAssertEqual(CLIParsers.systemDNSDomain(from: output), "test")
        XCTAssertNil(CLIParsers.systemDNSDomain(from: ""))
        XCTAssertNil(CLIParsers.systemDNSDomain(from: "[dns]\ndomain = \"\""))
    }
}
