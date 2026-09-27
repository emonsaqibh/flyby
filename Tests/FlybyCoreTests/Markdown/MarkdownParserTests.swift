import Foundation
import Testing
@testable import FlybyCore

private func bullet(_ text: String, depth: Int = 0) -> AnswerBlock {
    .listItem(.init(ordered: false, marker: "•", depth: depth, text: text))
}

private func numbered(_ marker: String, _ text: String, depth: Int = 0) -> AnswerBlock {
    .listItem(.init(ordered: true, marker: marker, depth: depth, text: text))
}

@Suite struct MarkdownHeadingTests {
    @Test func everyLevelUpToSixAndDeeperClamps() {
        let blocks = MarkdownParser.parse("""
        # One
        ## Two
        ### Three
        #### Four
        ##### Five
        ###### Six
        ####### Seven
        """)
        #expect(blocks == [
            .heading(level: 1, text: "One"),
            .heading(level: 2, text: "Two"),
            .heading(level: 3, text: "Three"),
            .heading(level: 4, text: "Four"),
            .heading(level: 5, text: "Five"),
            .heading(level: 6, text: "Six"),
            .heading(level: 6, text: "Seven"),
        ])
    }

    @Test func closingHashesGoButHashtagsStayText() {
        let blocks = MarkdownParser.parse("""
        ## Title ##
        # C#
        #hashtag is text
        """)
        #expect(blocks == [
            .heading(level: 2, text: "Title"),
            .heading(level: 1, text: "C#"),
            .paragraph("#hashtag is text"),
        ])
    }

    @Test func headingWithNoTextYetDrawsNothing() {
        #expect(MarkdownParser.parse("Intro\n#") == [.paragraph("Intro")])
        #expect(MarkdownParser.parse("## ") == [])
    }
}

@Suite struct MarkdownParagraphTests {
    @Test func linesJoinAndBlankLinesSplit() {
        let blocks = MarkdownParser.parse("One  \ntwo\n\n\nThree")
        #expect(blocks == [.paragraph("One two"), .paragraph("Three")])
    }

    @Test func windowsLineEndings() {
        let blocks = MarkdownParser.parse("# T\r\nline one\r\nline two\r\n\r\n- x")
        #expect(blocks == [
            .heading(level: 1, text: "T"),
            .paragraph("line one line two"),
            bullet("x"),
        ])
    }

    @Test func emptyInput() {
        #expect(MarkdownParser.parse("") == [])
        #expect(MarkdownParser.parse("\n\n  \n") == [])
    }
}

@Suite struct MarkdownListTests {
    @Test func everyBulletMarkerBecomesADot() {
        let blocks = MarkdownParser.parse("- a\n* b\n+ c\n• d")
        #expect(blocks == [bullet("a"), bullet("b"), bullet("c"), bullet("d")])
    }

    @Test func orderedMarkersKeepTheirNumber() {
        let blocks = MarkdownParser.parse("1. one\n2) two\n10. ten")
        #expect(blocks == [numbered("1.", "one"), numbered("2.", "two"), numbered("10.", "ten")])
    }

