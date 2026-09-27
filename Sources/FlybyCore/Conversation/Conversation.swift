import Foundation

/// One question and what came back for it.
public struct ConversationTurn: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var query: String
    /// The provider's stored name (`ProviderKind.rawValue` in the app, which
    /// owns that enum).
    public var provider: String
    public var answer: AnswerSnapshot
    /// Why the turn ended without an answer, when it did.
    public var failure: String?
    public var date: Date

    public init(
        id: UUID = UUID(),
        query: String,
        provider: String,
        answer: AnswerSnapshot,
        failure: String? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.provider = provider
        self.answer = answer
        self.failure = failure
        self.date = date
    }
}

/// A chat: a first question and the follow-ups asked after it, oldest first.
public struct Conversation: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var turns: [ConversationTurn]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        turns: [ConversationTurn],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.turns = turns
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The question that started it.
    public var title: String { turns.first?.query ?? "" }

    public var summary: ConversationSummary {
        ConversationSummary(
            id: id,
            title: title,
            provider: turns.last?.provider ?? "",
            turnCount: turns.count,
            updatedAt: updatedAt
        )
    }
}

/// What the history list shows for a conversation — enough to draw a row
/// without reading the conversation itself.
public struct ConversationSummary: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var title: String
    /// The provider of the latest turn.
    public var provider: String
    public var turnCount: Int
    public var updatedAt: Date

    public init(id: UUID, title: String, provider: String, turnCount: Int, updatedAt: Date) {
        self.id = id
        self.title = title
        self.provider = provider
        self.turnCount = turnCount
        self.updatedAt = updatedAt
    }
}

/// A message in the context sent with a follow-up question.
public struct ChatMessage: Sendable, Hashable {
    public enum Role: String, Sendable {
        case user
        /// Gemini's name for the assistant's side.
        case model
    }

    public var role: Role
    public var text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// The earlier turns a follow-up is asked in the context of.
public enum ChatContext {
    /// Past turns as alternating user and model messages, oldest first.
    ///
    /// Only turns that got an answer count: a question with no reply gives
    /// the model nothing to build on. Each answer is capped, and the oldest
    /// turns go first when the whole thing would be too long — a follow-up is
    /// nearly always about the last answer or two, and every character is
    /// paid for in latency before the first word comes back.
    public static func messages(
        from turns: [ConversationTurn],
        maxTurns: Int = 8,
        maxAnswerCharacters: Int = 4_000,
        maxTotalCharacters: Int = 24_000
    ) -> [ChatMessage] {
        var pairs: [(question: String, answer: String)] = turns.compactMap { turn in
            let answer = turn.answer.bodyText
            guard !answer.isEmpty else { return nil }
            return (turn.query, truncated(answer, to: maxAnswerCharacters))
        }
        if pairs.count > maxTurns { pairs.removeFirst(pairs.count - maxTurns) }
        while pairs.count > 1,
              pairs.reduce(0, { $0 + $1.question.count + $1.answer.count }) > maxTotalCharacters {
            pairs.removeFirst()
        }
        return pairs.flatMap { pair in
            [ChatMessage(role: .user, text: pair.question), ChatMessage(role: .model, text: pair.answer)]
        }
    }

    private static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }
}

extension AnswerSnapshot {
    /// The answer's text without the sources list — what a follow-up needs
    /// to know was said.
    public var bodyText: String {
        blocks.map(\.plainText).joined(separator: "\n\n")
    }
}
