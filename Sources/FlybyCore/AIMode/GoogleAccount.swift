import Foundation

/// Who the Google session belongs to, as far as a page lets us see.
public struct GoogleAccount: Sendable, Hashable, Codable {
    public var name: String?
    public var email: String?

    public init(name: String? = nil, email: String? = nil) {
        self.name = name
        self.email = email
    }

    /// "Jane Appleseed (jane@example.com)", or whichever half is known.
    public var displayName: String {
        switch (name, email) {
        case let (name?, email?): return "\(name) (\(email))"
        case let (name?, nil):    return name
        case let (nil, email?):   return email
        case (nil, nil):          return "Google account"
        }
    }
}
