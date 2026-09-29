import Foundation
import Testing
@testable import FlybyCore

@Suite struct AIModeQueryTests {
    @Test func buildsTheAIModeURL() {
        let url = AIModeQuery.url(for: "what is 1+1?", languageCode: "en")
        #expect(url.absoluteString == "https://www.google.com/search?q=what+is+1%2B1%3F&udm=50&hl=en")
    }

    @Test func encodesUnicodeAndReservedCharacters() {
        let url = AIModeQuery.url(for: "café & crème/50%=#", languageCode: "fr")
        #expect(url.absoluteString == "https://www.google.com/search?q=caf%C3%A9+%26+cr%C3%A8me%2F50%25%3D%23&udm=50&hl=fr")
    }

    @Test func leavesRegionAndPersonalisationToGoogle() {
        let url = AIModeQuery.url(for: "weather", languageCode: "de").absoluteString
        #expect(!url.contains("gl="))
        #expect(!url.contains("pws"))
        #expect(url.contains("udm=50"))
    }

    @Test func omitsHLWithoutALanguage() {
        #expect(AIModeQuery.url(for: "x", languageCode: nil).absoluteString == "https://www.google.com/search?q=x&udm=50")
        #expect(AIModeQuery.url(for: "x", languageCode: "").absoluteString == "https://www.google.com/search?q=x&udm=50")
    }

    @Test func startURL() {
        #expect(AIModeQuery.startURL(languageCode: "de").absoluteString == "https://www.google.com/search?udm=50&hl=de")
        #expect(AIModeQuery.startURL(languageCode: nil).absoluteString == "https://www.google.com/search?udm=50")
    }

    @Test func homeURL() {
        #expect(AIModeQuery.homeURL(languageCode: "de").absoluteString == "https://www.google.com/?hl=de")
        #expect(AIModeQuery.homeURL(languageCode: nil).absoluteString == "https://www.google.com/")
    }

    @Test func mapsPreferredLanguagesToHL() {
        let cases: [(identifier: String, hl: String)] = [
            ("en-US", "en"), ("en-GB", "en-GB"), ("en", "en"), ("de-DE", "de"), ("fr_CA", "fr"),
            ("zh-Hans-CN", "zh-CN"), ("zh-Hant-TW", "zh-TW"), ("zh-Hant-HK", "zh-HK"), ("zh-TW", "zh-TW"),
            ("pt-PT", "pt-PT"), ("pt-BR", "pt-BR"), ("pt", "pt-BR"), ("nb-NO", "no"), ("es-419", "es"),
            ("JA-jp", "ja"),
        ]
        for c in cases {
            #expect(AIModeQuery.googleLanguageCode(for: c.identifier) == c.hl)
        }
    }

    @Test func rejectsNonsenseLanguages() {
        #expect(AIModeQuery.googleLanguageCode(for: "") == nil)
        #expect(AIModeQuery.googleLanguageCode(for: "123") == nil)
        #expect(AIModeQuery.googleLanguageCode(for: "x") == nil)
    }
}

@Suite struct AIModePageTests {
    private func kind(_ string: String) -> AIModePageKind? {
        URL(string: string).flatMap(AIModePageKind.init(url:))
    }

    @Test func classifiesAttentionPages() {
        #expect(kind("https://www.google.com/sorry/index?continue=https://www.google.com/search%3Fq%3Dx&q=abc") == .captcha)
        #expect(kind("https://ipv4.google.com/sorry/index?continue=x") == .captcha)
        #expect(kind("https://www.google.com/sorry/") == .captcha)
        #expect(kind("https://consent.google.com/ml?continue=https://www.google.com/") == .consent)
        #expect(kind("https://accounts.google.com/v3/signin/identifier?continue=x") == .signIn)
        #expect(kind("https://accounts.google.com/ServiceLogin?continue=x") == .signIn)
    }

    @Test func ordinaryPagesAreNotClassified() {
        #expect(kind("https://www.google.com/search?q=sorry&udm=50") == nil)
        #expect(kind("https://www.google.com/sorryish") == nil)
        #expect(kind("https://www.google.com/") == nil)
        #expect(kind("https://example.com/sorry/index") == nil)
        #expect(kind("https://accounts.example.com/signin") == nil)
        #expect(kind("https://consent.notgoogle.com/") == nil)
    }

