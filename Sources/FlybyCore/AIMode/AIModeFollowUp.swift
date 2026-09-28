import Foundation

/// A follow-up asked of AI Mode when there's no live Google conversation to
/// ask it in.
///
/// The engine normally types a follow-up into AI Mode's own composer, so
/// Google keeps the thread. When that page is gone — a chat reopened from
/// Recent Chats, a relaunch, a page that failed or was left, an earlier turn
/// another provider answered — the only way to carry the conversation is in
/// the question itself. Without it, "what is its AnTuTu score?" is a question
/// about AnTuTu, and "the device" is whatever Google guesses.
public enum AIModeFollowUp {
    /// The query for a fresh AI Mode search that stands in for asking
    /// `question` after `turns` (oldest first):
    ///
    ///     Continuing our conversation. I asked earlier: "iPhone 16 Pro
    ///     performance". Your answer began: "The iPhone 16 Pro…". Now answer
    ///     my follow-up question: what is its AnTuTu score?
    ///
    /// The new question is last, whole and marked as the one to answer.
    /// Context fills what's left of `budget`: the earlier questions, newest
    /// first when they don't all fit, then the start of the latest answer.
    /// The budget counts UTF-8 bytes, because that's what the URL carries —
    /// so even percent-encoded it's a few kilobytes, well inside what Google
    /// takes, and short enough not to slow the answer down. With nothing
    /// earlier, or a question that fills the budget by itself, it's just the
    /// question.
    public static func query(
        _ question: String,
        after turns: [ConversationTurn],
        budget: Int = 1_200,
        maxQuestionLength: Int = 200,
        maxGistLength: Int = 280
    ) -> String {
        let question = collapsed(question)
        let asked = turns.map { collapsed($0.query) }.filter { !$0.isEmpty }
        guard !question.isEmpty, !asked.isEmpty else { return question }

        let intro = "Continuing our conversation. I asked earlier:"
        let ask = " Now answer my follow-up question: " + question
        var room = budget - intro.utf8.count - ask.utf8.count - 1

        var kept: [String] = []
        for query in asked.reversed() {
            let item = " \"" + clipped(query, to: maxQuestionLength) + "\""
            let cost = item.utf8.count + (kept.isEmpty ? 0 : 1)
            guard cost <= room else { break }
            room -= cost
            kept.insert(item, at: 0)
        }
        guard !kept.isEmpty else { return question }
        var context = intro + kept.joined(separator: ";") + "."

        // The start of the latest answer settles what "it" or "the device"
        // was when the questions alone don't: "which phone is fastest?".
        if let answer = turns.last(where: { !$0.answer.blocks.isEmpty })?.answer {
            let opening = " Your answer began: \""
            let gist = clipped(gistText(of: answer), to: min(maxGistLength, room - opening.utf8.count - 2))
            if gist.utf8.count >= 40 {
                context += opening + gist + "\"."
            }
        }
        return context + ask
    }

    /// The answer's prose as plain text: paragraphs and list items, inline
    /// markdown removed. Headings, tables and code make poor sentences.
    static func gistText(of answer: AnswerSnapshot) -> String {
        let prose = answer.blocks.compactMap { block -> String? in
            switch block {
            case .paragraph(let text), .quote(let text): return text
            case .listItem(let item):                   return item.text
            case .heading, .code, .table, .divider:     return nil
            }
        }
        return collapsed(prose.map(plain).joined(separator: " "))
    }

    /// Inline markdown to its text: links keep their words, emphasis and code
    /// marks go, escapes are undone.
    static func plain(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else { return markdown }
        return String(parsed.characters)
    }

    /// Runs of whitespace, newlines included, down to single spaces: the
    /// query is one line, and a question typed over several lines is still
    /// one question.
    static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// At most `limit` UTF-8 bytes. Anything cut is cut back to a word, where
    /// there's one to cut back to, and marked with "…".
    static func clipped(_ text: String, to limit: Int) -> String {
        guard text.utf8.count > limit else { return text }
        let ellipsis = "…"
        var left = limit - ellipsis.utf8.count
        var end = text.startIndex
        while end < text.endIndex, text[end].utf8.count <= left {
            left -= text[end].utf8.count
            end = text.index(after: end)
        }
        var cut = text[..<end]
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > cut.count / 2 {
            cut = cut[..<space]
        }
        while let last = cut.last, last.isWhitespace || last.isPunctuation {
            cut = cut.dropLast()
        }
        return cut.isEmpty ? "" : cut + ellipsis
    }
}
