import Foundation

// CONTRACT — public surface of browser cookie import. The app codes against
// exactly these names; implementations live in the sibling files.

/// A cookie read out of a browser's on-disk store.
public struct BrowserCookie: Sendable, Hashable {
    public enum SameSite: String, Sendable, Hashable { case lax, strict, none }

    public var name: String
    public var value: String
    /// As stored, e.g. ".google.com" (domain cookie) or "www.google.com" (host-only).
    public var domain: String
    public var path: String
    /// `nil` for a session cookie.
    public var expires: Date?
    public var isSecure: Bool
    public var isHTTPOnly: Bool
    public var sameSite: SameSite?

    public init(
        name: String, value: String, domain: String, path: String = "/",
        expires: Date? = nil, isSecure: Bool = false, isHTTPOnly: Bool = false,
        sameSite: SameSite? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.expires = expires
        self.isSecure = isSecure
        self.isHTTPOnly = isHTTPOnly
        self.sameSite = sameSite
    }

    public var isExpired: Bool {
        guard let expires else { return false }
        return expires < Date()
    }
}

/// Browsers Flyby can borrow a Google session from.
public enum Browser: String, CaseIterable, Sendable, Identifiable, Codable {
    case safari, chrome, arc, brave, edge, vivaldi, chromium, opera, firefox

    public var id: String { rawValue }

    public enum Engine: Sendable { case webKit, chromium, gecko }

    public var displayName: String {
        switch self {
        case .safari:   return "Safari"
        case .chrome:   return "Google Chrome"
        case .arc:      return "Arc"
        case .brave:    return "Brave"
        case .edge:     return "Microsoft Edge"
        case .vivaldi:  return "Vivaldi"
        case .chromium: return "Chromium"
        case .opera:    return "Opera"
        case .firefox:  return "Firefox"
        }
    }

    /// For looking the app up with NSWorkspace (icon, "is it installed").
    public var bundleIdentifier: String {
        switch self {
        case .safari:   return "com.apple.Safari"
        case .chrome:   return "com.google.Chrome"
        case .arc:      return "company.thebrowser.Browser"
        case .brave:    return "com.brave.Browser"
        case .edge:     return "com.microsoft.edgemac"
        case .vivaldi:  return "com.vivaldi.Vivaldi"
        case .chromium: return "org.chromium.Chromium"
        case .opera:    return "com.operasoftware.Opera"
        case .firefox:  return "org.mozilla.firefox"
        }
    }

    public var engine: Engine {
        switch self {
        case .safari:  return .webKit
        case .firefox: return .gecko
        default:       return .chromium
        }
    }

    /// What reading this browser's cookies will ask the user for, so the UI can
    /// say it up front instead of springing a system prompt on them.
    public var permissionNote: String {
        switch engine {
        case .webKit:   return "Needs Full Disk Access — Safari keeps its cookies in a protected folder."
        case .chromium: return "macOS will ask to let Flyby use “\(displayName) Safe Storage” from your Keychain. On macOS 27 it may also need Full Disk Access."
        case .gecko:    return "Usually no permission needed — though macOS 27 may ask for Full Disk Access."
        }
    }
}

/// One profile of a multi-profile browser. Safari has exactly one.
public struct BrowserProfile: Sendable, Hashable, Identifiable {
    public var browser: Browser
    /// Human-facing name, e.g. "Default", "Profile 2", "Work".
    public var name: String
    /// The directory holding the cookie store (or, for Safari, the store file).
    public var location: URL

    public var id: String { browser.rawValue + ":" + location.path }

    public init(browser: Browser, name: String, location: URL) {
        self.browser = browser
        self.name = name
        self.location = location
    }
}

