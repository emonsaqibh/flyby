import Foundation

/// Splits provider markdown into `AnswerBlock`s.
///
/// Block structure only: inline syntax (bold, italic, code spans, links) is
/// left in each block's text for the renderer, which hands it to
/// `AttributedString(markdown:)` with inline-only parsing.
///
/// Built for streamed input. Gemini sends markdown a few tokens at a time and
/// the whole accumulated text is re-parsed on every update, so every *prefix*
/// of a document has to parse into something sensible: an unterminated code
/// fence is code to the end, a half-arrived closing fence isn't shown as code,
/// and a list marker whose text hasn't arrived yet is nothing rather than a
/// stray "-" glued onto the paragraph above it.
///
/// Deliberately not CommonMark. It covers what language models actually
/// write — ATX headings, paragraphs, nested lists, fences, GitHub tables,
/// quotes and rules — and settles ambiguities the way that reads best in a
/// small panel rather than the way the spec does.
public enum MarkdownParser {
    public static func parse(_ text: String) -> [AnswerBlock] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(Line.init)
        var parser = BlockParser(lines: lines)
        return parser.run()
    }
}

// MARK: - Lines

private struct Line {
    /// As written, minus the line break.
    let raw: String
    /// Leading whitespace in columns, a tab counting to the next multiple of 4.
    let indent: Int
    /// Without leading or trailing whitespace.
    let content: String

    var isBlank: Bool { content.isEmpty }

