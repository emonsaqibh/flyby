import Foundation
import Testing
@testable import FlybyCore

#if canImport(SQLite3)
@Suite struct CookieImporterTests {
    @Test func googleCookiesFromFirefoxFiltersDomainsAndExpiry() throws {
        let home = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/Firefox")

        let profilesINI = """
        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/xxxx.default-release
        Default=1
        """
        try CookieTestSupport.write(Data(profilesINI.utf8), to: base.appendingPathComponent("profiles.ini"))

        let now = Int64(Date().timeIntervalSince1970)
        let future = now + 31_536_000   // +1 year
        let past = now - 86_400         // yesterday

        let rows = [
            FirefoxTestRow(host: ".google.com", name: "SID", value: "signed-in", expiry: future),
            FirefoxTestRow(host: "www.google.co.uk", name: "NID", value: "pref", expiry: future),
            FirefoxTestRow(host: "youtube.com", name: "YT", value: "nope", expiry: future),
            FirefoxTestRow(host: ".google.com", name: "OLD", value: "stale", expiry: past),
        ]
        // Schema 15 → expiry is seconds.
        try FirefoxTestDB.create(
            at: base.appendingPathComponent("Profiles/xxxx.default-release/cookies.sqlite"),
            schemaVersion: 15, rows: rows)

        let importer = CookieImporter(homeDirectory: home)
        let google = try importer.googleCookies(from: .firefox)

        let names = Set(google.map(\.name))
        #expect(names == ["SID", "NID"])           // youtube dropped, expired OLD dropped
        #expect(GoogleCookies.hasSignedInSession(google))
    }

    @Test func installedBrowsersFindsFirefoxProfile() throws {
        let home = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/Firefox")
        let profilesINI = """
        [Profile0]
        Name=default
        IsRelative=1
        Path=Profiles/yyyy.default
        Default=1
        """
        try CookieTestSupport.write(Data(profilesINI.utf8), to: base.appendingPathComponent("profiles.ini"))
        try FirefoxTestDB.create(
            at: base.appendingPathComponent("Profiles/yyyy.default/cookies.sqlite"),
            schemaVersion: 16, rows: [FirefoxTestRow(host: ".google.com", name: "SID", value: "x")])

        let importer = CookieImporter(homeDirectory: home)
        #expect(importer.installedBrowsers().contains(.firefox))
    }
}
#endif
