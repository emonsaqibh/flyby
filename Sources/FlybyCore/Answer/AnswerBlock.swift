import Foundation

/// One block of a rendered answer, independent of which provider produced it.
///
/// Gemini returns markdown, which `MarkdownParser` splits into these. Google AI
/// Mode returns a live DOM, which the in-page extractor walks and posts back as
/// JSON in exactly this shape. Both land in the same native renderer, so the
/// two providers look like one product.
///
/// Text payloads are *inline markdown* — bold, italic, `code` and
/// `[links](url)` — never block syntax. Block structure lives in the enum.
public enum AnswerBlock: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(ListItem)
    case code(language: String?, text: String)
    case quote(String)
    case table(Table)
    case divider

    public struct ListItem: Sendable, Hashable, Codable {
        public var ordered: Bool
        /// What to draw in the gutter: "•" for unordered, "3." for ordered.
        public var marker: String
        /// 0 for top level, 1 for a list nested inside it, and so on.
        public var depth: Int
        public var text: String

        public init(ordered: Bool, marker: String, depth: Int = 0, text: String) {
            self.ordered = ordered
            self.marker = marker
            self.depth = depth
            self.text = text
        }
    }

    public struct Table: Sendable, Hashable, Codable {
        public var header: [String]
        public var rows: [[String]]

        public init(header: [String], rows: [[String]]) {
            self.header = header
            self.rows = rows
        }
    }
}

// MARK: - Codable

/// Wire format, shared with the AI Mode extractor script:
///
///     {"type": "heading", "level": 2, "text": "…"}
///     {"type": "paragraph", "text": "…"}
///     {"type": "listItem", "ordered": false, "marker": "•", "depth": 0, "text": "…"}
///     {"type": "code", "language": "swift", "text": "…"}
///     {"type": "quote", "text": "…"}
///     {"type": "table", "header": ["…"], "rows": [["…"]]}
///     {"type": "divider"}
///
/// Unknown types decode as an empty paragraph rather than failing the whole
/// snapshot — Google changing one element shouldn't blank the answer.
extension AnswerBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, level, text, ordered, marker, depth, language, header, rows
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "paragraph"
        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""

        switch type {
        case "heading":
            let level = try c.decodeIfPresent(Int.self, forKey: .level) ?? 2
            self = .heading(level: min(max(level, 1), 6), text: text)
        case "listItem":
            let ordered = try c.decodeIfPresent(Bool.self, forKey: .ordered) ?? false
            self = .listItem(ListItem(
                ordered: ordered,
                marker: try c.decodeIfPresent(String.self, forKey: .marker) ?? (ordered ? "1." : "•"),
                depth: max(0, try c.decodeIfPresent(Int.self, forKey: .depth) ?? 0),
                text: text
            ))
        case "code":
            let language = try c.decodeIfPresent(String.self, forKey: .language)
            self = .code(language: language?.isEmpty == true ? nil : language, text: text)
        case "quote":
            self = .quote(text)
        case "table":
            self = .table(Table(
                header: try c.decodeIfPresent([String].self, forKey: .header) ?? [],
                rows: try c.decodeIfPresent([[String]].self, forKey: .rows) ?? []
            ))
        case "divider":
            self = .divider
        default:
            self = .paragraph(text)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .heading(let level, let text):
            try c.encode("heading", forKey: .type)
            try c.encode(level, forKey: .level)
            try c.encode(text, forKey: .text)
        case .paragraph(let text):
            try c.encode("paragraph", forKey: .type)
            try c.encode(text, forKey: .text)
        case .listItem(let item):
            try c.encode("listItem", forKey: .type)
            try c.encode(item.ordered, forKey: .ordered)
            try c.encode(item.marker, forKey: .marker)
            try c.encode(item.depth, forKey: .depth)
            try c.encode(item.text, forKey: .text)
        case .code(let language, let text):
            try c.encode("code", forKey: .type)
            try c.encodeIfPresent(language, forKey: .language)
            try c.encode(text, forKey: .text)
        case .quote(let text):
            try c.encode("quote", forKey: .type)
            try c.encode(text, forKey: .text)
        case .table(let table):
            try c.encode("table", forKey: .type)
            try c.encode(table.header, forKey: .header)
            try c.encode(table.rows, forKey: .rows)
        case .divider:
            try c.encode("divider", forKey: .type)
        }
    }
}

extension AnswerBlock {
    /// Plain-text rendering, for "Copy answer". Inline markdown is kept as-is:
    /// it pastes sensibly into chat apps and notes, which is where answers go.
    public var plainText: String {
        switch self {
        case .heading(let level, let text):
            return String(repeating: "#", count: level) + " " + text
        case .paragraph(let text), .quote(let text):
            return text
        case .listItem(let item):
            return String(repeating: "  ", count: item.depth) + item.marker + " " + item.text
        case .code(let language, let text):
            return "```" + (language ?? "") + "\n" + text + "\n```"
        case .table(let table):
            let lines = [table.header] + table.rows
            return lines.map { "| " + $0.joined(separator: " | ") + " |" }.joined(separator: "\n")
        case .divider:
            return "---"
        }
    }
}
