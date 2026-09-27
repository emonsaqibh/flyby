import Foundation
import Testing
@testable import FlybyCore

/// Messages the extractor actually produced, captured by running
/// `AIModeScript.extractor` in Chromium against saved pages:
///
/// - `realAnswer`: a live AI Mode answer captured 2026-09-16 (paragraphs,
///   headings, a list with spacer items, a table, citation chips including a
///   repeated source and a hidden icon-only chip, the completion footer).
/// - `thread`: a two-turn page built around that answer, with side cards, a
///   signed-in account button, code blocks, nested and ordered lists, links
///   through Google's `/url?q=` redirect and text that looks like markdown.
enum CapturedMessages {
    static let realAnswer = #"""
{"v":1,"pageId":"398onyhinydmujfhso8","kind":"answer","blocks":[{"type":"paragraph","text":"**It is physically impossible** to traditional hard-boil an egg in an open pot of boiling water at the summit of Mount Everest, no matter how much time you give it."},{"type":"paragraph","text":"At sea level, a perfect hard-boiled egg takes about **9 to 12 minutes** in boiling water (100°C / 212°F). However, on Everest, you will only end up with a runny, soup-like disappointment."},{"type":"heading","level":2,"text":"The Science Behind the Failed Breakfast"},{"type":"paragraph","text":"An egg doesn't cook because it is submerged in \"boiling\" water; it cooks because the heat energy denatures and coagulates the proteins in the egg. Different parts of the egg solidify at different temperature thresholds:"},{"type":"listItem","ordered":false,"marker":"•","depth":0,"text":"**Egg Yolks:** Require a minimum temperature of about **65°C to 70°C (149°F to 158°F)** to solidify."},{"type":"listItem","ordered":false,"marker":"•","depth":0,"text":"**Egg Whites:** Require a minimum temperature of at least **80°C to 85°C (176°F to 185°F)** to firmly set."},{"type":"paragraph","text":"Because water at the summit of Everest boils at roughly **68°C (154°F)**, the water will vigorously evaporate and turn to steam before it can ever reach the temperature needed to cook the egg whites. The yolk might thicken into a paste over a very long period, but the whites will remain liquid forever."},{"type":"heading","level":2,"text":"Cooking Times: Sea Level vs. Everest"},{"type":"table","header":["Location","Water Boiling Point","Hard-Boil Time","Result"],"rows":[["**Sea Level**","100°C (212°F)","**9–12 minutes**","Perfectly firm white and yolk."],["**Everest Summit** (Open Pot)","68°C (154°F)","**Infinite / Impossible**","A warm, runny mess; the white never solidifies."],["**Everest Summit** (With Pressure Cooker)","Artificial 100°C+ (212°F+)","**9–12 minutes**","Perfectly cooked (by trapping steam to artificially raise the boiling point)."]]},{"type":"paragraph","text":"Are you interested in learning about **how much longer it takes to cook at moderate high altitudes** (like Denver or Mexico City) where hard-boiling is still possible, or would you like to explore **other bizarre thermodynamic limits** at extreme elevations?"}],"sources":[{"title":"This Is Why You Can’t Boil An Egg On Mount Everest | IFLScience","url":"https://www.iflscience.com/this-is-why-you-cant-boil-an-egg-on-mount-everest-74028","siteName":"IFLScience"},{"title":"Atmospheric Pressure: You Can't Boil an Egg on Mount Everest","url":"https://www.cplabsafety.com/science-and-safety-blog/?p=atmospheric-pressure-boiled-eggs","siteName":"CP Lab Safety"},{"title":"Vapour Pressure & Why You can't Boil an Egg on Everest","url":"https://www.northridgepumps.com/article-2_boil-egg-on-everest","siteName":"North Ridge Pumps"},{"title":"This Is Why You Can't Boil An Egg On Mount Everest - Facebook","url":"https://www.facebook.com/IFLScience/posts/this-is-why-you-cant-boil-an-egg-on-mount-everest/986724146452036/","siteName":"Facebook"}],"followUps":[],"isComplete":true,"signedIn":null,"accountLabel":null}
"""#

    static let thread = #"""
{"v":1,"pageId":"pj92zaex9qmujfhu1i","kind":"answer","blocks":[{"type":"paragraph","text":"**It is physically impossible** to traditional hard-boil an egg in an open pot of boiling water at the summit of Mount Everest, no matter how much time you give it."},{"type":"paragraph","text":"At sea level, a perfect hard-boiled egg takes about **9 to 12 minutes** in boiling water (100°C / 212°F). However, on Everest, you will only end up with a runny, soup-like disappointment."},{"type":"heading","level":2,"text":"The Science Behind the Failed Breakfast"},{"type":"paragraph","text":"An egg doesn't cook because it is submerged in \"boiling\" water; it cooks because the heat energy denatures and coagulates the proteins in the egg. Different parts of the egg solidify at different temperature thresholds:"},{"type":"listItem","ordered":false,"marker":"•","depth":0,"text":"**Egg Yolks:** Require a minimum temperature of about **65°C to 70°C (149°F to 158°F)** to solidify."},{"type":"listItem","ordered":false,"marker":"•","depth":0,"text":"**Egg Whites:** Require a minimum temperature of at least **80°C to 85°C (176°F to 185°F)** to firmly set."},{"type":"paragraph","text":"Because water at the summit of Everest boils at roughly **68°C (154°F)**, the water will vigorously evaporate and turn to steam before it can ever reach the temperature needed to cook the egg whites. The yolk might thicken into a paste over a very long period, but the whites will remain liquid forever."},{"type":"heading","level":2,"text":"Cooking Times: Sea Level vs. Everest"},{"type":"table","header":["Location","Water Boiling Point","Hard-Boil Time","Result"],"rows":[["**Sea Level**","100°C (212°F)","**9–12 minutes**","Perfectly firm white and yolk."],["**Everest Summit** (Open Pot)","68°C (154°F)","**Infinite / Impossible**","A warm, runny mess; the white never solidifies."],["**Everest Summit** (With Pressure Cooker)","Artificial 100°C+ (212°F+)","**9–12 minutes**","Perfectly cooked (by trapping steam to artificially raise the boiling point)."]]},{"type":"paragraph","text":"Are you interested in learning about **how much longer it takes to cook at moderate high altitudes** (like Denver or Mexico City) where hard-boiling is still possible, or would you like to explore **other bizarre thermodynamic limits** at extreme elevations?"},{"type":"paragraph","text":"Use `let x = a_b * 2` in Swift, see [the *Swift* docs](https://developer.apple.com/swift/#intro) or [this page](https://example.com/page). Stars: 5\\*3\\*2 and snake_case and \\_under\\_ and \\[brackets\\] and Vec\\<String> and \\&copy;\nsecond line"},{"type":"paragraph","text":"Visible text"},{"type":"heading","level":3,"text":"Steps"},{"type":"listItem","ordered":true,"marker":"3.","depth":0,"text":"Third **bold nested**"},{"type":"listItem","ordered":true,"marker":"4.","depth":0,"text":"Fourth"},{"type":"listItem","ordered":false,"marker":"•","depth":1,"text":"Sub A"},{"type":"listItem","ordered":false,"marker":"•","depth":1,"text":"Sub [B](https://example.org/sub)"},{"type":"divider"},{"type":"code","language":"Python","text":"def f(x):\n    return x * 2"},{"type":"code","language":"js","text":"const a = 1;\nconsole.log(a);"},{"type":"quote","text":"Quoted *words*"},{"type":"paragraph","text":"Paragraph inside a span wrapper"},{"type":"paragraph","text":"Second one"}],"sources":[{"title":"This Is Why You Can’t Boil An Egg On Mount Everest | IFLScience","url":"https://www.iflscience.com/this-is-why-you-cant-boil-an-egg-on-mount-everest-74028","siteName":"IFLScience"},{"title":"Atmospheric Pressure: You Can't Boil an Egg on Mount Everest","url":"https://www.cplabsafety.com/science-and-safety-blog/?p=atmospheric-pressure-boiled-eggs","siteName":"CP Lab Safety"},{"title":"Vapour Pressure & Why You can't Boil an Egg on Everest","url":"https://www.northridgepumps.com/article-2_boil-egg-on-everest","siteName":"North Ridge Pumps"},{"title":"This Is Why You Can't Boil An Egg On Mount Everest - Facebook","url":"https://www.facebook.com/IFLScience/posts/this-is-why-you-cant-boil-an-egg-on-mount-everest/986724146452036/","siteName":"Facebook"},{"title":"Mount Everest - Wikipedia","url":"https://en.wikipedia.org/wiki/Mount_Everest","siteName":null},{"title":"NASA boiling explainer","url":"https://www.nasa.gov/boil?x=1","siteName":null}],"followUps":[],"isComplete":true,"signedIn":true,"accountLabel":"Google Account: Jane Appleseed  \n(jane@example.com)"}
"""#
}

@Suite struct AIModeMessageFixtureTests {
    @Test func decodesTheRealAnswer() throws {
        let message = try AIModeMessage.decode(CapturedMessages.realAnswer)
        #expect(message.kind == .answer)
        #expect(message.isComplete)
        #expect(message.pageID?.isEmpty == false)
        #expect(message.signedIn == nil)
        #expect(message.account == nil)
        #expect(message.error == nil)
        #expect(message.blocks.count == 10)

        #expect(message.blocks.first == .paragraph(
            "**It is physically impossible** to traditional hard-boil an egg in an open pot of boiling water at the summit of Mount Everest, no matter how much time you give it."
        ))
        #expect(message.blocks[2] == .heading(level: 2, text: "The Science Behind the Failed Breakfast"))
        #expect(message.blocks[4] == .listItem(.init(
            ordered: false, marker: "•", depth: 0,
            text: "**Egg Yolks:** Require a minimum temperature of about **65°C to 70°C (149°F to 158°F)** to solidify."
        )))
        #expect(message.blocks[7] == .heading(level: 2, text: "Cooking Times: Sea Level vs. Everest"))

        guard case .table(let table) = message.blocks[8] else {
            Issue.record("expected a table at index 8")
            return
        }
        #expect(table.header == ["Location", "Water Boiling Point", "Hard-Boil Time", "Result"])
        #expect(table.rows.count == 3)
        #expect(table.rows[1] == ["**Everest Summit** (Open Pot)", "68°C (154°F)", "**Infinite / Impossible**", "A warm, runny mess; the white never solidifies."])

        // Chips become sources, never inline text: nothing like "IFLScience"
        // or "Related results" leaks into the answer.
        let text = message.blocks.map(\.plainText).joined(separator: "\n")
        #expect(!text.contains("Related results"))
        #expect(!text.contains("AI can make mistakes"))
    }

    @Test func realAnswerSourcesAreDedupedInFirstSeenOrder() throws {
        let message = try AIModeMessage.decode(CapturedMessages.realAnswer)
        #expect(message.sources.map(\.url.absoluteString) == [
            "https://www.iflscience.com/this-is-why-you-cant-boil-an-egg-on-mount-everest-74028",
            "https://www.cplabsafety.com/science-and-safety-blog/?p=atmospheric-pressure-boiled-eggs",
            "https://www.northridgepumps.com/article-2_boil-egg-on-everest",
            "https://www.facebook.com/IFLScience/posts/this-is-why-you-cant-boil-an-egg-on-mount-everest/986724146452036/",
        ])
        #expect(message.sources.map(\.siteName) == ["IFLScience", "CP Lab Safety", "North Ridge Pumps", "Facebook"])
        #expect(message.sources[0].title == "This Is Why You Can’t Boil An Egg On Mount Everest | IFLScience")
        #expect(message.sources[2].title == "Vapour Pressure & Why You can't Boil an Egg on Everest")
    }

    @Test func snapshotCarriesEverything() throws {
        let message = try AIModeMessage.decode(CapturedMessages.realAnswer)
        let snapshot = message.snapshot
        #expect(snapshot == AnswerSnapshot(blocks: message.blocks, sources: message.sources, isComplete: true))
        #expect(!snapshot.isEmpty)
        #expect(snapshot.plainText.contains("Sources:\n- This Is Why You Can’t Boil An Egg On Mount Everest | IFLScience"))
    }

    @Test func decodesTheThreadPage() throws {
        let message = try AIModeMessage.decode(CapturedMessages.thread)
        #expect(message.kind == .answer)
        #expect(message.isComplete)
        #expect(message.signedIn == true)
        #expect(message.account == GoogleAccount(name: "Jane Appleseed", email: "jane@example.com"))

        let blocks = message.blocks
        #expect(blocks.contains(.paragraph(
            #"Use `let x = a_b * 2` in Swift, see [the *Swift* docs](https://developer.apple.com/swift/#intro) or [this page](https://example.com/page). Stars: 5\*3\*2 and snake_case and \_under\_ and \[brackets\] and Vec\<String> and \&copy;"# + "\nsecond line"
        )))
        #expect(blocks.contains(.heading(level: 3, text: "Steps")))
        #expect(blocks.contains(.listItem(.init(ordered: true, marker: "3.", depth: 0, text: "Third **bold nested**"))))
        #expect(blocks.contains(.listItem(.init(ordered: false, marker: "•", depth: 1, text: "Sub [B](https://example.org/sub)"))))
        #expect(blocks.contains(.divider))
        #expect(blocks.contains(.code(language: "Python", text: "def f(x):\n    return x * 2")))
        #expect(blocks.contains(.code(language: "js", text: "const a = 1;\nconsole.log(a);")))
        #expect(blocks.contains(.quote("Quoted *words*")))
        #expect(!blocks.map(\.plainText).joined().contains("OLD TURN"))

        // Inline citations first, then the side cards; the duplicate card and
        // the javascript: card are gone, the /url?q= card is unwrapped.
        #expect(message.sources.count == 6)
        #expect(message.sources[4] == WebSource(title: "Mount Everest - Wikipedia", url: URL(string: "https://en.wikipedia.org/wiki/Mount_Everest")!))
        #expect(message.sources[5].url.absoluteString == "https://www.nasa.gov/boil?x=1")
        #expect(message.sources[5].title == "NASA boiling explainer")
    }

    /// The extractor's inline markdown has to survive the renderer's parser:
    /// escaped text stays literal, links stay links.
    @Test func inlineMarkdownParsesAsIntended() throws {
        let message = try AIModeMessage.decode(CapturedMessages.thread)
        guard case .paragraph(let text)? = message.blocks.first(where: {
            if case .paragraph(let t) = $0 { return t.hasPrefix("Use ") }
            return false
        }) else {
            Issue.record("paragraph missing")
            return
        }
        let parsed = try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        let plain = String(parsed.characters)
        #expect(plain.contains("5*3*2 and snake_case and _under_ and [brackets] and Vec<String> and &copy;"))
        #expect(plain.contains("see the Swift docs or this page."))
        // "the *Swift* docs" is three runs sharing one link.
        var links: [String] = []
        for run in parsed.runs {
            if let link = run.link?.absoluteString, links.last != link { links.append(link) }
        }
        #expect(links == ["https://developer.apple.com/swift/#intro", "https://example.com/page"])
    }
}
