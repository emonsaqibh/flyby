import Foundation

/// A picture asked about along with a question — a screenshot of the window
/// the user was in. What's kept with the chat: a small thumbnail to show in
/// the question's bubble, never the full picture.
public struct Attachment: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    /// What the picture shows, in words — "Safari — Flyby on GitHub" — for
    /// VoiceOver and for when the thumbnail can't be drawn.
    public var title: String
    /// A JPEG a few hundred pixels across.
    public var thumbnail: Data

    public init(id: UUID = UUID(), title: String, thumbnail: Data) {
        self.id = id
        self.title = title
        self.thumbnail = thumbnail
    }
}

/// An image sent to a model with a message.
public struct ChatImage: Sendable, Hashable {
    public var data: Data
    /// `image/jpeg`, `image/png`.
    public var mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}
