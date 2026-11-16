import Foundation
import Combine

// MARK: - Commands (pure)

/// Builds the commands that move files in and out of a named volume.
///
/// `container cp` can't be used: verified on CLI 1.6.1 and 1.7.1, it ignores
/// volume mounts — it writes into (and reads from) the container's root
/// filesystem *underneath* the mount point, so nothing reaches the volume.
/// Everything here streams a tar archive through `container exec -i` (a
/// running container that mounts the volume) or a throwaway
/// `container run --rm -i` helper (volume not used by any container).
/// Verified with busybox tar (alpine) and GNU tar (debian-based images).
nonisolated enum VolumeFileCommands {
    /// How the volume's filesystem can be reached right now.
    enum Access: Equatable, Sendable {
        /// `container exec` into a running container that mounts the volume.
        case exec(container: String, mountPoint: String)
        /// `container run --rm` with the volume mounted at `helperMountPoint`.
        case helper(volume: String, image: String)

        /// Where the volume root is inside the container.
        var root: String {
            switch self {
            case .exec(_, let mountPoint): return mountPoint
            case .helper: return VolumeFileCommands.helperMountPoint
            }
        }
    }

    static let helperMountPoint = "/__vol"
    /// Text previews read at most this many bytes.
    static let previewLimit = 256 * 1024
    static let hostTar = "/usr/bin/tar"

    /// `a//b/../c/.` → `a/b/c`: no empty, `.` or `..` components, so a path
    /// can never climb out of the volume root.
    static func sanitizedRelativePath(_ path: String) -> String {
        path.split(separator: "/")
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }

    /// Absolute path inside the container for `relative` (volume-relative).
    static func directory(_ access: Access, _ relative: String) -> String {
        let clean = sanitizedRelativePath(relative)
        return clean.isEmpty ? access.root : access.root + "/" + clean
    }

    /// A single path component the user (or Finder) can name an entry with.
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    /// The `container` CLI arguments that run `command` against the volume.
    /// Helpers mount read-only unless `writable`.
    static func cliArguments(_ access: Access, writable: Bool, stdin: Bool, command: [String]) -> [String] {
        switch access {
        case .exec(let container, _):
            return ["exec"] + (stdin ? ["-i"] : []) + [container] + command
        case .helper(let volume, let image):
            return ["run", "--rm"] + (stdin ? ["-i"] : [])
                + ["-v", "\(volume):\(helperMountPoint)" + (writable ? "" : ":ro"), image] + command
        }
    }

    /// Archive `names` (entries of `directory`) to stdout. `./` keeps names
    /// starting with `-` from being read as options.
    static func archiveCommand(directory: String, names: [String]) -> [String] {
        ["tar", "-C", directory, "-c", "-f", "-", "--"] + names.map { "./" + $0 }
    }

    /// Extracts stdin into `$1`, then gives each extracted top-level entry
    /// the owner of the destination folder (a file dropped into a postgres
    /// data dir ends up `postgres`-owned, not `root`). `-o` = don't restore
    /// the archive's owner (busybox and GNU tar alike). chown failures are
    /// ignored: a container running as non-root already writes as itself.
    static let extractScript = #"set -e; cd "$1"; shift; tar -x -o -f -; owner=$(stat -c %u:%g .); for f in "$@"; do chown -R "$owner" -- "./$f" 2>/dev/null || true; done"#

    static func extractCommand(directory: String, names: [String]) -> [String] {
        ["sh", "-c", extractScript, "sh", directory] + names
    }

    static let makeDirectoryScript = #"set -e; cd "$1"; mkdir -- "./$2"; chown "$(stat -c %u:%g .)" -- "./$2" 2>/dev/null || true"#

    static func makeDirectoryCommand(directory: String, name: String) -> [String] {
        ["sh", "-c", makeDirectoryScript, "sh", directory, name]
    }

    /// `nil` when any name is invalid — never removes `directory` itself.
    static func removeCommand(directory: String, names: [String]) -> [String]? {
        guard !names.isEmpty, names.allSatisfy(isValidName) else { return nil }
        return ["rm", "-rf", "--"] + names.map { directory + "/" + $0 }
    }

    /// One byte over the limit tells us the file was truncated.
    static func previewCommand(path: String) -> [String] {
        ["head", "-c", String(previewLimit + 1), "--", path]
    }

    /// macOS `tar` arguments archiving `urls` (each from its own parent
    /// folder) to stdout, without Finder metadata (`._*` files, xattrs,
    /// ACLs, flags) that would litter a Linux volume.
    static func hostArchiveArguments(_ urls: [URL]) -> [String] {
        var arguments = ["-c", "-f", "-", "--no-mac-metadata", "--no-xattrs", "--no-acls", "--no-fflags"]
        for url in urls {
            arguments += ["-C", url.deletingLastPathComponent().path, "./" + url.lastPathComponent]
        }
        return arguments
    }

    static func hostExtractArguments(destination: URL) -> [String] {
        ["-x", "-f", "-", "-C", destination.path]
    }

    /// The useful part of a failed command's stderr: drops the CLI's
    /// `[n/6] Fetching …` progress lines and keeps the last few lines.
    static func errorSummary(_ stderr: String, fallback: String) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !($0.hasPrefix("[") && $0.contains("/") && $0.contains("]")) }
        let lower = lines.joined(separator: " ").lowercased()
        if lower.contains("executable file not found") || lower.contains("no such file or directory: tar")
            || (lower.contains("not found") && (lower.contains("tar") || lower.contains(" sh"))) {
            return "This container's image has no shell or tar (a minimal image), so files can't be copied through it."
        }
        if lower.contains("read-only file system") {
            return "The volume is mounted read-only in this container."
        }
        let summary = lines.suffix(3).joined(separator: "\n")
        return summary.isEmpty ? fallback : summary
    }

    /// Decodes a preview: `nil` text means binary (NUL bytes or not UTF-8).
    static func previewText(_ data: Data) -> (text: String?, truncated: Bool) {
        let truncated = data.count > previewLimit
        var body = data.prefix(previewLimit)
        if body.contains(0) { return (nil, truncated) }
        if let text = String(data: body, encoding: .utf8) { return (text, truncated) }
        // The cut may have split a multi-byte character.
        if truncated {
            for _ in 0..<3 where !body.isEmpty {
                body = body.dropLast()
                if let text = String(data: body, encoding: .utf8) { return (text, truncated) }
            }
        }
        return (nil, truncated)
    }
}

