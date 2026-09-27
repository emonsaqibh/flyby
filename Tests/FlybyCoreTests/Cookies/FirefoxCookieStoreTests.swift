import Foundation
import Testing
@testable import FlybyCore

@Suite struct FirefoxCookieStoreUnitTests {
    @Test func expirySeconds() {
        // Schema < 16: value is seconds.
        #expect(FirefoxCookieStore.expiry(1_893_456_000, schemaVersion: 15)
            == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func expiryMilliseconds() {
        // Schema >= 16 (Firefox 142+): value is milliseconds.
        #expect(FirefoxCookieStore.expiry(1_893_456_000_000, schemaVersion: 16)
            == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func expiryMagnitudeFallbackWhenSchemaUnknown() {
        // Schema unreadable (0): a value beyond 10^11 must be milliseconds.
        #expect(FirefoxCookieStore.expiry(1_893_456_000_000, schemaVersion: 0)
            == Date(timeIntervalSince1970: 1_893_456_000))
        #expect(FirefoxCookieStore.expiry(1_893_456_000, schemaVersion: 0)
            == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func sessionExpiry() {
        #expect(FirefoxCookieStore.expiry(0, schemaVersion: 16) == nil)
    }

    @Test func sameSiteMapping() {
        #expect(FirefoxCookieStore.sameSite(0) == BrowserCookie.SameSite.none)
        #expect(FirefoxCookieStore.sameSite(1) == .lax)
        #expect(FirefoxCookieStore.sameSite(2) == .strict)
    }
}

#if canImport(SQLite3)
@Suite struct FirefoxCookieStoreTests {
    private func readSID(schema: Int, expiry: Int64) throws -> BrowserCookie {
        let rows = [FirefoxTestRow(
            host: ".google.com", name: "SID", value: "signed-in", path: "/",
            expiry: expiry, isSecure: true, isHTTPOnly: true, sameSite: 1)]

        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        try FirefoxTestDB.create(
            at: directory.appendingPathComponent("cookies.sqlite"), schemaVersion: schema, rows: rows)

        let cookies = try FirefoxCookieStore(profileDirectory: directory).read()
        return try #require(cookies.first { $0.name == "SID" })
    }

    @Test func readsSecondsExpiryForOldSchema() throws {
        let sid = try readSID(schema: 15, expiry: 1_893_456_000)
        #expect(sid.value == "signed-in")
        #expect(sid.isSecure)
        #expect(sid.isHTTPOnly)
        #expect(sid.sameSite == .lax)
        #expect(sid.expires == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func readsMillisecondsExpiryForSchema16() throws {
        let sid = try readSID(schema: 16, expiry: 1_893_456_000_000)
        #expect(sid.expires == Date(timeIntervalSince1970: 1_893_456_000))
    }

    @Test func missingDatabaseThrowsNoProfiles() throws {
        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        do {
            _ = try FirefoxCookieStore(profileDirectory: directory).read()
            Issue.record("expected noProfiles")
        } catch {
            #expect(error as? CookieImportError == .noProfiles(.firefox))
        }
    }
}
#endif
