import Foundation
import Testing
@testable import FlybyCore

private func turn(_ query: String, answer blocks: [AnswerBlock] = [], provider: String = "webview") -> ConversationTurn {
    ConversationTurn(
        query: query,
        provider: provider,
        answer: AnswerSnapshot(blocks: blocks, sources: [], isComplete: true)
    )
}

@Suite struct AIModeFollowUpTests {
    private let iPhone = turn("iPhone 16 Pro performance", answer: [
        .heading(level: 2, text: "Benchmarks"),
        .paragraph("The **Apple iPhone 16 Pro** delivers top-tier performance, driven by the [A18 Pro](https://www.apple.com/a18) chip."),
        .table(.init(header: ["Test", "Score"], rows: [["Geekbench", "3,400"]])),
        .listItem(.init(ordered: false, marker: "•", depth: 0, text: "Built on a `3nm` process")),
    ])

    @Test func aFirstQuestionIsLeftAlone() {
        #expect(AIModeFollowUp.query("  what is AnTuTu?\n", after: []) == "what is AnTuTu?")
    }

    @Test func carriesTheEarlierQuestionAndTheStartOfItsAnswer() {
        let query = AIModeFollowUp.query("what is its AnTuTu score?", after: [iPhone])
        #expect(query == """
            Continuing our conversation. I asked earlier: "iPhone 16 Pro performance". Your answer began: \
            "The Apple iPhone 16 Pro delivers top-tier performance, driven by the A18 Pro chip. Built on a 3nm process". \
            Now answer my follow-up question: what is its AnTuTu score?
            """)
    }

    @Test func theNewQuestionIsLastAndWhole() {
        let question = "and what is the score of the device, in " + String(repeating: "great ", count: 60) + "detail?"
        let query = AIModeFollowUp.query(question, after: [iPhone, turn("how about the camera?")])
        #expect(query.hasSuffix("Now answer my follow-up question: " + AIModeFollowUp.collapsed(question)))
    }

    @Test func earlierQuestionsStayInOrder() {
        let query = AIModeFollowUp.query("which is cheaper?", after: [turn("Pixel 10 price"), turn("and the iPhone 17?")])
        #expect(query.hasPrefix(#"Continuing our conversation. I asked earlier: "Pixel 10 price"; "and the iPhone 17?"."#))
    }

    @Test func staysWithinTheBudgetDroppingTheOldestQuestionsFirst() {
        let turns = (1...40).map { turn("question number \($0) about " + String(repeating: "phones ", count: 20)) }
        let query = AIModeFollowUp.query("so which one?", after: turns, budget: 600)
        #expect(query.utf8.count <= 600)
        #expect(query.contains("question number 40"))
        #expect(!query.contains("question number 1 "))
        #expect(query.hasSuffix("so which one?"))
    }

    @Test func budgetCountsBytesNotCharacters() {
        let japanese = String(repeating: "東京の天気はどうですか", count: 30)
        let query = AIModeFollowUp.query("明日は?", after: [turn(japanese, answer: [.paragraph(japanese)])], budget: 500)
        #expect(query.utf8.count <= 500)
        #expect(query.hasSuffix("明日は?"))
    }

    @Test func theURLStaysWellInsideGooglesLimits() {
        let long = String(repeating: "ü€ word ", count: 400)
        let turns = (1...20).map { _ in turn(long, answer: [.paragraph(long)]) }
        let query = AIModeFollowUp.query("and then?", after: turns)
        let url = AIModeQuery.url(for: query, languageCode: "de")
        #expect(query.utf8.count <= 1_200)
        #expect(url.absoluteString.utf8.count < 4_000)
    }

    @Test func longEarlierQuestionsAreClipped() {
        let query = AIModeFollowUp.query("why?", after: [turn(String(repeating: "word ", count: 100))], maxQuestionLength: 50)
        #expect(query.contains(#""word word word word word word word word word…""#))
    }

    @Test func aQuestionThatFillsTheBudgetGoesAlone() {
        let question = String(repeating: "long question ", count: 100)
        let query = AIModeFollowUp.query(question, after: [iPhone], budget: 300)
        #expect(query == AIModeFollowUp.collapsed(question))
    }

    @Test func noGistFromAnAnswerlessTurn() {
        let query = AIModeFollowUp.query("try again?", after: [turn("iPhone 16 Pro performance")])
        #expect(query == #"Continuing our conversation. I asked earlier: "iPhone 16 Pro performance". Now answer my follow-up question: try again?"#)
    }

    @Test func theGistComesFromTheLatestAnswer() {
        let failed = turn("and its AnTuTu score?")
        let query = AIModeFollowUp.query("the device's weight?", after: [iPhone, failed])
        #expect(query.contains(#"I asked earlier: "iPhone 16 Pro performance"; "and its AnTuTu score?"."#))
        #expect(query.contains("Your answer began: \"The Apple iPhone 16 Pro"))
    }

    @Test func questionsTypedOverSeveralLinesAreOneLine() {
        let query = AIModeFollowUp.query("what about\n\nbattery   life?", after: [turn("iPhone\n16 Pro")])
        #expect(!query.contains("\n"))
        #expect(query.contains(#""iPhone 16 Pro""#))
        #expect(query.hasSuffix("what about battery life?"))
    }

    @Test func gistIsProseWithoutMarkdown() {
        let gist = AIModeFollowUp.gistText(of: iPhone.answer)
        #expect(gist == "The Apple iPhone 16 Pro delivers top-tier performance, driven by the A18 Pro chip. Built on a 3nm process")
    }

    @Test func clipsToAWordWithinTheLimit() {
        #expect(AIModeFollowUp.clipped("short", to: 10) == "short")
        let clipped = AIModeFollowUp.clipped("The quick brown fox jumps over the lazy dog.", to: 24)
        #expect(clipped == "The quick brown fox…")
        #expect(clipped.utf8.count <= 24)
        #expect(AIModeFollowUp.clipped("Supercalifragilistic", to: 10).utf8.count <= 10)
        #expect(AIModeFollowUp.clipped("東京東京東京", to: 10) == "東京…")
    }
}
