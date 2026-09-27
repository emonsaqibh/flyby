import Foundation

/// What the AI Mode page is showing.
///
/// The in-page extractor reports one of these with every message, and the
/// engine classifies each main-frame URL into one before it loads — Google
/// usually redirects to its CAPTCHA and consent pages, so the URL alone often
/// says what's coming.
public enum AIModePageKind: String, Sendable, Hashable, Codable, CaseIterable {
    /// Some of an answer is on the page.
    case answer
    /// A Google page with nothing to show yet.
    case loading
    /// Google's "unusual traffic" wall.
    case captcha
    /// The EU cookie-consent interstitial, as a page or an inline dialog.
    case consent
    /// Google's account pages — a sign-in wall, or a sign-in the user started.
    case signIn

    /// Google wants the user, not Flyby: the page has to be shown to them.
    public var needsUser: Bool {
        switch self {
        case .captcha, .consent, .signIn: return true
        case .answer, .loading:           return false
        }
    }

    /// Classifies a main-frame URL, or returns nil for an ordinary page whose
    /// DOM has to be looked at.
    ///
    /// Only Google hosts count, so a stray `/sorry/` path elsewhere is nothing.
    public init?(url: URL) {
        guard let parts = AIModePage.parts(of: url), AIModePage.isGoogleHost(parts.host) else { return nil }
        if parts.path == "/sorry" || parts.path.hasPrefix("/sorry/") {
            self = .captcha
        } else if parts.host.hasPrefix("consent.") {
            self = .consent
        } else if parts.host.hasPrefix("accounts.") {
            self = .signIn
        } else {
            return nil
        }
    }

    /// Unknown kinds read as `.loading` — a newer script shouldn't fail the
    /// whole message.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIModePageKind(rawValue: raw) ?? .loading
    }
}

/// URL facts the engine needs about Google's pages.
public enum AIModePage {
    public static func isGoogleHost(_ host: String) -> Bool {
        !host.isEmpty && GoogleCookies.isGoogleDomain(host.lowercased())
    }

    /// `www.google.*` or the bare domain: where search itself lives, as
    /// opposed to accounts, consent, maps and the rest.
    public static func isSearchHost(_ url: URL) -> Bool {
        guard let host = parts(of: url)?.host, isGoogleHost(host) else { return false }
        return host.hasPrefix("www.google.") || host.hasPrefix("google.")
    }

    /// A Google search results page — where a solved CAPTCHA or an accepted
    /// consent wall sends the user back to.
    public static func isResultsPage(_ url: URL) -> Bool {
        isSearchHost(url) && parts(of: url)?.path == "/search"
    }

    static func parts(of url: URL) -> (host: String, path: String)? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host?.lowercased() else { return nil }
        return (host, components.path)
    }
}
