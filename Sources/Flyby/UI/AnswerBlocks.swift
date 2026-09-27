import SwiftUI
import AppKit
import FlybyCore

/// Renders an answer's blocks natively — the same renderer for Gemini's
/// markdown and AI Mode's extracted page, so the two read as one product.
///
/// `AttributedString(markdown:)` alone flattens lists and headings into one
/// run-on paragraph, so structure comes from `AnswerBlock` and markdown is only
/// used for inline styling (bold, italic, code, links) within each block.
struct AnswerBlocksView: View {
    let blocks: [AnswerBlock]
    /// More is on its way: new blocks fade in and a caret blinks after the
    /// last one.
    var isStreaming = false

    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Identified by position: a block that grows as it streams keeps
            // its identity (and doesn't re-animate), and only genuinely new
            // blocks get the insertion transition.
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                AnswerBlockView(block: block, accent: settings.accent.color)
                    .equatable()
                    .padding(.top, index == 0 ? 0 : spacing(before: index))
                    .transition(arrival)
            }

            if isStreaming {
                StreamingCaret(color: settings.accent.color)
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .animation(reduceMotion ? nil : Animation.easeOut(duration: 0.28), value: blocks.count)
        .animation(.easeOut(duration: 0.2), value: isStreaming)
    }

    private var arrival: AnyTransition {
        reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .offset(y: 6))
    }

    /// Rhythm: list items sit close, headings get air above and hold on to
    /// what follows them, everything else is a paragraph apart.
    private func spacing(before index: Int) -> CGFloat {
        switch (blocks[index - 1], blocks[index]) {
        case (.listItem, .listItem): return 6
        case (_, .heading):          return 22
        case (.heading, _):          return 8
        default:                     return 14
        }
    }
}

/// One block. Equatable so a streamed update only re-renders the blocks that
/// actually changed — usually just the last one.
struct AnswerBlockView: View, Equatable {
    let block: AnswerBlock
    let accent: Color

    @ViewBuilder
    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(InlineMarkdown.render(text, accent: accent))
                .font(Self.headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            Text(InlineMarkdown.render(text, accent: accent))
                .font(.system(size: 14))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let item):
            ListItemView(item: item, accent: accent)

        case .code(let language, let text):
            CodeBlockView(language: language, code: text)

        case .quote(let text):
            // The bar is an overlay rather than a sibling so it always spans
            // exactly the text's height, however many lines that wraps to.
            Text(InlineMarkdown.render(text, accent: accent))
                .font(.system(size: 14))
                .italic()
                .lineSpacing(4)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(accent.opacity(0.7))
                        .frame(width: 3)
                }

        case .table(let table):
            TableBlockView(table: table, accent: accent)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 20, weight: .bold)
        case 2:  return .system(size: 17, weight: .semibold)
        case 3:  return .system(size: 15, weight: .semibold)
        default: return .system(size: 14, weight: .semibold)
        }
    }
}

// MARK: - Inline markdown

enum InlineMarkdown {
    /// Bold, italic, `code` and links, with links in the accent colour and
    /// code spans on a faint well so they read as literal text.
    ///
    /// Attributes are set by explicit key: with both SwiftUI and AppKit in
    /// scope, `.foregroundColor` and `.backgroundColor` exist in two attribute
    /// scopes and the shorthand is ambiguous.
    static func render(_ text: String, accent: Color) -> AttributedString {
        var result = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        var links: [Range<AttributedString.Index>] = []
        var code: [Range<AttributedString.Index>] = []
        for run in result.runs {
            if run.link != nil { links.append(run.range) }
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                code.append(run.range)
            }
        }
        for range in links {
            result[range][AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = accent
        }
        for range in code {
            result[range][AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Color.primary.opacity(0.08)
        }
        return result
    }
}

// MARK: - Lists

/// A hanging indent: the marker sits in a fixed-width gutter so wrapped lines
/// line up with the first line's text, not with the bullet.
private struct ListItemView: View {
    let item: AnswerBlock.ListItem
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .font(item.ordered ? Font.system(size: 14).monospacedDigit() : Font.system(size: 14, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: item.ordered ? 26 : 12, alignment: .trailing)
                .accessibilityHidden(!item.ordered)

            Text(InlineMarkdown.render(item.text, accent: accent))
                .font(.system(size: 14))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CGFloat(min(item.depth, 6)) * 20)
    }

    /// Nested bullets change shape, like every word processor's, so depth
    /// reads even where the indent is subtle.
    private var marker: String {
        guard !item.ordered, item.marker == "•" else { return item.marker }
        switch item.depth {
        case 0:  return "•"
        case 1:  return "◦"
        default: return "▪︎"
        }
    }
}

// MARK: - Code

/// Monospaced on a rounded well, scrolling sideways rather than wrapping —
/// wrapped code is wrong code — with a copy button, because code in an answer
/// is there to be pasted.
private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    withAnimation(.easeOut(duration: 0.15)) { copied = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation(.easeOut(duration: 0.2)) { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineSpacing(2)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - Tables

/// A real grid with an emphasised header row and hairline rules.
///
/// Up to four columns fit the reading column and wrap within it, which is
/// how nearly every answer's table is shaped. Wider tables keep a readable
/// column width and scroll sideways instead of crushing every cell to a
/// sliver.
private struct TableBlockView: View {
    let table: AnswerBlock.Table
    let accent: Color
    @Environment(\.displayScale) private var displayScale

    private static let fittedColumnLimit = 4
    private static let scrollingCellWidth: CGFloat = 180

    var body: some View {
        Group {
            if columnCount <= Self.fittedColumnLimit {
                grid(cellWidth: nil)
            } else {
                ScrollView(.horizontal) {
                    grid(cellWidth: Self.scrollingCellWidth)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var columnCount: Int {
        max(table.header.count, table.rows.map(\.count).max() ?? 0)
    }

    private func grid(cellWidth: CGFloat?) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            if !table.header.isEmpty {
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(value(in: table.header, at: column), width: cellWidth, isHeader: true)
                    }
                }
                rule(opacity: 0.18)
            }

            ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { column in
                        cell(value(in: row, at: column), width: cellWidth, isHeader: false)
                    }
                }
                if index < table.rows.count - 1 {
                    rule(opacity: 0.08)
                }
            }
        }
    }

    private func value(in row: [String], at column: Int) -> String {
        column < row.count ? row[column] : ""
    }

    private func cell(_ text: String, width: CGFloat?, isHeader: Bool) -> some View {
        let font: Font = isHeader ? .system(size: 13, weight: .semibold) : .system(size: 13)
        return Text(InlineMarkdown.render(text, accent: accent))
            .font(font)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? CGFloat.infinity : nil, maxHeight: .infinity, alignment: .topLeading)
            .background(isHeader ? Color.primary.opacity(0.05) : Color.clear)
    }

    /// A hairline across every column. Unsized horizontally, so it spans the
    /// grid without asking the grid to grow to fit it.
    private func rule(opacity: Double) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(opacity))
            .frame(height: 1 / max(displayScale, 1))
            .gridCellUnsizedAxes(.horizontal)
    }
}

// MARK: - Streaming

/// A blinking bar after the last block while the answer is still arriving —
/// the same promise a text caret makes. Steady under Reduce Motion.
private struct StreamingCaret: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1.25, style: .continuous)
            .fill(color)
            .frame(width: 2.5, height: 16)
            .opacity(dimmed ? 0.15 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    dimmed = true
                }
            }
            .accessibilityLabel("Answer still arriving")
    }
}
