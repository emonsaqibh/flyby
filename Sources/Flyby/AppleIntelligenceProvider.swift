import AppKit
import FoundationModels
import FlybyCore

/// Answers with Apple's on-device model, through FoundationModels: no key, no
/// account, and nothing leaves the Mac. Also no web — it knows what it knew
/// when it was trained, and is told to say so rather than guess at anything
/// newer.
///
/// Streams the answer as it grows: each element is the whole answer so far,
/// which is what the model hands back, rather than a delta.
@MainActor
enum AppleIntelligenceProvider {
    /// Whether the model can answer on this Mac right now.
    enum Readiness: Equatable {
        case ready
        /// Apple Intelligence is off; System Settings can turn it on.
        case turnedOff
        /// On, but the model isn't downloaded (or updated) yet.
        case preparing
        /// This Mac, or this region, can't run it.
        case unsupported

        /// Why it can't answer, worded for the person asking. `nil` when ready.
        var problem: String? {
            switch self {
            case .ready:
                return nil
            case .turnedOff:
                return "Apple Intelligence is turned off. Turn it on in System Settings › Apple Intelligence & Siri to get answers on this Mac."
            case .preparing:
                return "Apple Intelligence is still getting its model ready — it may be downloading. Try again in a few minutes."
            case .unsupported:
                return "Apple Intelligence isn't available on this Mac."
            }
        }
    }

    /// `SystemLanguageModel` is observable, so a view that reads this redraws
    /// when the model finishes downloading or Apple Intelligence is turned on.
    static var readiness: Readiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(.appleIntelligenceNotEnabled):
            return .turnedOff
        case .unavailable(.modelNotReady):
            return .preparing
        case .unavailable:
            return .unsupported
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The earlier turns a follow-up carries, sized for this model's context
    /// window rather than Gemini's: a first cut by characters, at about three
    /// a token, with half the window left for the question and the answer.
    /// That undercounts languages that take a token a character, so the
    /// session trims again by the model's own token count.
    static func context(from turns: [ConversationTurn]) -> [ChatMessage] {
        let budget = SystemLanguageModel.default.contextSize * 3 / 2
        return ChatContext.messages(
            from: turns,
            maxTurns: 4,
            maxAnswerCharacters: min(1_500, budget / 2),
            maxTotalCharacters: budget
        )
    }

    // MARK: - Answering

    /// `context` is the conversation so far, for a follow-up; empty for a
    /// first question.
    static func stream(query: String, context: [ChatMessage] = []) -> AsyncThrowingStream<String, Error> {
        let readiness = readiness
        let session = context.isEmpty ? takeWarmSession() : nil
        // Each element supersedes the last, so a reader that falls behind
        // only needs the newest.
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                do {
                    if let problem = readiness.problem { throw AppleIntelligenceError(problem) }
                    let session = if let session { session } else { await makeSession(context: context) }
                    for try await snapshot in session.streamResponse(to: query) {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: AppleIntelligenceError(explaining: error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Warming up

    /// A session with the instructions already loaded, made as Flyby
    /// opens so the first question doesn't also pay for loading the model.
    private static var warmSession: (session: LanguageModelSession, made: Date)?

    /// Loads the model while the user types. Kept for the first question,
    /// which starts a new conversation; a follow-up needs the conversation in
    /// its session and makes its own.
    static func prewarm() {
        guard readiness == .ready else { return }
        if let warmSession, isFresh(warmSession.made) { return }
        let session = LanguageModelSession(model: .default, instructions: instructions())
        session.prewarm()
        warmSession = (session, Date())
    }

    private static func takeWarmSession() -> LanguageModelSession? {
        defer { warmSession = nil }
        guard let warmSession, isFresh(warmSession.made) else { return nil }
        return warmSession.session
    }

    /// The instructions give today's date, so a session made much earlier
    /// would answer "what's the date?" wrong.
    private static func isFresh(_ made: Date) -> Bool {
        Date().timeIntervalSince(made) < 10 * 60
    }

    // MARK: - Sessions

    private static func makeSession(context: [ChatMessage]) async -> LanguageModelSession {
        // The conversation so far goes in as the session's history, so the
        // model sees the earlier turns as its own rather than as quoted text.
        let model = SystemLanguageModel.default
        let preamble = Transcript.Entry.instructions(
            Transcript.Instructions(segments: [text(instructions())], toolDefinitions: [])
        )
        var history: [Transcript.Entry] = context.map { message in
            switch message.role {
            case .user:  return .prompt(Transcript.Prompt(segments: [text(message.text)], contextOptions: ContextOptions()))
            case .model: return .response(Transcript.Response(segments: [text(message.text)]))
            }
        }
        // Oldest question-and-answer first, until it fits in half the window.
        // If the model can't count, go with the character cut.
        while !history.isEmpty,
              let tokens = try? await model.tokenCount(for: [preamble] + history),
              tokens > model.contextSize / 2 {
            history.removeFirst(min(2, history.count))
        }
        return LanguageModelSession(model: model, transcript: Transcript(entries: [preamble] + history))
    }

    private static func text(_ content: String) -> Transcript.Segment {
        .text(Transcript.TextSegment(content: content))
    }

    /// Short and plain: it's a small model, and every word here is paid for
    /// before the first word of the answer.
    private static func instructions() -> String {
        let today = Date().formatted(date: .complete, time: .omitted)
        return """
        You are Flyby, a quick-answer assistant on the user's Mac. Answer the question directly and concisely, leading with the answer itself. Format with Markdown: short paragraphs, lists or tables where they help, fenced code blocks for code.
        You run entirely on this Mac with no internet access. If a question depends on recent or live information — news, prices, scores, weather, schedules, anything after your training — say plainly that you can't check the web, and that Gemini or Google AI Mode in Flyby's provider menu can. Never make up facts, links or sources.
        Today is \(today).
        """
    }
}

/// A failure worded for someone who just asked a question.
struct AppleIntelligenceError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    init(explaining error: Error) {
        self.message = Self.explanation(for: error)
    }

    var errorDescription: String? { message }

    private static func explanation(for error: Error) -> String {
        if let error = error as? AppleIntelligenceError { return error.message }
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded:
                return "This chat has grown longer than Apple Intelligence can keep in mind. Start a new chat (⌘N) to carry on."
            case .guardrailViolation:
                return "Apple Intelligence's safety guardrails stopped this answer."
            case .refusal:
                return "Apple Intelligence declined to answer this."
            case .unsupportedLanguageOrLocale:
                return "Apple Intelligence doesn't support this language yet."
            case .rateLimited:
                return "Apple Intelligence is busy right now. Try again in a moment."
            case .timeout:
                return "Apple Intelligence took too long to answer. Try again."
            default:
                return error.localizedDescription
            }
        }
        if let error = error as? SystemLanguageModel.Error, case .assetsUnavailable = error {
            return AppleIntelligenceProvider.Readiness.preparing.problem ?? error.localizedDescription
        }
        return error.localizedDescription
    }
}
