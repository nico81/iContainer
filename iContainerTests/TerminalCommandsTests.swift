import XCTest
@testable import iContainer

/// Tests for `TerminalCommands`: the argv behind the interactive container
/// and machine terminals, and the Terminal.app hand-off script.
final class TerminalCommandsTests: XCTestCase {
    func testContainerShellUsesTTYAndFallsBackToSh() {
        let args = TerminalCommands.containerShell(containerId: "web", preferredShell: "/bin/bash")
        XCTAssertEqual(Array(args.prefix(6)), ["exec", "-t", "-i", "-e", "TERM=xterm-256color", "web"])
        XCTAssertEqual(Array(args.suffix(5)), ["/bin/sh", "-c", TerminalCommands.shellFallbackScript, "sh", "/bin/bash"])
        XCTAssertTrue(TerminalCommands.shellFallbackScript.hasSuffix("exec /bin/sh"))
    }

    func testMachineShellOpensLoginShell() {
        XCTAssertEqual(TerminalCommands.machineShell(machineId: "ubuntu", asRoot: false),
                       ["machine", "run", "-n", "ubuntu", "-t", "-i", "-e", "TERM=xterm-256color"])
        XCTAssertEqual(TerminalCommands.machineShell(machineId: "ubuntu", asRoot: true).last, "--root")
    }

    func testShellQuote() {
        XCTAssertEqual(TerminalCommands.shellQuote("plain"), "'plain'")
        XCTAssertEqual(TerminalCommands.shellQuote("it's"), #"'it'\''s'"#)
    }

    func testCommandFileQuotesEveryArgument() {
        let body = TerminalCommands.commandFile(cliPath: "/usr/local/bin/container",
                                                arguments: ["machine", "run", "-n", "my box"])
        XCTAssertEqual(body, "#!/bin/sh\nexec '/usr/local/bin/container' 'machine' 'run' '-n' 'my box'\n")
    }
}
