import Foundation

/// Where an AI Mode search goes.
public enum AIModeQuery {
    /// Google's origin. Also the base that relative links on its pages resolve
    /// against.
    public static let google: URL = URL(string: "https://www.google.com/")!

    /// `https://www.google.com/search?q=<query>&udm=50&hl=<lang>`.
    ///
    /// `udm=50` selects AI Mode. `hl` follows the user's language: the
    /// extractor is language-agnostic, so there's no reason to force English
    /// on anyone. Deliberately absent are `gl`, since a region that contradicts
    /// the IP's is a classic bot tell, and `pws=0`, which switches off the
    /// personalisation a signed-in session is there to provide.
    ///
    /// Spaces become `+` and everything else outside RFC 3986's unreserved set
    /// is percent-encoded, which is exactly what Google's own search box sends.
    public static func url(for query: String, languageCode: String?) -> URL {
        var parameters = "q=" + formEncode(query) + "&udm=50"
        if let hl = languageCode, !hl.isEmpty {
            parameters += "&hl=" + formEncode(hl)
        }
        return URL(string: "https://www.google.com/search?" + parameters) ?? google
    }

    /// AI Mode with nothing asked yet: `udm=50` and no `q`, in the user's
    /// language. A question with a screenshot starts here, because a URL
    /// can't carry a picture: it's asked through the page's own composer.
    public static func startURL(languageCode: String?) -> URL {
        var parameters = "udm=50"
        if let hl = languageCode, !hl.isEmpty {
            parameters += "&hl=" + formEncode(hl)
        }
        return URL(string: "https://www.google.com/search?" + parameters) ?? google
    }

    /// google.com itself, in the user's language — what the engine loads to
    /// warm up before the first search.
    public static func homeURL(languageCode: String?) -> URL {
        guard let hl = languageCode, !hl.isEmpty else { return google }
        return URL(string: "https://www.google.com/?hl=" + formEncode(hl)) ?? google
    }

    /// The `hl` for the user's first preferred language, if it has one.
    public static var preferredLanguageCode: String? {
        Locale.preferredLanguages.first.flatMap(googleLanguageCode(for:))
    }

    /// Maps a BCP 47 identifier ("en-US", "zh-Hans-CN", "pt_PT") to the `hl`
    /// value Google uses. Only language variants Google treats as separate
    /// UIs keep their region; everything else is the bare language, so the
    /// region is left for Google to infer rather than asserted.
    public static func googleLanguageCode(for identifier: String) -> String? {
        let parts = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        guard let first = parts.first else { return nil }
        let language = first.lowercased()
        guard (2...3).contains(language.count), language.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            return nil
        }

        var script: String?
        var region: String?
        for part in parts.dropFirst() {
            let letters = part.allSatisfy { $0.isASCII && $0.isLetter }
            let digits = part.allSatisfy { $0.isASCII && $0.isNumber }
            if script == nil, region == nil, part.count == 4, letters {
                script = part.lowercased()
            } else if region == nil, (part.count == 2 && letters) || (part.count == 3 && digits) {
                region = part.uppercased()
            }
        }

        switch language {
        case "zh":
            if region == "HK" || region == "MO" { return "zh-HK" }
            if script == "hant" || region == "TW" { return "zh-TW" }
            return "zh-CN"
        case "pt":
            return region == "PT" ? "pt-PT" : "pt-BR"
        case "en":
            return region == "GB" ? "en-GB" : "en"
        case "nb":
            return "no"
        default:
            return language
        }
    }

    /// `application/x-www-form-urlencoded`, the way browsers write a query.
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~ ")
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return encoded.replacingOccurrences(of: " ", with: "+")
    }
}
