import Foundation

/// A page the answer cites.
///
/// Identified by its URL rather than a fresh UUID, so a source that arrives in
/// two streamed updates is the same chip both times instead of re-animating —
/// and so the list keeps a stable order while the answer is still streaming.
public struct WebSource: Sendable, Hashable, Codable, Identifiable {
    public var title: String
    public var url: URL
    /// "Wikipedia", "The Verge" — whatever the provider calls the site, if it
    /// says. Falls back to the host when drawn.
    public var siteName: String?

    public var id: String { url.absoluteString }

    public init(title: String, url: URL, siteName: String? = nil) {
        self.title = title
        self.url = url
        self.siteName = siteName
    }

    /// `siteName`, else the host without a leading "www.".
    public var displaySite: String {
        if let siteName, !siteName.isEmpty { return siteName }
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

extension Array where Element == WebSource {
    /// Appends sources not already present, keeping first-seen order.
    public mutating func merge(_ incoming: [WebSource]) {
        var seen = Set(map(\.id))
        for source in incoming where seen.insert(source.id).inserted {
            append(source)
        }
    }
}
