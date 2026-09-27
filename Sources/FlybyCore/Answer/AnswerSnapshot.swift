import Foundation

/// Everything the result panel draws for one answer, at one moment.
///
/// Providers publish whole snapshots rather than deltas: AI Mode re-reads the
/// page on every mutation anyway, and re-parsing Gemini's accumulated markdown
/// is cheap at answer sizes. Replacing wholesale means no provider can leave
/// the view in a half-applied state.
public struct AnswerSnapshot: Sendable, Hashable, Codable {
    public var blocks: [AnswerBlock]
    public var sources: [WebSource]
    /// Suggested next questions, when the provider offers them.
    public var followUps: [String]
    /// The provider has finished; nothing more will stream in.
    public var isComplete: Bool

    public init(
        blocks: [AnswerBlock] = [],
        sources: [WebSource] = [],
        followUps: [String] = [],
        isComplete: Bool = false
    ) {
        self.blocks = blocks
        self.sources = sources
        self.followUps = followUps
        self.isComplete = isComplete
    }

    public static let empty = AnswerSnapshot()

    public var isEmpty: Bool { blocks.isEmpty }

    /// The whole answer as markdown-ish text, sources appended, for the
    /// clipboard.
    public var plainText: String {
        var parts = blocks.map(\.plainText)
        if !sources.isEmpty {
            parts.append("Sources:\n" + sources.map { "- \($0.title) — \($0.url.absoluteString)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}
