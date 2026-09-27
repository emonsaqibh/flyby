import Foundation

public extension BrowserCookie {
    /// Builds an `HTTPCookie` for injection into a `WKWebsiteDataStore`.
    ///
    /// The domain is passed through exactly as the browser stored it, and that
    /// matters: a leading dot (".google.com") tells `HTTPCookie` this is a
    /// *domain* cookie that also matches subdomains, while a bare host
    /// ("accounts.google.com") stays host-only. Google's session cookies rely on
    /// this distinction, so rewriting the domain would either leak a host-only
    /// cookie across subdomains or stop a domain cookie matching them. Returns
    /// nil only if Foundation rejects the assembled properties.
    ///
    /// Foundation caps the expiry at 400 days out (RFC 6265bis), so Google's
    /// two-year cookies come back shorter. Irrelevant in practice: Flyby
    /// re-imports far more often than that.
    func makeHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path.isEmpty ? "/" : path,
        ]
        if let expires {
            properties[.expires] = expires
        }
        // For these flag keys HTTPCookie treats any present value as "on"; the
        // string "TRUE" is the conventional one.
        if isSecure {
            properties[.secure] = "TRUE"
        }
        if isHTTPOnly {
            // Not a documented property key, but WebKit honours it and there is
            // no first-class flag for HttpOnly in the properties dictionary.
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
        }
        #if canImport(Darwin)
        // SameSite policy exists only in Apple's Foundation. "none" has no
        // dedicated policy constant, so it is simply left unset.
        switch sameSite {
        case .some(.lax):
            properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax
        case .some(.strict):
            properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
        default:
            break
        }
        #endif
        return HTTPCookie(properties: properties)
    }
}