    @Test func resultsPages() {
        func url(_ string: String) -> URL { URL(string: string)! }
        #expect(AIModePage.isResultsPage(url("https://www.google.com/search?q=x&udm=50")))
        #expect(AIModePage.isSearchHost(url("https://www.google.com/search?q=x&udm=50")))
        #expect(!AIModePage.isResultsPage(url("https://www.google.com/")))
        #expect(!AIModePage.isResultsPage(url("https://accounts.google.com/search")))
        #expect(!AIModePage.isResultsPage(url("https://maps.google.com/search")))
        #expect(AIModePage.isSearchHost(url("https://google.com/")))
        #expect(!AIModePage.isSearchHost(url("https://example.com/search")))
    }

    @Test func needsUser() {
        #expect(AIModePageKind.allCases.filter(\.needsUser) == [.captcha, .consent, .signIn])
    }

    @Test func unknownKindsDecodeAsLoading() throws {
        let kinds = try JSONDecoder().decode([AIModePageKind].self, from: Data(#"["answer", "signIn", "somethingNew"]"#.utf8))
        #expect(kinds == [.answer, .signIn, .loading])
    }
}

@Suite struct AIModeLinksTests {
    private func clean(_ raw: String) -> String? {
        AIModeLinks.sanitize(raw)?.absoluteString
    }

    @Test func stripsTextFragments() {
        #expect(clean("https://example.com/page#:~:text=hello%20world") == "https://example.com/page")
        #expect(clean("https://example.com/page#section:~:text=x") == "https://example.com/page#section")
        #expect(clean("https://example.com/page#section") == "https://example.com/page#section")
        #expect(clean("https://example.com/page") == "https://example.com/page")
    }

    @Test func unwrapsGoogleRedirects() {
        #expect(clean("/url?q=https://example.com/a%3Fb%3D1&sa=U&ved=x") == "https://example.com/a?b=1")
        #expect(clean("https://www.google.com/url?url=https://example.com/b&sa=t") == "https://example.com/b")
        #expect(clean("https://www.google.com/url?q=https://example.com/c%23:~:text%3Dfoo") == "https://example.com/c")
    }

    @Test func keepsOpaqueGotoRedirectsAbsolute() {
        #expect(clean("/goto?url=CAESAB") == "https://www.google.com/goto?url=CAESAB")
    }

    @Test func resolvesRelativeLinksAgainstGoogle() {
        #expect(clean("/search?q=x&udm=50") == "https://www.google.com/search?q=x&udm=50")
    }

    @Test func rejectsNonWebLinks() {
        #expect(clean("javascript:alert(1)") == nil)
        #expect(clean("mailto:jane@example.com") == nil)
        #expect(clean("data:text/html,hi") == nil)
        #expect(clean("https://www.google.com/url?q=javascript:alert(1)") == nil)
        #expect(clean("") == nil)
        #expect(clean("   ") == nil)
    }

    @Test func keepsPlainHTTP() {
        #expect(clean("http://example.com/x") == "http://example.com/x")
    }

    @Test func sanitizesURLValues() {
        let url = URL(string: "https://www.google.com/url?q=https://example.com/d")!
        #expect(AIModeLinks.sanitize(url)?.absoluteString == "https://example.com/d")
    }
}

@Suite struct AIModeMessageDecodingTests {
    @Test func minimalMessageTakesDefaults() throws {
        let message = try AIModeMessage.decode(#"{"kind": "captcha"}"#)
        #expect(message == AIModeMessage(kind: .captcha))
        #expect(message.snapshot == .empty)
        #expect(try AIModeMessage.decode("{}").kind == .loading)
        #expect(try AIModeMessage.decode(#"{"kind": "hologram"}"#).kind == .loading)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: (any Error).self) { try AIModeMessage.decode("not json") }
    }

    @Test func sanitisesAndDedupesSources() throws {
        let message = try AIModeMessage.decode(#"""
        {"kind": "answer", "sources": [
          {"title": "x", "url": "javascript:alert(1)"},
          {"title": " ", "url": "https://www.google.com/url?q=https://a.example/x%23:~:text%3Dy", "siteName": "A"},
          {"url": "https://b.example/"},
          {"title": "dup", "url": "https://a.example/x"},
          {"title": "no url"}
        ]}
        """#)
        #expect(message.sources == [
            WebSource(title: "A", url: URL(string: "https://a.example/x")!, siteName: "A"),
            WebSource(title: "b.example", url: URL(string: "https://b.example/")!),
        ])
    }

    @Test func dropsEmptyParagraphs() throws {
        let message = try AIModeMessage.decode(#"""
        {"blocks": [{"type": "paragraph", "text": ""}, {"type": "hologram"}, {"type": "divider"}, {"type": "paragraph", "text": "kept"}]}
        """#)
        #expect(message.blocks == [.divider, .paragraph("kept")])
    }

    @Test func readsTheAccountFromItsLabel() throws {
        let message = try AIModeMessage.decode(#"{"signedIn": true, "accountLabel": "Google Account: Jane\n(jane@example.com)"}"#)
        #expect(message.signedIn == true)
        #expect(message.account == GoogleAccount(name: "Jane", email: "jane@example.com"))
    }

    @Test func signedOutMeansNoAccount() throws {
        let message = try AIModeMessage.decode(#"{"signedIn": false, "accountLabel": "Google Account: Jane (jane@example.com)"}"#)
        #expect(message.signedIn == false)
        #expect(message.account == nil)
    }

    @Test func unknownSignInStateStaysUnknown() throws {
        let message = try AIModeMessage.decode(#"{"signedIn": null, "accountLabel": null}"#)
        #expect(message.signedIn == nil)
        #expect(message.account == nil)
    }

    @Test func explicitAccountWins() throws {
        let message = try AIModeMessage.decode(#"""
        {"signedIn": true, "account": {"name": "N", "email": "n@example.com"}, "accountLabel": "Google Account: Other (o@example.com)"}
        """#)
        #expect(message.account == GoogleAccount(name: "N", email: "n@example.com"))
    }

    @Test func carriesScriptErrors() throws {
        #expect(try AIModeMessage.decode(#"{"error": "TypeError: x"}"#).error == "TypeError: x")
    }

    @Test func readsWhichTurnItIsAbout() throws {
        #expect(try AIModeMessage.decode(#"{"kind": "answer", "turn": 2}"#).turn == 2)
        // The page it loaded with, when an older script doesn't say.
        #expect(try AIModeMessage.decode(#"{"kind": "answer"}"#).turn == 0)
        #expect(try AIModeMessage.decode(#"{"kind": "answer", "turn": "two"}"#).turn == 0)
    }
}

@Suite struct GoogleAccountLabelTests {
    @Test func parsesNameAndEmail() {
        let cases: [(label: String, name: String, email: String)] = [
            ("Google Account: Jane Appleseed  \n(jane@example.com)", "Jane Appleseed", "jane@example.com"),
            ("Google-Konto: Max Mustermann (max@example.de)", "Max Mustermann", "max@example.de"),
            ("Google アカウント: 山田 太郎（taro@example.jp）", "山田 太郎", "taro@example.jp"),
            ("Google Account: Jane (Work) (jane@example.com)", "Jane (Work)", "jane@example.com"),
            ("Jane Appleseed (jane@example.com)", "Jane Appleseed", "jane@example.com"),
        ]
        for c in cases {
            #expect(GoogleAccount(accountLabel: c.label) == GoogleAccount(name: c.name, email: c.email))
        }
    }

    @Test func emailOnly() {
        #expect(GoogleAccount(accountLabel: "Google Account: jane@example.com") == GoogleAccount(email: "jane@example.com"))
    }

    @Test func nothingToFind() {
        #expect(GoogleAccount(accountLabel: "") == nil)
        #expect(GoogleAccount(accountLabel: "Sign in") == nil)
        #expect(GoogleAccount(accountLabel: "Google Account") == nil)
    }

    @Test func displayName() {
        #expect(GoogleAccount(accountLabel: "Google Account: Jane (jane@example.com)")?.displayName == "Jane (jane@example.com)")
    }
}

@Suite struct SafariIdentityTests {
    @Test func appendsSafarisOwnSuffix() {
        #expect(SafariIdentity.applicationName(safariVersion: "26.0") == "Version/26.0 Safari/605.1.15")
        #expect(SafariIdentity.applicationName(safariVersion: "18.3.1") == "Version/18.3.1 Safari/605.1.15")
        #expect(SafariIdentity.applicationName(safariVersion: " 17.4 ") == "Version/17.4 Safari/605.1.15")
        #expect(SafariIdentity.applicationName(safariVersion: "26") == "Version/26.0 Safari/605.1.15")
    }

    @Test func fallsBackOnAnythingOdd() {
        for odd in [nil, "", "abc", "1.2.3.4", "26..1", "26.0b"] as [String?] {
            #expect(SafariIdentity.applicationName(safariVersion: odd) == "Version/26.0 Safari/605.1.15")
        }
    }
}
