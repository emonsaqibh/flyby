import Foundation
import Testing
@testable import FlybyCore

@Suite struct ChromiumCookieStoreUnitTests {
    @Test func expiryConvertsMicrosecondsSince1601() {
        // 11,644,473,600 s is the 1601→1970 gap, so this is the Unix epoch.
        #expect(ChromiumCookieStore.expiry(11_644_473_600_000_000) == Date(timeIntervalSince1970: 0))
        // 2021-01-01T00:00:00Z.
        #expect(ChromiumCookieStore.expiry(13_253_932_800_000_000) == Date(timeIntervalSince1970: 1_609_459_200))
        #expect(ChromiumCookieStore.expiry(0) == nil)   // session cookie
    }

    @Test func sameSiteMapping() {
        #expect(ChromiumCookieStore.sameSite(-1) == nil)
        #expect(ChromiumCookieStore.sameSite(0) == BrowserCookie.SameSite.none)
        #expect(ChromiumCookieStore.sameSite(1) == .lax)
        #expect(ChromiumCookieStore.sameSite(2) == .strict)
    }
}

#if canImport(SQLite3) && canImport(CommonCrypto)
@Suite struct ChromiumCookieStoreDecryptionTests {
    private static let password = "flyby-safe-storage-secret"

    private func key() throws -> Data {
        try ChromiumCookieStore(
            browser: .chrome,
            profileDirectory: URL(fileURLWithPath: "/tmp"),
            password: { Self.password }
        ).deriveKey(password: Self.password)
    }

    @Test(arguments: [23, 24])
    func readsAndDecrypts(metaVersion: Int) throws {
        let key = try key()
        let expiresUTC: Int64 = 13_253_932_800_000_000   // 2021-01-01

        let encryptedSID = CryptoTestSupport.chromiumEncrypted(
            value: "session-token-\(metaVersion)", host: ".google.com", key: key, metaVersion: metaVersion)

        let rows = [
            ChromiumTestRow(
                host: ".google.com", name: "SID", encryptedValue: encryptedSID,
                expiresUTC: expiresUTC, isSecure: true, isHTTPOnly: true, sameSite: 1),
            ChromiumTestRow(
                host: "www.google.com", name: "PLAIN", plaintextValue: "hello",
                sameSite: 2),
        ]

        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        try ChromiumTestDB.create(
            at: directory.appendingPathComponent("Cookies"), metaVersion: metaVersion, rows: rows)

        let store = ChromiumCookieStore(
            browser: .chrome, profileDirectory: directory, password: { Self.password })
        let cookies = try store.read()

        let sid = try #require(cookies.first { $0.name == "SID" })
        #expect(sid.value == "session-token-\(metaVersion)")
        #expect(sid.isSecure)
        #expect(sid.isHTTPOnly)
        #expect(sid.sameSite == .lax)
        #expect(sid.expires == ChromiumCookieStore.expiry(expiresUTC))

        let plain = try #require(cookies.first { $0.name == "PLAIN" })
        #expect(plain.value == "hello")
        #expect(plain.sameSite == .strict)
    }

    @Test func readsFromNetworkCookiesLayout() throws {
        let rows = [ChromiumTestRow(
            host: ".google.com", name: "PLAIN", plaintextValue: "value")]

        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        try ChromiumTestDB.create(
            at: directory.appendingPathComponent("Network/Cookies"), metaVersion: 24, rows: rows)

        let store = ChromiumCookieStore(
            browser: .chrome, profileDirectory: directory, password: { Self.password })
        let cookies = try store.read()
        #expect(cookies.map(\.name) == ["PLAIN"])
    }

    @Test func wrongPasswordFailsDecryption() throws {
        let correctKey = try key()
        let encrypted = CryptoTestSupport.chromiumEncrypted(
            value: "a-fairly-long-session-token-value", host: ".google.com",
            key: correctKey, metaVersion: 23)
        let rows = [ChromiumTestRow(host: ".google.com", name: "SID", encryptedValue: encrypted)]

        let directory = try CookieTestSupport.makeTemporaryDirectory()
        defer { CookieTestSupport.remove(directory) }
        try ChromiumTestDB.create(
            at: directory.appendingPathComponent("Cookies"), metaVersion: 23, rows: rows)

        let store = ChromiumCookieStore(
            browser: .chrome, profileDirectory: directory, password: { "the-wrong-password" })
        do {
            _ = try store.read()
            Issue.record("expected decryptionFailed")
        } catch {
            #expect(error as? CookieImportError == .decryptionFailed(.chrome))
        }
    }

    @Test func keychainName() {
        #expect(ChromiumCookieStore.keychainAccount(for: .chrome) == "Chrome")
        #expect(ChromiumCookieStore.keychainAccount(for: .edge) == "Microsoft Edge")
        #expect(ChromiumCookieStore.keychainAccount(for: .brave) == "Brave")
        #expect(ChromiumCookieStore.keychainAccount(for: .arc) == "Arc")
        #expect(ChromiumCookieStore.keychainAccount(for: .opera) == "Opera")
        #expect(ChromiumCookieStore.keychainAccount(for: .vivaldi) == "Vivaldi")
        #expect(ChromiumCookieStore.keychainAccount(for: .chromium) == "Chromium")
    }
}
#endif
