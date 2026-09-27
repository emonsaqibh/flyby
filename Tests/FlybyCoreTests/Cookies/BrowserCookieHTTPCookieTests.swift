import Foundation
import Testing
@testable import FlybyCore

@Suite struct BrowserCookieHTTPCookieTests {
    @Test func mapsFieldsFlagsAndExpiry() throws {
        // Within 400 days: Foundation caps cookie lifetimes there (RFC 6265bis),
        // so a far-future date comes back clipped rather than as written.
        let expires = Date(timeIntervalSinceNow: 30 * 24 * 60 * 60).rounded()
        let cookie = BrowserCookie(
            name: "SID", value: "token", domain: ".google.com", path: "/",
            expires: expires, isSecure: true, isHTTPOnly: true, sameSite: .lax)

        let http = try #require(cookie.makeHTTPCookie())
        #expect(http.name == "SID")
        #expect(http.value == "token")
        #expect(http.domain == ".google.com")
        #expect(http.path == "/")
        #expect(http.isSecure)
        // Note: `isHTTPOnly` isn't asserted — whether HTTPCookie surfaces our
        // "HttpOnly" property key is undocumented, so we don't depend on it.
        let expiresDate = try #require(http.expiresDate)
        #expect(abs(expiresDate.timeIntervalSince(expires)) < 1)

        #if canImport(Darwin)
        #expect(http.sameSitePolicy == .sameSiteLax)
        #endif
    }

    /// Google's long-lived cookies (two years) come out capped at ~400 days.
    /// Harmless — Flyby re-imports long before that — but worth pinning, so a
    /// change in Foundation's behaviour shows up here rather than as a
    /// mystery sign-out.
    @Test func farFutureExpiryIsCappedByFoundation() throws {
        let cookie = BrowserCookie(
            name: "SID", value: "v", domain: ".google.com",
            expires: Date(timeIntervalSinceNow: 2 * 365 * 24 * 60 * 60))
        let http = try #require(cookie.makeHTTPCookie())
        let expiresDate = try #require(http.expiresDate)
        #expect(expiresDate <= Date(timeIntervalSinceNow: 401 * 24 * 60 * 60))
    }

    @Test func keepsHostOnlyDomain() throws {
        let cookie = BrowserCookie(name: "NID", value: "v", domain: "accounts.google.com")
        let http = try #require(cookie.makeHTTPCookie())
        #expect(http.domain == "accounts.google.com")
    }

    @Test func sessionCookieHasNoExpiry() throws {
        let cookie = BrowserCookie(name: "S", value: "v", domain: ".google.com")
        let http = try #require(cookie.makeHTTPCookie())
        #expect(http.expiresDate == nil)
    }
}

private extension Date {
    /// Whole seconds, so the round trip through HTTPCookie compares cleanly.
    func rounded() -> Date {
        Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate.rounded())
    }
}