    @Test func twoSpaceNesting() {
        let blocks = MarkdownParser.parse("""
        - top
          - nested
            - deeper
          - back one
        - top again
        """)
        #expect(blocks == [
            bullet("top"),
            bullet("nested", depth: 1),
            bullet("deeper", depth: 2),
            bullet("back one", depth: 1),
            bullet("top again"),
        ])
    }

    @Test func geminiStyleFourSpaceNesting() {
        let blocks = MarkdownParser.parse("""
        *   **Mountains:** tall
            *   Everest
        *   **Rivers:** long
        """)
        #expect(blocks == [
            bullet("**Mountains:** tall"),
            bullet("Everest", depth: 1),
            bullet("**Rivers:** long"),
        ])
    }

    @Test func bulletsNestedUnderNumbers() {
        let blocks = MarkdownParser.parse("""
        1. First
           - detail
        2. Second
        """)
        #expect(blocks == [
            numbered("1.", "First"),
            bullet("detail", depth: 1),
            numbered("2.", "Second"),
        ])
    }

    @Test func aParagraphEndsTheList() {
        let blocks = MarkdownParser.parse("""
        - a
          - b

        Paragraph

          - c
        """)
        #expect(blocks == [
            bullet("a"),
            bullet("b", depth: 1),
            .paragraph("Paragraph"),
            bullet("c"),
        ])
    }

    @Test func wrappedItemTextContinuesTheItem() {
        let blocks = MarkdownParser.parse("""
        - first item
          wraps here
        - second
        """)
        #expect(blocks == [bullet("first item wraps here"), bullet("second")])
    }

    @Test func markerWithoutTextYetDoesNotGlueOntoTheParagraph() {
        #expect(MarkdownParser.parse("Intro text\n-") == [.paragraph("Intro text")])
        #expect(MarkdownParser.parse("Intro text\n*") == [.paragraph("Intro text")])
        #expect(MarkdownParser.parse("Intro text\n3.") == [.paragraph("Intro text")])
    }

    @Test func emphasisAtLineStartIsNotABullet() {
        #expect(MarkdownParser.parse("*italic* and **bold**") == [.paragraph("*italic* and **bold**")])
    }
}

@Suite struct MarkdownCodeTests {
    @Test func fencedBlockKeepsItsContentVerbatim() {
        let blocks = MarkdownParser.parse("""
        Intro
        ```swift
        let x = 1

        if x > 0 {
            print("# not a heading")
        }
        ```
        After
        """)
        #expect(blocks == [
            .paragraph("Intro"),
            .code(language: "swift", text: "let x = 1\n\nif x > 0 {\n    print(\"# not a heading\")\n}"),
            .paragraph("After"),
        ])
    }

    @Test func tildeFencesAndLongerClosingFences() {
        #expect(MarkdownParser.parse("~~~\na ``` b\n~~~~") == [.code(language: nil, text: "a ``` b")])
        // A tilde line doesn't close a backtick fence.
        #expect(MarkdownParser.parse("```\ncode\n~~~\n```") == [.code(language: nil, text: "code\n~~~")])
    }

    @Test func languageIsTheFirstWordOfTheInfoString() {
        #expect(MarkdownParser.parse("``` python title=\"x\"\npass\n```") == [.code(language: "python", text: "pass")])
    }

    @Test func unterminatedFenceIsCodeToTheEnd() {
        let blocks = MarkdownParser.parse("Here:\n```python\nprint(1)\n# still code\n\n")
        #expect(blocks == [
            .paragraph("Here:"),
            .code(language: "python", text: "print(1)\n# still code"),
        ])
    }

    @Test func halfArrivedClosingFenceIsNotShownAsCode() {
        #expect(MarkdownParser.parse("```js\nlet a = 1\n``") == [.code(language: "js", text: "let a = 1")])
    }

    @Test func fenceWithNoBodyYet() {
        #expect(MarkdownParser.parse("```ruby") == [.code(language: "ruby", text: "")])
    }

    @Test func fenceInsideAListItemLosesTheListIndent() {
        let blocks = MarkdownParser.parse("""
        - Run this:
          ```sh
          make build
            --verbose
          ```
        - Done
        """)
        #expect(blocks == [
            bullet("Run this:"),
            .code(language: "sh", text: "make build\n  --verbose"),
            bullet("Done"),
        ])
    }

    @Test func inlineTripleBackticksAreText() {
        #expect(MarkdownParser.parse("```inline``` code") == [.paragraph("```inline``` code")])
    }
}

