import Foundation
import Testing
@testable import FlybyCore

#if canImport(Darwin)
import Darwin
#endif

@Suite struct SafariCookieStoreTests {
    @Test func parsesWrittenFileAcrossTwoPages() throws {
        // A dated, secure, httpOnly cookie on page one; a session cookie on two.
        let dated = SafariTestCookie(
            domain: ".google.com", name: "SID", path: "/", value: "signed-in",
            isSecure: true, isHTTPOnly: true, expiry: 700_000_000, creation: 600_000_000)
        let session = SafariTestCookie(
            domain: "www.google.co.uk", name: "PREF", path: "/search", value: "abc",
            isSecure: false, isHTTPOnly: false, expiry: 0)

        let data = SafariBinaryCookiesWriter.make(pages: [[dated], [session]])

        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        let file = directory.appendingPathComponent("Cookies.binarycookies")
        try data.write(to: file)

        let cookies = try SafariCookieStore(location: file).read()
        #expect(cookies.count == 2)

        let sid = try #require(cookies.first { $0.name == "SID" })
        #expect(sid.domain == ".google.com")
        #expect(sid.value == "signed-in")
        #expect(sid.isSecure)
        #expect(sid.isHTTPOnly)
        #expect(sid.expires == Date(timeIntervalSinceReferenceDate: 700_000_000))

        let pref = try #require(cookies.first { $0.name == "PREF" })
        #expect(pref.domain == "www.google.co.uk")
        #expect(pref.path == "/search")
        #expect(!pref.isSecure)
        #expect(pref.expires == nil)   // expiry 0 → session cookie
    }

    @Test func wrongMagicThrowsUnsupportedFormat() {
        let data = Data("XXXXnot a cookie file".utf8)
        CookieTestSupport.expectUnsupportedFormat { _ = try SafariCookieStore.parse(data) }
    }

    @Test func truncatedFileThrowsUnsupportedFormat() {
        // Valid magic and a page count of 1, but no page-size table follows.
        var data = Data("cook".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x01])   // pageCount = 1 (BE)
        CookieTestSupport.expectUnsupportedFormat { _ = try SafariCookieStore.parse(data) }
    }

    @Test func garbageNeverTraps() {
        // Random-ish bytes must throw, not crash.
        let data = Data((0 ..< 512).map { UInt8(($0 * 37 + 11) & 0xff) })
        CookieTestSupport.expectUnsupportedFormat { _ = try SafariCookieStore.parse(data) }
    }

    @Test func emptyDataThrowsUnsupportedFormat() {
        CookieTestSupport.expectUnsupportedFormat { _ = try SafariCookieStore.parse(Data()) }
    }

    #if canImport(Darwin)
    // chmod 000 only denies a non-root user; CI runs as one, but guard anyway.
    @Test(.enabled(if: getuid() != 0))
    func permissionDeniedMapsToFullDiskAccess() throws {
        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        let file = directory.appendingPathComponent("Cookies.binarycookies")
        let valid = SafariBinaryCookiesWriter.make(pages: [[
            SafariTestCookie(domain: ".google.com", name: "SID", path: "/", value: "x"),
        ]])
        try valid.write(to: file)

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        do {
            _ = try SafariCookieStore(location: file).read()
            Issue.record("expected a permission error")
        } catch {
            #expect(error as? CookieImportError == .fullDiskAccessRequired)
        }
    }
    #endif

    @Test func missingFileMapsToNoProfiles() {
        let missing = URL(fileURLWithPath: "/nonexistent/flyby/Cookies.binarycookies")
        do {
            _ = try SafariCookieStore(location: missing).read()
            Issue.record("expected noProfiles")
        } catch {
            #expect(error as? CookieImportError == .noProfiles(.safari))
        }
    }
}
