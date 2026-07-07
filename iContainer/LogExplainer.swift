import Foundation
import Combine
import FoundationModels

/// On-device log analysis for the container Logs tab, powered by Apple's
/// Foundation Models framework (macOS 26+).
///
/// Everything runs locally: the log text — which routinely carries secrets,
/// tokens and connection strings — never leaves the machine. The on-device
/// model has a small context window, so we only feed it the tail of the
/// visible log text (see `maxCharacters`) and stream the Markdown report
/// back so it appears as it is generated.
@MainActor
final class LogExplainer: ObservableObject {
    /// The Markdown report produced by the model, updated live as it streams.
    @Published private(set) var explanation: String = ""
    @Published private(set) var isExplaining: Bool = false
    /// User-facing message when analysis can't run or fails. Mutually
    /// exclusive with a useful `explanation`.
    @Published private(set) var errorMessage: String?

    /// Upper bound on how much log text we hand to the model. The on-device
    /// model's context window (~4k tokens) is shared across our instructions,
    /// this log text AND the generated answer, so we send a relevance-filtered
    /// slice rather than the whole tail (see `buildPrompt`). (Empirically 12k
    /// characters overflowed the window; 4k leaves comfortable room for the
    /// reply.)
    private static let maxCharacters = 4_000

    /// Always keep at least this many of the most recent lines — the freshest
    /// context — before spending the rest of the budget on salient lines.
    private static let guaranteedTailCount = 12

    /// A line is "salient" (kept with priority even when old) if it contains
    /// any of these, matched case-insensitively. Patterns are delimited on
    /// purpose: a bare "error" would also match benign structured-log fields
    /// like `ErrorCode:`/`ErrorMessage:` that appear in *successful* lines, so
    /// we match `level=error`, `error:`, `error=`, `[error`, etc. instead.
    private static let salientKeywords = [
        "level=error", "level=fatal", "level=critical", "level=warn",
        "error:", "error=", " error ", "[error", "err:",
        "warning:", "[warn",
        "fatal", "panic", "exception", "traceback", "stack trace", "segfault",
        "fail", "denied", "refused", "timeout", "timed out",
        "unable", "cannot", "can't", "could not", "couldn't",
        "out of memory", "oom", "killed", "abort", "unhealthy", "crash"
    ]

    private var currentTask: Task<Void, Never>?

    /// Whether the on-device model can run right now, with a reason to show
    /// the user when it can't.
    enum Readiness {
        case ready
        case unavailable(String)
    }

    var readiness: Readiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.deviceNotEligible):
            return .unavailable("This Mac doesn’t support Apple Intelligence, which powers on-device log analysis.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Turn on Apple Intelligence in System Settings to analyze logs on-device.")
        case .unavailable(.modelNotReady):
            return .unavailable("The on-device model is still downloading or getting ready. Try again shortly.")
        case .unavailable(let other):
            return .unavailable("On-device log analysis is unavailable (\(other)).")
        }
    }

    private static let instructions = """
    You are a diagnostics assistant embedded in a macOS app that manages Apple Container (Linux containers run via the `container` CLI). \
    The user gives you the most recent log output from a single container. Analyze ONLY those logs and answer in concise Markdown.

    Structure the answer as:
    - **Summary** — one or two sentences on what the container appears to be doing and its overall health.
    - **Problems** — bullet the errors, warnings, crashes, panics or restart loops you find, quoting the key log line verbatim. Omit this section entirely if the logs look healthy.
    - **Likely cause** — your best explanation for the main problem. Omit if there is no problem.
    - **Suggested actions** — concrete next steps: shell commands, or port/volume/env/config changes to try. Omit if there is no problem.

    Rules: base everything strictly on the provided logs — never invent log lines or facts. Prefer specific, actionable advice over generic tips. Keep the whole answer short.
    """

    /// Kicks off a fresh analysis of `logs`, cancelling any in-flight run.
    func explain(logs: String) {
        cancel()
        errorMessage = nil
        explanation = ""

        let trimmed = logs.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "There are no logs to analyze yet."
            return
        }

        if case .unavailable(let reason) = readiness {
            errorMessage = reason
            return
        }

        let prompt = Self.buildPrompt(from: trimmed)
        isExplaining = true
        currentTask = Task {
            defer { isExplaining = false }
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                for try await partial in session.streamResponse(to: prompt) {
                    explanation = partial.content
                }
            } catch is CancellationError {
                // Dismissed or regenerated — leave the current state untouched.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Couldn’t analyze the logs: \(error.localizedDescription)"
            }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Builds the prompt body by selecting the most diagnostically relevant
    /// lines that fit `maxCharacters`, instead of blindly truncating. Keeps
    /// the recent tail plus any error/warning-looking line, in original order,
    /// marks omitted stretches so the model doesn't assume continuity, and
    /// lets the most recent lines win when the budget is tight.
    private static func buildPrompt(from logs: String) -> String {
        let lines = logs
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let total = lines.count

        func isSalient(_ line: String) -> Bool {
            let lower = line.lowercased()
            return salientKeywords.contains { lower.contains($0) }
        }

        var included = Set<Int>()
        var used = 0
        func tryAdd(_ i: Int) {
            guard !included.contains(i) else { return }
            let cost = lines[i].count + 1
            guard used + cost <= maxCharacters else { return }
            included.insert(i)
            used += cost
        }

        // 1. Guaranteed recent tail — freshest context, newest first.
        let tailStart = max(0, total - guaranteedTailCount)
        for i in stride(from: total - 1, through: tailStart, by: -1) { tryAdd(i) }

        // 2. Salient lines get priority over routine history, newest first, so
        //    an error far above the tail still makes it into the window.
        for i in stride(from: tailStart - 1, through: 0, by: -1) where isSalient(lines[i]) {
            tryAdd(i)
        }

        // 3. Spend any leftover budget extending the tail backwards.
        for i in stride(from: tailStart - 1, through: 0, by: -1) { tryAdd(i) }

        // 4. Reassemble chronologically, flagging omitted stretches.
        var out: [String] = []
        var previous = -1
        for i in included.sorted() {
            let gap = previous < 0 ? i : i - previous - 1
            if gap > 0 {
                out.append("[… \(gap) line(s) omitted …]")
            }
            out.append(lines[i])
            previous = i
        }

        let body = out.joined(separator: "\n")
        let preamble = included.count < total
            ? "Container logs — showing \(included.count) of \(total) lines (recent lines plus lines that look like errors or warnings; routine/older lines omitted):"
            : "Container logs:"
        return "\(preamble)\n\n\(body)"
    }
}
