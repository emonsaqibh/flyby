import Foundation
import Testing
@testable import FlybyCore

#if canImport(SQLite3)
import SQLite3
#endif

#if canImport(CommonCrypto)
import CommonCrypto
#endif

// Shared fixtures for the cookie tests: a temp-directory helper, an in-test
// Safari `binarycookies` writer, and (Darwin-only) SQLite database builders and
// crypto helpers that produce exactly what the stores expect to read back.

enum CookieTestSupport {
    /// A fresh, empty directory unique to one test. The caller removes it.
    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flyby-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Asserts a closure throws `CookieImportError.unsupportedFormat` (any
    /// detail), and never traps.
    static func expectUnsupportedFormat(_ body: () throws -> Void) {
        do {
            try body()
            Issue.record("expected unsupportedFormat, but nothing was thrown")
        } catch let error as CookieImportError {
            if case .unsupportedFormat = error { return }
            Issue.record("expected unsupportedFormat, got \(error)")
        } catch {
            Issue.record("expected CookieImportError, got \(error)")
        }
    }
}

// MARK: - Safari binarycookies writer

/// One cookie to encode into a test `binarycookies` file.
struct SafariTestCookie {
    var domain: String
    var name: String
    var path: String
    var value: String
    var isSecure = false
    var isHTTPOnly = false
    /// Mac absolute time (seconds since 2001-01-01); 0 means a session cookie.
    var expiry: Double = 0
    var creation: Double = 0
}

enum SafariBinaryCookiesWriter {
    private static func appendLE32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes.append(UInt8(value & 0xff))
        bytes.append(UInt8((value >> 8) & 0xff))
        bytes.append(UInt8((value >> 16) & 0xff))
        bytes.append(UInt8((value >> 24) & 0xff))
    }

