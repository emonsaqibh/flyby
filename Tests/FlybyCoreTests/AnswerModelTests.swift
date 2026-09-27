import Foundation
import Testing
@testable import FlybyCore

@Suite struct AnswerBlockCodingTests {
    @Test func decodesEveryBlockType() throws {
        let json = """
        [
          {"type": "heading", "level": 2, "text": "Kilimanjaro"},
          {"type": "paragraph", "text": "It is **5,895 m** tall."},
          {"type": "listItem", "ordered": true, "marker": "1.", "depth": 1, "text": "Uhuru Peak"},
          {"type": "code", "language": "", "text": "let x = 1"},
          {"type": "quote", "text": "Roof of Africa"},
          {"type": "table", "header": ["A", "B"], "rows": [["1", "2"]]},
          {"type": "divider"},
          {"type": "somethingNew", "text": "still shown"}
        ]
        """
        let blocks = try JSONDecoder().decode([AnswerBlock].self, from: Data(json.utf8))
        #expect(blocks == [
            .heading(level: 2, text: "Kilimanjaro"),
            .paragraph("It is **5,895 m** tall."),
            .listItem(.init(ordered: true, marker: "1.", depth: 1, text: "Uhuru Peak")),
            .code(language: nil, text: "let x = 1"),
            .quote("Roof of Africa"),
            .table(.init(header: ["A", "B"], rows: [["1", "2"]])),
            .divider,
            .paragraph("still shown"),
        ])
    }

    @Test func roundTrips() throws {
        let blocks: [AnswerBlock] = [
            .heading(level: 1, text: "T"),
            .listItem(.init(ordered: false, marker: "•", text: "a")),
            .code(language: "swift", text: "x"),
            .table(.init(header: ["h"], rows: [["r"]])),
            .divider,
        ]
        let data = try JSONEncoder().encode(blocks)
        #expect(try JSONDecoder().decode([AnswerBlock].self, from: data) == blocks)
    }
}

@Suite struct WebSourceTests {
    @Test func mergeKeepsFirstSeenOrderAndDropsDuplicates() {
        let a = WebSource(title: "A", url: URL(string: "https://a.example")!)
        let b = WebSource(title: "B", url: URL(string: "https://b.example")!)
        let c = WebSource(title: "C", url: URL(string: "https://c.example")!)
        var list = [a, b]
        list.merge([b, c, a])
        #expect(list.map(\.title) == ["A", "B", "C"])
    }

    @Test func displaySiteFallsBackToHostWithoutWWW() {
        #expect(WebSource(title: "x", url: URL(string: "https://www.bbc.co.uk/news")!).displaySite == "bbc.co.uk")
        #expect(WebSource(title: "x", url: URL(string: "https://bbc.co.uk")!, siteName: "BBC").displaySite == "BBC")
    }
}

@Suite struct MarkdownParserBaselineTests {
    @Test func splitsHeadingsParagraphsAndLists() {
        let blocks = MarkdownParser.parse("""
        # Title
        First line
        continues here.

        - one
        2. two
        """)
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line continues here."),
            .listItem(.init(ordered: false, marker: "•", text: "one")),
            .listItem(.init(ordered: true, marker: "2.", text: "two")),
        ])
    }
}
