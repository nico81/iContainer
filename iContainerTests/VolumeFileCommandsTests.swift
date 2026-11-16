import XCTest
@testable import iContainer

/// Tests for `VolumeFileCommands`: the argv built for volume file copies,
/// path sanitizing, name validation, error summaries and preview decoding.
final class VolumeFileCommandsTests: XCTestCase {
    private let exec = VolumeFileCommands.Access.exec(container: "db", mountPoint: "/var/lib/postgresql/data")
    private let helper = VolumeFileCommands.Access.helper(volume: "pgdata", image: "docker.io/library/alpine:latest")

    // MARK: - Paths and names

    func testSanitizedRelativePathDropsTraversal() {
        XCTAssertEqual(VolumeFileCommands.sanitizedRelativePath("a//b/../c/./"), "a/b/c")
        XCTAssertEqual(VolumeFileCommands.sanitizedRelativePath("../../etc"), "etc")
        XCTAssertEqual(VolumeFileCommands.sanitizedRelativePath(""), "")
    }

    func testDirectoryIsRootedAtMountOrHelper() {
        XCTAssertEqual(VolumeFileCommands.directory(exec, ""), "/var/lib/postgresql/data")
        XCTAssertEqual(VolumeFileCommands.directory(exec, "pg/base"), "/var/lib/postgresql/data/pg/base")
        XCTAssertEqual(VolumeFileCommands.directory(helper, "../x"), "/__vol/x")
    }

    func testValidNames() {
        XCTAssertTrue(VolumeFileCommands.isValidName("my file.txt"))
        XCTAssertTrue(VolumeFileCommands.isValidName("-dash"))
        XCTAssertFalse(VolumeFileCommands.isValidName(""))
        XCTAssertFalse(VolumeFileCommands.isValidName("."))
        XCTAssertFalse(VolumeFileCommands.isValidName(".."))
        XCTAssertFalse(VolumeFileCommands.isValidName("a/b"))
    }

    // MARK: - CLI arguments

    func testExecArguments() {
        XCTAssertEqual(VolumeFileCommands.cliArguments(exec, writable: true, stdin: true, command: ["tar"]),
                       ["exec", "-i", "db", "tar"])
        XCTAssertEqual(VolumeFileCommands.cliArguments(exec, writable: false, stdin: false, command: ["ls"]),
                       ["exec", "db", "ls"])
    }

    func testHelperMountsReadOnlyUnlessWritable() {
        XCTAssertEqual(VolumeFileCommands.cliArguments(helper, writable: false, stdin: false, command: ["ls"]),
                       ["run", "--rm", "-v", "pgdata:/__vol:ro", "docker.io/library/alpine:latest", "ls"])
        XCTAssertEqual(VolumeFileCommands.cliArguments(helper, writable: true, stdin: true, command: ["sh"]),
                       ["run", "--rm", "-i", "-v", "pgdata:/__vol", "docker.io/library/alpine:latest", "sh"])
    }

    func testArchiveCommandPrefixesNames() {
        XCTAssertEqual(VolumeFileCommands.archiveCommand(directory: "/__vol/a", names: ["-dash", "my dir"]),
                       ["tar", "-C", "/__vol/a", "-c", "-f", "-", "--", "./-dash", "./my dir"])
    }

    func testExtractCommandPassesNamesAsArguments() {
        let command = VolumeFileCommands.extractCommand(directory: "/data/pg", names: ["a file.txt"])
        XCTAssertEqual(Array(command.prefix(2)), ["sh", "-c"])
        XCTAssertEqual(Array(command.suffix(3)), ["sh", "/data/pg", "a file.txt"])
        XCTAssertTrue(command[2].contains("tar -x -o -f -"))
        XCTAssertTrue(command[2].contains("chown -R"))
    }

    func testRemoveCommandRefusesInvalidNames() {
        XCTAssertEqual(VolumeFileCommands.removeCommand(directory: "/__vol", names: ["a", "-b"]),
                       ["rm", "-rf", "--", "/__vol/a", "/__vol/-b"])
        XCTAssertNil(VolumeFileCommands.removeCommand(directory: "/__vol", names: []))
        XCTAssertNil(VolumeFileCommands.removeCommand(directory: "/__vol", names: [""]))
        XCTAssertNil(VolumeFileCommands.removeCommand(directory: "/__vol", names: [".."]))
        XCTAssertNil(VolumeFileCommands.removeCommand(directory: "/__vol", names: ["a/b"]))
    }

    func testPreviewReadsOneByteOverLimit() {
        XCTAssertEqual(VolumeFileCommands.previewCommand(path: "/__vol/x"),
                       ["head", "-c", String(VolumeFileCommands.previewLimit + 1), "--", "/__vol/x"])
    }

    func testHostArchiveUsesEachParentAndDropsMacMetadata() {
        let args = VolumeFileCommands.hostArchiveArguments([
            URL(fileURLWithPath: "/Users/me/Desktop/a.txt"),
            URL(fileURLWithPath: "/tmp/site", isDirectory: true),
        ])
        XCTAssertTrue(args.contains("--no-mac-metadata"))
        XCTAssertTrue(args.contains("--no-xattrs"))
        XCTAssertEqual(Array(args.suffix(6)), ["-C", "/Users/me/Desktop", "./a.txt", "-C", "/tmp", "./site"])
    }

    // MARK: - Errors

    func testErrorSummarySkipsProgressLines() {
        let stderr = "[1/6] Fetching image [0s]\n[6/6] Starting container [0s]\ntar: ./x: Cannot open: Permission denied\n"
        XCTAssertEqual(VolumeFileCommands.errorSummary(stderr, fallback: "f"), "tar: ./x: Cannot open: Permission denied")
        XCTAssertEqual(VolumeFileCommands.errorSummary("", fallback: "fallback"), "fallback")
    }

    func testErrorSummaryExplainsMinimalImagesAndReadOnlyMounts() {
        XCTAssertTrue(VolumeFileCommands.errorSummary("exec: \"tar\": executable file not found in $PATH", fallback: "")
            .contains("no shell or tar"))
        XCTAssertTrue(VolumeFileCommands.errorSummary("tar: can't open 'x': Read-only file system", fallback: "")
            .contains("read-only"))
    }

    // MARK: - Preview decoding

    func testPreviewTextDecodesUTF8() {
        let decoded = VolumeFileCommands.previewText(Data("listen 80;\n".utf8))
        XCTAssertEqual(decoded.text, "listen 80;\n")
        XCTAssertFalse(decoded.truncated)
    }

    func testPreviewTextFlagsBinary() {
        XCTAssertNil(VolumeFileCommands.previewText(Data([0x7F, 0x45, 0x4C, 0x46, 0x00, 0x01])).text)
    }

    func testPreviewTextTruncatesAndRepairsSplitCharacter() {
        // "é" is two bytes; put its first byte right at the limit.
        var data = Data(repeating: UInt8(ascii: "a"), count: VolumeFileCommands.previewLimit - 1)
        data.append(contentsOf: Array("é".utf8))
        data.append(contentsOf: Array("tail".utf8))
        let decoded = VolumeFileCommands.previewText(data)
        XCTAssertTrue(decoded.truncated)
        XCTAssertEqual(decoded.text?.count, VolumeFileCommands.previewLimit - 1)
    }
}