    private static func appendBE32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes.append(UInt8((value >> 24) & 0xff))
        bytes.append(UInt8((value >> 16) & 0xff))
        bytes.append(UInt8((value >> 8) & 0xff))
        bytes.append(UInt8(value & 0xff))
    }

    private static func writeLE32(_ bytes: inout [UInt8], at offset: Int, _ value: UInt32) {
        bytes[offset] = UInt8(value & 0xff)
        bytes[offset + 1] = UInt8((value >> 8) & 0xff)
        bytes[offset + 2] = UInt8((value >> 16) & 0xff)
        bytes[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    private static func writeLEDouble(_ bytes: inout [UInt8], at offset: Int, _ value: Double) {
        let raw = value.bitPattern
        for i in 0 ..< 8 {
            bytes[offset + i] = UInt8((raw >> (UInt64(i) * 8)) & 0xff)
        }
    }

    private static func encodeRecord(_ cookie: SafariTestCookie) -> [UInt8] {
        let domain = Array(cookie.domain.utf8) + [0]
        let name = Array(cookie.name.utf8) + [0]
        let path = Array(cookie.path.utf8) + [0]
        let value = Array(cookie.value.utf8) + [0]

        let headerSize = 56
        let domainOffset = headerSize
        let nameOffset = domainOffset + domain.count
        let pathOffset = nameOffset + name.count
        let valueOffset = pathOffset + path.count
        let recordSize = valueOffset + value.count

        var bytes = [UInt8](repeating: 0, count: recordSize)
        writeLE32(&bytes, at: 0, UInt32(recordSize))
        let flags: UInt32 = (cookie.isSecure ? 0x1 : 0) | (cookie.isHTTPOnly ? 0x4 : 0)
        writeLE32(&bytes, at: 8, flags)
        writeLE32(&bytes, at: 16, UInt32(domainOffset))
        writeLE32(&bytes, at: 20, UInt32(nameOffset))
        writeLE32(&bytes, at: 24, UInt32(pathOffset))
        writeLE32(&bytes, at: 28, UInt32(valueOffset))
        writeLEDouble(&bytes, at: 40, cookie.expiry)
        writeLEDouble(&bytes, at: 48, cookie.creation)

        for (i, byte) in domain.enumerated() { bytes[domainOffset + i] = byte }
        for (i, byte) in name.enumerated() { bytes[nameOffset + i] = byte }
        for (i, byte) in path.enumerated() { bytes[pathOffset + i] = byte }
        for (i, byte) in value.enumerated() { bytes[valueOffset + i] = byte }
        return bytes
    }

    private static func encodePage(_ cookies: [SafariTestCookie]) -> [UInt8] {
        let records = cookies.map(encodeRecord)
        let headerSize = 4 + 4 + 4 * records.count + 4

        var offsets: [Int] = []
        var cursor = headerSize
        for record in records {
            offsets.append(cursor)
            cursor += record.count
        }

        var page: [UInt8] = [0x00, 0x00, 0x01, 0x00]
        appendLE32(&page, UInt32(records.count))
        for offset in offsets { appendLE32(&page, UInt32(offset)) }
        appendLE32(&page, 0)   // trailing header field, skipped by the reader
        for record in records { page += record }
        return page
    }

    /// Builds a valid `binarycookies` blob split across the given pages.
    static func make(pages: [[SafariTestCookie]]) -> Data {
        let encoded = pages.map(encodePage)
        var out: [UInt8] = Array("cook".utf8)
        appendBE32(&out, UInt32(encoded.count))
        for page in encoded { appendBE32(&out, UInt32(page.count)) }
        for page in encoded { out += page }
        out += [UInt8](repeating: 0, count: 8)   // checksum placeholder, ignored
        return Data(out)
    }
}

#if canImport(SQLite3)
/// A tiny wrapper for building test databases with the SQLite C API.
enum SQLiteTestDB {
    // Computed (not a stored global) so it doesn't trip Swift 6's
    // non-Sendable-global-state check; SQLITE_TRANSIENT tells SQLite to copy.
    static var transient: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    static func create(at url: URL) throws -> OpaquePointer {
        // SQLite creates the file but not its parent directories.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard rc == SQLITE_OK, let db else {
            throw CookieImportError.unreadableStore("could not create test database")
        }
        return db
    }

    static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CookieImportError.unreadableStore(String(cString: sqlite3_errmsg(db)))
        }
    }

    static func close(_ db: OpaquePointer) {
        sqlite3_close(db)
    }
}

/// A cookie row to insert into a Chromium test database.
struct ChromiumTestRow {
    var host: String
    var name: String
    var plaintextValue: String = ""
    var encryptedValue: Data = Data()
    var path: String = "/"
    var expiresUTC: Int64 = 0
    var isSecure: Bool = false
    var isHTTPOnly: Bool = false
    var sameSite: Int64 = -1
}

enum ChromiumTestDB {
    /// Creates a Chromium-shaped cookie database (meta.version + cookies table).
    static func create(at url: URL, metaVersion: Int, rows: [ChromiumTestRow]) throws {
        let db = try SQLiteTestDB.create(at: url)
        defer { SQLiteTestDB.close(db) }
        try SQLiteTestDB.exec(db, "CREATE TABLE meta (key TEXT, value TEXT)")
        try SQLiteTestDB.exec(db, "INSERT INTO meta (key, value) VALUES ('version', '\(metaVersion)')")
        try SQLiteTestDB.exec(db, """
        CREATE TABLE cookies (
            host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT,
            expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER, samesite INTEGER
        )
        """)
        for row in rows {
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO cookies
            (host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly, samesite)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CookieImportError.unreadableStore(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.host, -1, SQLiteTestDB.transient)
            sqlite3_bind_text(stmt, 2, row.name, -1, SQLiteTestDB.transient)
            sqlite3_bind_text(stmt, 3, row.plaintextValue, -1, SQLiteTestDB.transient)
            _ = row.encryptedValue.withUnsafeBytes { buffer in
                sqlite3_bind_blob(stmt, 4, buffer.baseAddress, Int32(buffer.count), SQLiteTestDB.transient)
            }
            sqlite3_bind_text(stmt, 5, row.path, -1, SQLiteTestDB.transient)
            sqlite3_bind_int64(stmt, 6, row.expiresUTC)
            sqlite3_bind_int64(stmt, 7, row.isSecure ? 1 : 0)
            sqlite3_bind_int64(stmt, 8, row.isHTTPOnly ? 1 : 0)
            sqlite3_bind_int64(stmt, 9, row.sameSite)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CookieImportError.unreadableStore("insert failed")
            }
        }
    }
}