// MARK: - Process plumbing

/// Lets a running transfer be cancelled from the main actor: terminating
/// the processes closes their pipes, which unblocks the relay loop.
nonisolated final class VolumeTransferJob: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func register(_ process: Process) {
        lock.withLock {
            processes.append(process)
            if cancelled, process.isRunning { process.terminate() }
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            for process in processes where process.isRunning { process.terminate() }
        }
    }
}

nonisolated enum VolumeFileRunner {
    struct Output: Sendable {
        let stdout: Data
        let stderr: String
        let status: Int32
    }

    struct PipeOutput: Sendable {
        let producerStatus: Int32
        let producerError: String
        let consumerStatus: Int32
        let consumerOutput: String
        let bytes: Int64
    }

    private final class Box: @unchecked Sendable { var data = Data() }

    /// Runs one command with stdout and stderr kept apart (the CLI writes
    /// pull progress to stderr, which must not end up in a file preview).
    static func run(_ executable: String, _ arguments: [String], job: VolumeTransferJob? = nil) throws -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        job?.register(process)
        let errBox = Box()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: group) {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()
        return Output(stdout: data, stderr: String(decoding: errBox.data, as: UTF8.self), status: process.terminationStatus)
    }

    /// `producer | consumer`, relaying the bytes ourselves so the caller
    /// gets progress (`onBytes`, total so far) and can cancel. Both stderr
    /// streams are drained on their own threads so neither child can block.
    static func pipe(
        producer: (executable: String, arguments: [String], environment: [String: String]?),
        consumer: (executable: String, arguments: [String]),
        job: VolumeTransferJob,
        onBytes: @escaping (Int64) -> Void
    ) throws -> PipeOutput {
        // A consumer that dies early must surface as an error, not kill the app.
        signal(SIGPIPE, SIG_IGN)

        let source = Process()
        source.executableURL = URL(fileURLWithPath: producer.executable)
        source.arguments = producer.arguments
        if let environment = producer.environment {
            source.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        source.standardInput = FileHandle.nullDevice
        let sourceOut = Pipe(), sourceErr = Pipe()
        source.standardOutput = sourceOut
        source.standardError = sourceErr

        let sink = Process()
        sink.executableURL = URL(fileURLWithPath: consumer.executable)
        sink.arguments = consumer.arguments
        let sinkIn = Pipe(), sinkOut = Pipe()
        sink.standardInput = sinkIn
        sink.standardOutput = sinkOut
        sink.standardError = sinkOut

        try sink.run()
        job.register(sink)
        do {
            try source.run()
        } catch {
            sink.terminate()
            throw error
        }
        job.register(source)

        let sourceErrBox = Box(), sinkOutBox = Box()
        let group = DispatchGroup()
        DispatchQueue.global(qos: .utility).async(group: group) {
            sourceErrBox.data = sourceErr.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global(qos: .utility).async(group: group) {
            sinkOutBox.data = sinkOut.fileHandleForReading.readDataToEndOfFile()
        }

        let reader = sourceOut.fileHandleForReading
        let writer = sinkIn.fileHandleForWriting
        var total: Int64 = 0
        var sinkClosed = false
        while let chunk = try? reader.read(upToCount: 256 * 1024), !chunk.isEmpty {
            if !sinkClosed {
                do { try writer.write(contentsOf: chunk) } catch { sinkClosed = true }
            }
            // Keep draining even after the sink died, so the source can exit.
            total += Int64(chunk.count)
            onBytes(total)
        }
        try? writer.close()
        source.waitUntilExit()
        sink.waitUntilExit()
        group.wait()
        return PipeOutput(
            producerStatus: source.terminationStatus,
            producerError: String(decoding: sourceErrBox.data, as: UTF8.self),
            consumerStatus: sink.terminationStatus,
            consumerOutput: String(decoding: sinkOutBox.data, as: UTF8.self),
            bytes: total
        )
    }
}

// MARK: - Operations

/// File operations of one volume browser: upload, download, new folder,
/// delete, preview. Long transfers publish progress and can be cancelled.
@MainActor
final class VolumeFileOperations: ObservableObject {
    struct Activity: Equatable {
        let title: String
        var bytesDone: Int64
        let bytesTotal: Int64?
        let cancellable: Bool
    }

    struct Preview: Identifiable, Equatable {
        var id: String { path }
        let name: String
        let path: String
        let text: String?
        let truncated: Bool
    }

    @Published private(set) var activity: Activity?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    /// Files to reveal from the status line after a download.
    @Published private(set) var revealURLs: [URL] = []

    private var job: VolumeTransferJob?

    var isBusy: Bool { activity != nil }

    func cancel() { job?.cancel() }

    func clearMessages() {
        errorMessage = nil
        statusMessage = nil
        revealURLs = []
    }

    // MARK: Upload

    /// Copies `urls` from the Mac into `relativeDirectory`. `replacing`
    /// names are removed first (Finder-style replace, not a merge).
    func upload(_ urls: [URL], into relativeDirectory: String, replacing: [String], access: VolumeFileCommands.Access) async -> Bool {
        guard !urls.isEmpty, let cli = cliPath() else { return false }
        clearMessages()
        let directory = VolumeFileCommands.directory(access, relativeDirectory)
        let names = urls.map(\.lastPathComponent)
        let total = Self.totalSize(of: urls)

        if !replacing.isEmpty {
            activity = Activity(title: "Replacing \(Self.describe(replacing))…", bytesDone: 0, bytesTotal: nil, cancellable: false)
            guard let remove = VolumeFileCommands.removeCommand(directory: directory, names: replacing) else {
                activity = nil
                errorMessage = "Invalid file name."
                return false
            }
            let arguments = VolumeFileCommands.cliArguments(access, writable: true, stdin: false, command: remove)
            let result = try? await Task.detached(priority: .userInitiated) { try VolumeFileRunner.run(cli, arguments) }.value
            guard let result, result.status == 0 else {
                activity = nil
                errorMessage = VolumeFileCommands.errorSummary(result?.stderr ?? "", fallback: "Couldn't replace the existing items.")
                return false
            }
        }

        activity = Activity(title: "Copying \(Self.describe(names)) to the volume…", bytesDone: 0, bytesTotal: total, cancellable: true)
        let job = VolumeTransferJob()
        self.job = job
        let producer = (executable: VolumeFileCommands.hostTar,
                        arguments: VolumeFileCommands.hostArchiveArguments(urls),
                        environment: Optional(["COPYFILE_DISABLE": "1"]))
        let consumer = (executable: cli,
                        arguments: VolumeFileCommands.cliArguments(access, writable: true, stdin: true,
                                                                   command: VolumeFileCommands.extractCommand(directory: directory, names: names)))
        let output = await runPipe(producer: producer, consumer: consumer, job: job)
        self.job = nil
        activity = nil

        guard let output else { return false }
        if job.isCancelled {
            statusMessage = "Copy cancelled. Items already transferred may be incomplete."
            return false
        }
        guard output.producerStatus == 0, output.consumerStatus == 0 else {
            let detail = output.consumerStatus != 0 ? output.consumerOutput : output.producerError
            errorMessage = VolumeFileCommands.errorSummary(detail, fallback: "The copy failed.")
            return false
        }
        statusMessage = "Copied \(Self.describe(names)) (\(Self.format(output.bytes)))."
        return true
    }

    // MARK: Download

    func download(_ names: [String], from relativeDirectory: String, to destination: URL, access: VolumeFileCommands.Access) async -> Bool {
        guard !names.isEmpty, let cli = cliPath() else { return false }
        clearMessages()
        let directory = VolumeFileCommands.directory(access, relativeDirectory)
        activity = Activity(title: "Saving \(Self.describe(names)) to \(destination.lastPathComponent)…", bytesDone: 0, bytesTotal: nil, cancellable: true)
        let job = VolumeTransferJob()
        self.job = job
        let producer = (executable: cli,
                        arguments: VolumeFileCommands.cliArguments(access, writable: false, stdin: false,
                                                                   command: VolumeFileCommands.archiveCommand(directory: directory, names: names)),
                        environment: [String: String]?.none)
        let consumer = (executable: VolumeFileCommands.hostTar,
                        arguments: VolumeFileCommands.hostExtractArguments(destination: destination))
        let output = await runPipe(producer: producer, consumer: consumer, job: job)
        self.job = nil
        activity = nil

        guard let output else { return false }
        if job.isCancelled {
            statusMessage = "Save cancelled. Files already written to \(destination.lastPathComponent) may be incomplete."
            return false
        }
        guard output.producerStatus == 0, output.consumerStatus == 0 else {
            let detail = output.producerStatus != 0 ? output.producerError : output.consumerOutput
            errorMessage = VolumeFileCommands.errorSummary(detail, fallback: "Saving to the Mac failed.")
            return false
        }
        statusMessage = "Saved \(Self.describe(names)) to \(destination.lastPathComponent) (\(Self.format(output.bytes)))."
        revealURLs = names.map { destination.appendingPathComponent($0) }
        return true
    }

    // MARK: New folder / delete / preview

    func makeDirectory(_ name: String, in relativeDirectory: String, access: VolumeFileCommands.Access) async -> Bool {
        guard VolumeFileCommands.isValidName(name) else {
            errorMessage = "A folder name can't be empty, “.”, “..” or contain “/”."
            return false
        }
        let command = VolumeFileCommands.makeDirectoryCommand(directory: VolumeFileCommands.directory(access, relativeDirectory), name: name)
        return await runSimple(command, access: access, title: "Creating “\(name)”…", failure: "Couldn't create the folder.",
                               success: "Created folder “\(name)”.")
    }

    func delete(_ names: [String], in relativeDirectory: String, access: VolumeFileCommands.Access) async -> Bool {
        guard let command = VolumeFileCommands.removeCommand(directory: VolumeFileCommands.directory(access, relativeDirectory), names: names) else {
            errorMessage = "Invalid file name."
            return false
        }
        return await runSimple(command, access: access, title: "Deleting \(Self.describe(names))…", failure: "Couldn't delete.",
                               success: "Deleted \(Self.describe(names)).")
    }

    func preview(_ name: String, in relativeDirectory: String, access: VolumeFileCommands.Access) async -> Preview? {
        guard let cli = cliPath() else { return nil }
        clearMessages()
        let path = VolumeFileCommands.directory(access, relativeDirectory) + "/" + name
        activity = Activity(title: "Reading “\(name)”…", bytesDone: 0, bytesTotal: nil, cancellable: false)
        defer { activity = nil }
        let arguments = VolumeFileCommands.cliArguments(access, writable: false, stdin: false, command: VolumeFileCommands.previewCommand(path: path))
        let result = try? await Task.detached(priority: .userInitiated) { try VolumeFileRunner.run(cli, arguments) }.value
        guard let result, result.status == 0 else {
            errorMessage = VolumeFileCommands.errorSummary(result?.stderr ?? "", fallback: "Couldn't read the file.")
            return nil
        }
        let decoded = VolumeFileCommands.previewText(result.stdout)
        return Preview(name: name, path: VolumeFileCommands.sanitizedRelativePath(relativeDirectory + "/" + name),
                       text: decoded.text, truncated: decoded.truncated)
    }

    // MARK: Helpers

    private func runSimple(_ command: [String], access: VolumeFileCommands.Access, title: String, failure: String, success: String) async -> Bool {
        guard let cli = cliPath() else { return false }
        clearMessages()
        activity = Activity(title: title, bytesDone: 0, bytesTotal: nil, cancellable: false)
        defer { activity = nil }
        let arguments = VolumeFileCommands.cliArguments(access, writable: true, stdin: false, command: command)
        let result = try? await Task.detached(priority: .userInitiated) { try VolumeFileRunner.run(cli, arguments) }.value
        guard let result, result.status == 0 else {
            errorMessage = VolumeFileCommands.errorSummary(result?.stderr ?? "", fallback: failure)
            return false
        }
        statusMessage = success
        return true
    }

    private func runPipe(
        producer: (executable: String, arguments: [String], environment: [String: String]?),
        consumer: (executable: String, arguments: [String]),
        job: VolumeTransferJob
    ) async -> VolumeFileRunner.PipeOutput? {
        // Progress hops to the main actor at most every 512 KB.
        let throttle = ProgressThrottle()
        let report: @Sendable (Int64) -> Void = { [weak self] bytes in
            guard throttle.shouldReport(bytes) else { return }
            Task { @MainActor in self?.activity?.bytesDone = bytes }
        }
        do {
            return try await Task.detached(priority: .userInitiated) {
                try VolumeFileRunner.pipe(producer: producer, consumer: consumer, job: job, onBytes: report)
            }.value
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func cliPath() -> String? {
        guard let path = SettingsManager.resolvedContainerCLIPath() else {
            errorMessage = "container CLI not found."
            return nil
        }
        return path
    }

    nonisolated static func totalSize(of urls: [URL]) -> Int64? {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        for url in urls {
            if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
                continue
            }
            guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { continue }
            for case let file as URL in enumerator {
                if let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
                    total += Int64(values.fileSize ?? 0)
                }
            }
        }
        return total > 0 ? total : nil
    }

    nonisolated static func describe(_ names: [String]) -> String {
        names.count == 1 ? "“\(names[0])”" : "\(names.count) items"
    }

    nonisolated static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private nonisolated final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Int64 = 0

    func shouldReport(_ bytes: Int64) -> Bool {
        lock.withLock {
            guard bytes - last >= 512 * 1024 || last == 0 else { return false }
            last = bytes
            return true
        }
    }
}