    init(_ raw: Substring) {
        var width = 0
        for character in raw {
            if character == " " {
                width += 1
            } else if character == "\t" {
                width += 4 - width % 4
            } else {
                break
            }
        }
        self.raw = String(raw)
        self.indent = width
        self.content = raw.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Block parser

private struct BlockParser {
    let lines: [Line]
    private var index = 0
    private var blocks: [AnswerBlock] = []
    /// Lines of the paragraph being gathered, each already trimmed.
    private var paragraph: [String] = []
    /// Indent of each open list level, outermost first. Its count is the depth
    /// of the next item at the innermost indent.
    private var listIndents: [Int] = []
    /// The last block is a list item or quote that a plain line directly
    /// beneath it (no blank line between) continues, rather than starting a
    /// paragraph of its own — how a model wraps a long bullet.
    private var lastBlockContinues = false

    init(lines: [Line]) {
        self.lines = lines
    }

    mutating func run() -> [AnswerBlock] {
        while index < lines.count {
            let line = lines[index]

            if line.isBlank {
                flushParagraph()
                lastBlockContinues = false
                index += 1
                continue
            }

            if let fence = Fence(line) {
                flushParagraph()
                leaveListIfOutdented(line)
                readCode(fence)
                continue
            }

            if Self.isRule(line.content) {
                flushParagraph()
                listIndents.removeAll()
                append(.divider, continuable: false)
                index += 1
                continue
            }

            if let heading = Self.heading(line.content) {
                flushParagraph()
                listIndents.removeAll()
                // A bare "#" is a heading whose text hasn't streamed in yet.
                if !heading.text.isEmpty {
                    append(.heading(level: heading.level, text: heading.text), continuable: false)
                }
                lastBlockContinues = false
                index += 1
                continue
            }

            if let quoted = Self.quoteContent(line.content) {
                flushParagraph()
                leaveListIfOutdented(line)
                appendQuote(quoted)
                index += 1
                continue
            }

            if let item = Self.listItem(line.content) {
                flushParagraph()
                if item.text.isEmpty {
                    // Marker streamed, text not yet: ends the paragraph above
                    // but draws nothing.
                    lastBlockContinues = false
                } else {
                    let depth = depthForItem(indentedBy: line.indent)
                    append(
                        .listItem(.init(ordered: item.ordered, marker: item.marker, depth: depth, text: item.text)),
                        continuable: true
                    )
                }
                index += 1
                continue
            }

            if line.content.contains("|"),
               index + 1 < lines.count,
               Self.isDelimiterRow(lines[index + 1].content) {
                flushParagraph()
                leaveListIfOutdented(line)
                readTable(header: Self.cells(of: line.content))
                continue
            }

            if !continueLastBlock(with: line.content) {
                if paragraph.isEmpty { leaveListIfOutdented(line) }
                paragraph.append(line.content)
            }
            index += 1
        }

        flushParagraph()
        return blocks
    }

    // MARK: Building

    private mutating func append(_ block: AnswerBlock, continuable: Bool) {
        blocks.append(block)
        lastBlockContinues = continuable
    }

    private mutating func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        let joined = paragraph.joined(separator: " ")
        paragraph.removeAll()
        if !joined.isEmpty { append(.paragraph(joined), continuable: false) }
    }

    /// Lazy continuation: a plain line straight after a list item or quote
    /// belongs to it.
    private mutating func continueLastBlock(with text: String) -> Bool {
        guard paragraph.isEmpty, lastBlockContinues, let last = blocks.last else { return false }
        switch last {
        case .listItem(var item):
            item.text += " " + text
            blocks[blocks.count - 1] = .listItem(item)
            return true
        case .quote(let quoted):
            blocks[blocks.count - 1] = .quote(quoted + " " + text)
            return true
        default:
            return false
        }
    }

    /// Consecutive quote lines are one quote; a bare ">" splits it into two,
    /// and so does a quoted list item or heading, which would read as run-on
    /// text if joined.
    private mutating func appendQuote(_ quoted: String) {
        guard !quoted.isEmpty else {
            lastBlockContinues = false
            return
        }
        let startsOwnLine = Self.listItem(quoted) != nil || Self.heading(quoted) != nil
        if lastBlockContinues, !startsOwnLine, case .quote(let previous)? = blocks.last {
            blocks[blocks.count - 1] = .quote(previous + " " + quoted)
        } else {
            append(.quote(quoted), continuable: true)
        }
    }

    // MARK: Lists

    /// Nesting comes from indentation relative to the items above: two or more
    /// columns deeper than the current level opens a new one, and anything
    /// shallower closes levels until it fits. Relative rather than absolute,
    /// because models indent nested lists by two, three or four spaces
    /// depending on the marker width and their mood.
    private mutating func depthForItem(indentedBy indent: Int) -> Int {
        while let top = listIndents.last, indent < top - 1 {
            listIndents.removeLast()
        }
        if let top = listIndents.last {
            if indent >= top + 2 { listIndents.append(indent) }
        } else {
            listIndents.append(indent)
        }
        return listIndents.count - 1
    }

    /// Something at or left of the list's own margin ends the list, so the
    /// next list starts from depth 0 again. Anything indented further is still
    /// inside an item — a code block under a bullet, say.
    private mutating func leaveListIfOutdented(_ line: Line) {
        if let first = listIndents.first, line.indent <= first {
            listIndents.removeAll()
        }
    }

    // MARK: Code

    private mutating func readCode(_ fence: Fence) {
        index += 1
        var body: [String] = []
        var closed = false

        while index < lines.count {
            let line = lines[index]
            index += 1
            if fence.isClosed(by: line) {
                closed = true
                break
            }
            body.append(Self.removingIndent(fence.indent, from: line.raw))
        }

        if !closed {
            // The stream stopped mid-block. A run of fence characters shorter
            // than the fence is the closing fence arriving, not code, and the
            // blank lines the stream happens to end on aren't code either.
            if let last = body.last {
                let trimmed = last.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == fence.character }) {
                    body.removeLast()
                }
            }
            while let last = body.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                body.removeLast()
            }
        }

        append(.code(language: fence.language, text: body.joined(separator: "\n")), continuable: false)
    }

    /// A fence indented under a list item indents its whole body the same
    /// amount; that indentation is the list's, not the code's.
    private static func removingIndent(_ columns: Int, from raw: String) -> String {
        var removed = 0
        var start = raw.startIndex
        while start < raw.endIndex, removed < columns {
            let character = raw[start]
            if character == " " {
                removed += 1
            } else if character == "\t" {
                removed += 4 - removed % 4
            } else {
                break
            }
            start = raw.index(after: start)
        }
        return String(raw[start...])
    }

    // MARK: Tables

    private mutating func readTable(header: [String]) {
        // Skip the header and the delimiter row.
        index += 2
        var rows: [[String]] = []

        while index < lines.count {
            let line = lines[index]
            guard !line.isBlank,
                  line.content.contains("|"),
                  Fence(line) == nil,
                  Self.heading(line.content) == nil,
                  Self.quoteContent(line.content) == nil
            else { break }

            // Ragged rows are normal mid-stream, and models miscount columns
            // anyway: pad or trim to the header so the grid stays a grid.
            var row = Self.cells(of: line.content)
            if row.count < header.count {
                row += Array(repeating: "", count: header.count - row.count)
            } else if row.count > header.count {
                row = Array(row.prefix(header.count))
            }
            rows.append(row)
            index += 1
        }

        append(.table(.init(header: header, rows: rows)), continuable: false)
    }

    /// Splits a table row on unescaped pipes. The outer pipes are optional,
    /// `\|` is a literal pipe, and any other escape is left for the inline
    /// renderer.
    static func cells(of content: String) -> [String] {
        var row = Substring(content)
        if row.hasPrefix("|") { row = row.dropFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row = row.dropLast() }

        var cells: [String] = []
        var current = ""
        var escaping = false
        for character in row {
            if escaping {
                if character != "|" { current.append("\\") }
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaping { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    /// `| --- | :-: |` and friends. It has to contain a pipe: a bare `---`
    /// under a line that happens to contain one is a rule, not a table.
    static func isDelimiterRow(_ content: String) -> Bool {
        guard content.contains("|"), content.contains("-") else { return false }
        return cells(of: content).allSatisfy { cell in
            var dashes = Substring(cell)
            if dashes.hasPrefix(":") { dashes = dashes.dropFirst() }
            if dashes.hasSuffix(":") { dashes = dashes.dropLast() }
            return !dashes.isEmpty && dashes.allSatisfy { $0 == "-" }
        }
    }

    // MARK: Line classification

    /// Three or more of the same `-`, `*` or `_`, optionally spaced out.
    static func isRule(_ content: String) -> Bool {
        guard let first = content.first, first == "-" || first == "*" || first == "_" else { return false }
        var count = 0
        for character in content {
            if character == first {
                count += 1
            } else if character != " " && character != "\t" {
                return false
            }
        }
        return count >= 3
    }

    /// `#` to `######` and a space, with an optional closing run of `#`s.
    /// Deeper than six clamps to six rather than falling back to text — a
    /// model that wrote seven hashes still meant a heading.
    static func heading(_ content: String) -> (level: Int, text: String)? {
        let hashes = content.prefix { $0 == "#" }.count
        guard hashes > 0 else { return nil }
        let rest = content.dropFirst(hashes)
        // "#hashtag" and "#1" are text.
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }

        var text = rest.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("#") {
            if let lastOther = text.lastIndex(where: { $0 != "#" }) {
                // Only a run set off by a space closes: "# C#" keeps its "#".
                if text[lastOther] == " " || text[lastOther] == "\t" {
                    text = text[..<lastOther].trimmingCharacters(in: .whitespaces)
                }
            } else {
                text = ""
            }
        }
        return (min(max(hashes, 1), 6), text)
    }

    /// The text of a `>` line, with every level of `>` stripped — nested
    /// quotes flatten into one.
    static func quoteContent(_ content: String) -> String? {
        guard content.hasPrefix(">") else { return nil }
        var rest = Substring(content)
        while rest.first == ">" {
            rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    struct ListItem {
        let ordered: Bool
        let marker: String
        let text: String
    }

    /// `-`, `*`, `+` or `•` bullets, and `1.` or `1)` numbers, each followed by
    /// whitespace. A marker alone on its line is an item with no text yet.
    static func listItem(_ content: String) -> ListItem? {
        guard let first = content.first else { return nil }

        if first == "-" || first == "*" || first == "+" || first == "•" {
            let rest = content.dropFirst()
            if rest.isEmpty { return ListItem(ordered: false, marker: "•", text: "") }
            guard rest.first == " " || rest.first == "\t" else { return nil }
            return ListItem(ordered: false, marker: "•", text: rest.trimmingCharacters(in: .whitespaces))
        }

        let digits = content.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = content.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        let body = rest.dropFirst()
        let marker = "\(digits)."
        if body.isEmpty { return ListItem(ordered: true, marker: marker, text: "") }
        guard body.first == " " || body.first == "\t" else { return nil }
        return ListItem(ordered: true, marker: marker, text: body.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - Fences

private struct Fence: Equatable {
    let character: Character
    let length: Int
    let indent: Int
    let language: String?

    /// Three or more backticks or tildes, then an optional info string whose
    /// first word is the language. A backtick fence's info string can't
    /// contain a backtick — "```x```" on one line is inline code, not a fence.
    init?(_ line: Line) {
        guard let first = line.content.first, first == "`" || first == "~" else { return nil }
        let run = line.content.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        let info = line.content.dropFirst(run).trimmingCharacters(in: .whitespaces)
        if first == "`", info.contains("`") { return nil }

        character = first
        length = run
        indent = line.indent
        let word = info.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init)
        language = (word?.isEmpty ?? true) ? nil : word
    }

    /// The same character, at least as many of it, and nothing else.
    func isClosed(by line: Line) -> Bool {
        line.content.count >= length && line.content.allSatisfy { $0 == character }
    }
}
