import Foundation

/// Cleans the links an AI Mode page hands out before Flyby shows or opens them.
public enum AIModeLinks {
    /// An absolute http(s) URL, or nil.
    ///
    /// - Google's `/url?q=<target>` redirect is unwrapped to the target, so a
    ///   click doesn't round-trip through Google and the chip shows the real
    ///   site.
    /// - `/goto?url=<blob>` is kept as an absolute Google URL: the blob is
    ///   encrypted, and following the redirect is the only way to resolve it.
    /// - `#:~:text=` fragment directives are dropped; they're a highlight for
    ///   Google's own click-through, not part of the address.
    /// - Anything that isn't http(s) — `javascript:`, `data:`, `mailto:` — is
    ///   rejected.
    public static func sanitize(_ raw: String, relativeTo base: URL? = AIModeQuery.google) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: base) else { return nil }
        return sanitize(url.absoluteURL, unwrapping: true)
    }

    public static func sanitize(_ url: URL) -> URL? {
        sanitize(url.absoluteURL, unwrapping: true)
    }

    private static func sanitize(_ url: URL, unwrapping: Bool) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }

        if unwrapping, components.path == "/url", AIModePage.isGoogleHost(host) {
            let target = components.queryItems?.first(where: { $0.name == "q" || $0.name == "url" })?.value
            if let target, let inner = URL(string: target) {
                return sanitize(inner.absoluteURL, unwrapping: false)
            }
        }

        if let fragment = components.percentEncodedFragment, let directive = fragment.range(of: ":~:") {
            let kept = String(fragment[..<directive.lowerBound])
            components.percentEncodedFragment = kept.isEmpty ? nil : kept
        }
        return components.url
    }
}
