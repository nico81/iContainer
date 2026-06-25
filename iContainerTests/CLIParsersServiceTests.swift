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
}
