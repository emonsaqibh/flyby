import Foundation

/// One message from the in-page extractor: what the AI Mode page shows now.
///
/// The script posts a JSON string whenever what it reads changes:
///
///     {"v": 1, "pageId": "…", "kind": "answer",
///      "blocks": [<AnswerBlock wire format>],
///      "sources": [{"title": "…", "url": "https://…", "siteName": "…"}],
///      "followUps": [], "isComplete": false,
///      "signedIn": true, "accountLabel": "Google Account: Jane (jane@…)"}
///
/// Decoding is forgiving in the same spirit as `AnswerBlock`: missing fields
/// take defaults, unknown kinds read as loading, and sources whose URL isn't a
/// usable web address are dropped rather than failing the message.
public struct AIModeMessage: Sendable, Hashable {
    public var kind: AIModePageKind
    /// Identifies the document that sent this, so a message from a page the
    /// engine has already left can be told apart.
    public var pageID: String?
    public var blocks: [AnswerBlock]
    public var sources: [WebSource]
    public var followUps: [String]
    public var isComplete: Bool
    /// `nil` when the page shows no account UI either way (a CAPTCHA, a page
    /// that hasn't drawn its header yet).
    public var signedIn: Bool?
    public var account: GoogleAccount?
    /// Set when the script itself hit an exception.
    public var error: String?

    public init(
        kind: AIModePageKind,
        pageID: String? = nil,
        blocks: [AnswerBlock] = [],
        sources: [WebSource] = [],
        followUps: [String] = [],
        isComplete: Bool = false,
        signedIn: Bool? = nil,
        account: GoogleAccount? = nil,
        error: String? = nil
    ) {
        self.kind = kind
        self.pageID = pageID
        self.blocks = blocks
        self.sources = sources
        self.followUps = followUps
        self.isComplete = isComplete
        self.signedIn = signedIn
        self.account = account
        self.error = error
    }

    public var snapshot: AnswerSnapshot {
        AnswerSnapshot(blocks: blocks, sources: sources, followUps: followUps, isComplete: isComplete)
    }

    public static func decode(_ json: String) throws -> AIModeMessage {
        try JSONDecoder().decode(AIModeMessage.self, from: Data(json.utf8))
    }
}

extension AIModeMessage: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, pageId, blocks, sources, followUps, isComplete, signedIn, account, accountLabel, error
    }

    private struct RawSource: Decodable {
        var title: String?
        var url: String?
        var siteName: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(AIModePageKind.self, forKey: .kind) ?? .loading
        pageID = try c.decodeIfPresent(String.self, forKey: .pageId)
        blocks = (try c.decodeIfPresent([AnswerBlock].self, forKey: .blocks) ?? []).filter { block in
            if case .paragraph(let text) = block { return !text.isEmpty }
            return true
        }
        followUps = (try c.decodeIfPresent([String].self, forKey: .followUps) ?? []).filter { !$0.isEmpty }
        isComplete = try c.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        signedIn = try c.decodeIfPresent(Bool.self, forKey: .signedIn)
        error = try c.decodeIfPresent(String.self, forKey: .error)

        var sources: [WebSource] = []
        sources.merge((try c.decodeIfPresent([RawSource].self, forKey: .sources) ?? []).compactMap(Self.source))
        self.sources = sources

        if signedIn == false {
            account = nil
        } else if let explicit = try c.decodeIfPresent(GoogleAccount.self, forKey: .account) {
            account = explicit
        } else {
            account = try c.decodeIfPresent(String.self, forKey: .accountLabel).flatMap(GoogleAccount.init(accountLabel:))
        }
    }

    private static func source(_ raw: RawSource) -> WebSource? {
        guard let string = raw.url, let url = AIModeLinks.sanitize(string) else { return nil }
        let site = raw.siteName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let siteName = site?.isEmpty == false ? site : nil
        let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = siteName ?? url.host ?? url.absoluteString
        return WebSource(title: title.isEmpty ? fallback : title, url: url, siteName: siteName)
    }
}