/// A Firefox moz_cookies row.
struct FirefoxTestRow {
    var host: String
    var name: String
    var value: String
    var path: String = "/"
    var expiry: Int64 = 0
    var isSecure: Bool = false
    var isHTTPOnly: Bool = false
    var sameSite: Int64 = 0
}

enum FirefoxTestDB {
    static func create(at url: URL, schemaVersion: Int, rows: [FirefoxTestRow]) throws {
        let db = try SQLiteTestDB.create(at: url)
        defer { SQLiteTestDB.close(db) }
        try SQLiteTestDB.exec(db, "PRAGMA user_version = \(schemaVersion)")
        try SQLiteTestDB.exec(db, """
        CREATE TABLE moz_cookies (
            host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER,
            isSecure INTEGER, isHttpOnly INTEGER, sameSite INTEGER
        )
        """)
        for row in rows {
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO moz_cookies (host, name, value, path, expiry, isSecure, isHttpOnly, sameSite)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw CookieImportError.unreadableStore(String(cString: sqlite3_errmsg(db)))
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, row.host, -1, SQLiteTestDB.transient)
            sqlite3_bind_text(stmt, 2, row.name, -1, SQLiteTestDB.transient)
            sqlite3_bind_text(stmt, 3, row.value, -1, SQLiteTestDB.transient)
            sqlite3_bind_text(stmt, 4, row.path, -1, SQLiteTestDB.transient)
            sqlite3_bind_int64(stmt, 5, row.expiry)
            sqlite3_bind_int64(stmt, 6, row.isSecure ? 1 : 0)
            sqlite3_bind_int64(stmt, 7, row.isHTTPOnly ? 1 : 0)
            sqlite3_bind_int64(stmt, 8, row.sameSite)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw CookieImportError.unreadableStore("insert failed")
            }
        }
    }
}
#endif

#if canImport(CommonCrypto)
enum CryptoTestSupport {
    static func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    /// AES-128-CBC/PKCS7 with the same fixed IV Chromium uses.
    static func aesCBCEncrypt(_ plaintext: Data, key: Data) -> Data {
        let iv = Data(repeating: 0x20, count: 16)
        var output = [UInt8](repeating: 0, count: plaintext.count + kCCBlockSizeAES128)
        var moved = 0
        let status = output.withUnsafeMutableBufferPointer { outputBuffer in
            plaintext.withUnsafeBytes { plaintextBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, key.count,
                            ivBuffer.baseAddress,
                            plaintextBuffer.baseAddress, plaintext.count,
                            outputBuffer.baseAddress, outputBuffer.count,
                            &moved)
                    }
                }
            }
        }
        precondition(status == Int32(kCCSuccess), "test AES encryption failed")
        return Data(output.prefix(moved))
    }

    /// Produces a Chromium "v10" encrypted_value for `value`, including the
    /// 32-byte SHA-256(host) prefix when `metaVersion >= 24`.
    static func chromiumEncrypted(value: String, host: String, key: Data, metaVersion: Int) -> Data {
        var plaintext = Data()
        if metaVersion >= 24 {
            plaintext.append(sha256(Data(host.utf8)))
        }
        plaintext.append(Data(value.utf8))
        return Data("v10".utf8) + aesCBCEncrypt(plaintext, key: key)
    }
}
#endif