@Suite struct MarkdownTableTests {
    @Test func headerAlignmentRowAndBody() {
        let blocks = MarkdownParser.parse("""
        | Peak | Height |
        | :--- | ---: |
        | Everest | 8,849 m |
        | K2 | 8,611 m |

        After
        """)
        #expect(blocks == [
            .table(.init(header: ["Peak", "Height"], rows: [["Everest", "8,849 m"], ["K2", "8,611 m"]])),
            .paragraph("After"),
        ])
    }

    @Test func outerPipesAreOptionalAndEscapedPipesAreText() {
        let blocks = MarkdownParser.parse("""
        Name | Note
        --- | ---
        a \\| b | `x`
        no pipe ends it
        """)
        #expect(blocks == [
            .table(.init(header: ["Name", "Note"], rows: [["a | b", "`x`"]])),
            .paragraph("no pipe ends it"),
        ])
    }

    @Test func raggedRowsArePaddedOrTrimmedToTheHeader() {
        let blocks = MarkdownParser.parse("| A | B |\n|---|---|\n| 1 |\n| 1 | 2 | 3 |")
        #expect(blocks == [.table(.init(header: ["A", "B"], rows: [["1", ""], ["1", "2"]]))])
    }

    @Test func streamingHeaderIsTextUntilTheDelimiterArrives() {
        #expect(MarkdownParser.parse("| A | B |") == [.paragraph("| A | B |")])
        #expect(MarkdownParser.parse("| A | B |\n|---|--") == [.table(.init(header: ["A", "B"], rows: []))])
    }

    @Test func pipeTextAboveARuleIsNotATable() {
        #expect(MarkdownParser.parse("a | b\n---") == [.paragraph("a | b"), .divider])
    }
}

@Suite struct MarkdownQuoteAndRuleTests {
    @Test func quoteLinesJoinAndABareMarkerSplits() {
        let blocks = MarkdownParser.parse("""
        > Roof of Africa,
        > said everyone.
        >
        > Second paragraph.
        >> nested
        """)
        #expect(blocks == [
            .quote("Roof of Africa, said everyone."),
            .quote("Second paragraph. nested"),
        ])
    }

    @Test func plainLineDirectlyBelowContinuesTheQuote() {
        #expect(MarkdownParser.parse("> quoted\ncontinues") == [.quote("quoted continues")])
        #expect(MarkdownParser.parse("> quoted\n\nseparate") == [.quote("quoted"), .paragraph("separate")])
    }

    @Test func quotedListItemsStayOnTheirOwnLines() {
        #expect(MarkdownParser.parse("> - a\n> - b") == [.quote("- a"), .quote("- b")])
    }

    @Test func rulesInEverySpelling() {
        let blocks = MarkdownParser.parse("---\n***\n___\n* * *\n- - -")
        #expect(blocks == [.divider, .divider, .divider, .divider, .divider])
    }

    @Test func twoDashesAreNotARule() {
        #expect(MarkdownParser.parse("--") == [.paragraph("--")])
    }
}

@Suite struct MarkdownStreamingTests {
    private static let answer = """
    ## Summary

    Mount Everest is the **highest** peak.

    * **Height:** 8,849 m
    * **Range:** Himalayas
        * Nepal/China border

    | Rank | Peak |
    |---|---|
    | 1 | Everest |

    ```text
    29,032 ft
    ```

    ---

    > Because it's there.
    """

    @Test func wholeAnswer() {
        #expect(MarkdownParser.parse(Self.answer) == [
            .heading(level: 2, text: "Summary"),
            .paragraph("Mount Everest is the **highest** peak."),
            bullet("**Height:** 8,849 m"),
            bullet("**Range:** Himalayas"),
            bullet("Nepal/China border", depth: 1),
            .table(.init(header: ["Rank", "Peak"], rows: [["1", "Everest"]])),
            .code(language: "text", text: "29,032 ft"),
            .divider,
            .quote("Because it's there."),
        ])
    }

    /// Gemini re-parses the accumulated text on every chunk, so any prefix at
    /// all has to parse — and a prefix that stops inside the fence must
    /// already show the code.
    @Test func everyPrefixParses() {
        let characters = Array(Self.answer)
        for length in 0...characters.count {
            let prefix = String(characters[0..<length])
            let blocks = MarkdownParser.parse(prefix)
            if prefix.hasSuffix("29,032") {
                #expect(blocks.last == .code(language: "text", text: "29,032"))
            }
        }
    }
}
