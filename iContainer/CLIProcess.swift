import Foundation

/// Minimal synchronous process runner shared by CLI wrappers that talk to
/// a binary other than Apple's `container` (currently `docker`).
///
/// Mirrors the hard-won details of `ContainerizationWrapper.runCommandBlocking`:
/// stdout and stderr are merged into one pipe, optional stdin is written
/// and closed before reading, and the pipe is drained **before**
/// `waitUntilExit()` — a child that writes more than the 64 KB pipe buffer
/// would otherwise block forever while we wait on its exit.
nonisolated enum CLIProcess {
    struct Result: Sendable {
        let output: String
        let status: Int32
    }

    static func run(
        executable: String,
        arguments: [String],
        standardInput: String? = nil,
        environment: [String: String]? = nil
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment { merged[key] = value }
            process.environment = merged
        }
        let pipe = Pipe()
        let inputPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        if standardInput != nil {
            process.standardInput = inputPipe
        }
        try process.run()
        if let standardInput {
            if let data = standardInput.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        return Result(output: output, status: process.terminationStatus)
    }
}