public enum CookieImportError: Error, Sendable, Equatable, LocalizedError {
    case browserNotInstalled(Browser)
    case noProfiles(Browser)
    /// The store sits behind a TCC boundary and reading it fails with EPERM
    /// until the user grants Full Disk Access. Safari's container has always
    /// been protected this way; since macOS 27 the same applies to other
    /// browsers' Application Support folders, so this is no longer Safari-only.
    case fullDiskAccessRequired
    /// The user denied the Keychain prompt, or the Safe Storage item is missing.
    case keychainAccessDenied(Browser)
    case unreadableStore(String)
    case unsupportedFormat(String)
    case decryptionFailed(Browser)

    public var errorDescription: String? {
        switch self {
        case .browserNotInstalled(let b):
            return "\(b.displayName) doesn't seem to be installed."
        case .noProfiles(let b):
            return "Couldn't find a \(b.displayName) profile with cookies."
        case .fullDiskAccessRequired:
            return "Flyby needs Full Disk Access to read this browser's cookies."
        case .keychainAccessDenied(let b):
            return "Flyby wasn't allowed to read “\(b.displayName) Safe Storage” from your Keychain."
        case .unreadableStore(let detail):
            return "Couldn't read the browser's cookie store (\(detail))."
        case .unsupportedFormat(let detail):
            return "The browser's cookie store is in a format Flyby doesn't understand (\(detail))."
        case .decryptionFailed(let b):
            return "Couldn't decrypt \(b.displayName)'s cookies."
        }
    }
}

/// Google's own cookie vocabulary: which domains count as Google, and which
/// cookie names prove a signed-in session.
public enum GoogleCookies {
    /// Cookies whose presence means "signed in to a Google account".
    public static let sessionCookieNames: Set<String> = [
        "SID", "__Secure-1PSID", "__Secure-3PSID",
    ]

    /// `google.com`, its subdomains, and Google's country domains
    /// (`google.co.uk`, `google.com.au`, `google.de`, …) — nothing else.
    /// Leading dots are ignored.
    public static func isGoogleDomain(_ domain: String) -> Bool {
        GoogleDomainMatcher.matches(domain)
    }

    public static func hasSignedInSession(_ cookies: [BrowserCookie]) -> Bool {
        cookies.contains { sessionCookieNames.contains($0.name) && !$0.isExpired && isGoogleDomain($0.domain) }
    }
}

/// Reads cookies out of installed browsers.
///
/// Synchronous and blocking (file I/O, SQLite, a possible Keychain prompt) —
/// call it off the main thread.
public struct CookieImporter: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    /// Browsers with a cookie store on disk for this user.
    public func installedBrowsers() -> [Browser] {
        Browser.allCases.filter { (try? profiles(for: $0))?.isEmpty == false }
    }

    /// Profiles with a cookie store, most likely-to-be-used first ("Default"
    /// before "Profile 1"; Firefox's default-release first).
    public func profiles(for browser: Browser) throws -> [BrowserProfile] {
        try BrowserLocations(homeDirectory: homeDirectory).profiles(for: browser)
    }

    /// Every unexpired cookie from `profile` (or the first profile) whose domain
    /// passes `domainFilter`.
    public func cookies(
        from browser: Browser,
        profile: BrowserProfile? = nil,
        where domainFilter: (String) -> Bool
    ) throws -> [BrowserCookie] {
        guard let profile = try profile ?? profiles(for: browser).first else {
            throw CookieImportError.noProfiles(browser)
        }
        let all: [BrowserCookie]
        switch browser.engine {
        case .webKit:   all = try SafariCookieStore(location: profile.location).read()
        case .chromium: all = try ChromiumCookieStore(browser: browser, profileDirectory: profile.location).read()
        case .gecko:    all = try FirefoxCookieStore(profileDirectory: profile.location).read()
        }
        return all.filter { !$0.isExpired && domainFilter($0.domain) }
    }

    /// Convenience: Google cookies only.
    public func googleCookies(from browser: Browser, profile: BrowserProfile? = nil) throws -> [BrowserCookie] {
        try cookies(from: browser, profile: profile, where: GoogleCookies.isGoogleDomain)
    }
}
