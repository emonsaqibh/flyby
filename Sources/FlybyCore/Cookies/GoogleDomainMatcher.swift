import Foundation

/// Decides whether a cookie's domain belongs to Google.
///
/// Cookies are copied wholesale out of a browser and we only want the ones that
/// authenticate Google, so the match has to be tight: a permissive `contains`
/// would hand a look-alike site (`google.evil.com`, `googleusercontent.com`)
/// the user's session. We therefore match the *registrable* domain rather than
/// a substring — `google.com` and its subdomains, plus Google's country
/// domains (`google.de`, `google.co.uk`, `google.com.au`), and nothing whose
/// registrable part merely happens to spell "google".
enum GoogleDomainMatcher {
    static func matches(_ domain: String) -> Bool {
        // Normalise: cookie domains arrive lower/upper-cased, sometimes with a
        // leading dot (domain cookie) or a trailing dot (fully-qualified).
        var host = domain.lowercased()
        while host.hasPrefix(".") { host.removeFirst() }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        // Any empty label (e.g. "google..com") is malformed.
        guard labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let n = labels.count
        guard n >= 2 else { return false }

        func label(_ i: Int) -> String? { (0..<n).contains(i) ? labels[i] : nil }
        let isCountryCode: (String) -> Bool = { $0.count == 2 && $0.allSatisfy { $0.isLetter } }

        // google.com and its subdomains: …, "google", "com".
        if label(n - 2) == "google", label(n - 1) == "com" {
            return true
        }
        // A two-letter public suffix at the end is a country domain. It is only
        // Google's if "google" sits in the registrable position immediately
        // before it, or before a "co"/"com" second-level suffix.
        if let last = label(n - 1), isCountryCode(last) {
            // google.<cc>  (google.de, mail.google.de)
            if label(n - 2) == "google" { return true }
            // google.co.<cc> / google.com.<cc>  (google.co.uk, www.google.com.au)
            if label(n - 3) == "google", let mid = label(n - 2), mid == "co" || mid == "com" {
                return true
            }
        }
        return false
    }
}
