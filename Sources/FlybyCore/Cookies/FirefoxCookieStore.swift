import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

/// Reads cookies from a Firefox profile's `cookies.sqlite`.
///
/// Firefox stores cookies in the clear, so no Keychain or decryption is needed
/// — just a copy of the (possibly locked) database and a single SELECT.
struct FirefoxCookieStore {
    let profileDirectory: URL

    func read() throws -> [BrowserCookie] {
        #if canImport(SQLite3)
        let source = cookieDatabaseURL()
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw CookieImportError.noProfiles(.firefox)
        }

        let tempDirectory = try SQLiteTempCopy.makeDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let copy: URL
        do {
            copy = try SQLiteTempCopy.copyDatabase(source, into: tempDirectory)
        } catch {
            if let permission = CookieStoreSupport.fullDiskAccessError(from: error) { throw permission }
            throw CookieImportError.unreadableStore((error as NSError).localizedDescription)
        }

        let database = try SQLiteConnection(path: copy.path)
        let schemaVersion = database.userVersion()

        let columns = database.columnNames(ofTable: "moz_cookies")
        let httpOnlyColumn = columns.contains("isHttpOnly") ? "isHttpOnly" : "0"
        let sameSiteColumn = columns.contains("sameSite") ? "sameSite" : "-1"
        let sql = """
        SELECT host, name, value, path, expiry, isSecure, \
        \(httpOnlyColumn), \(sameSiteColumn) FROM moz_cookies
        """

        let statement = try database.prepare(sql)
        var cookies: [BrowserCookie] = []
        while statement.step() {
            let host = statement.text(0) ?? ""
            let name = statement.text(1) ?? ""
            let value = statement.text(2) ?? ""
            let path = statement.text(3) ?? "/"
            let expiryRaw = statement.int(4)
            let isSecure = statement.int(5) != 0
            let isHTTPOnly = statement.int(6) != 0
            let sameSiteRaw = statement.int(7)

            cookies.append(BrowserCookie(
                name: name,
                value: value,
                domain: host,
                path: path.isEmpty ? "/" : path,
                expires: Self.expiry(expiryRaw, schemaVersion: schemaVersion),
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly,
                sameSite: Self.sameSite(sameSiteRaw)))
        }
        return cookies
        #else
        throw CookieImportError.unsupportedFormat("SQLite unavailable on this platform")
        #endif
    }

    /// `profileDirectory` normally names the profile folder, but tolerate it
    /// pointing straight at the database file.
    private func cookieDatabaseURL() -> URL {
        if profileDirectory.lastPathComponent == "cookies.sqlite" {
            return profileDirectory
        }
        return profileDirectory.appendingPathComponent("cookies.sqlite")
    }

    /// `expiry` was seconds since the Unix epoch until Firefox 142 (cookie DB
    /// schema 16), which switched to milliseconds. Trust the schema version;
    /// when it can't be read (0), fall back to a magnitude check — a plain
    /// seconds expiry can't plausibly exceed 10^11 (that's the year 5138).
    static func expiry(_ raw: Int64, schemaVersion: Int64) -> Date? {
        guard raw > 0 else { return nil }
        let seconds: Double
        if schemaVersion >= 16 {
            seconds = Double(raw) / 1000.0
        } else if schemaVersion <= 0, raw > 100_000_000_000 {
            seconds = Double(raw) / 1000.0
        } else {
            seconds = Double(raw)
        }
        return Date(timeIntervalSince1970: seconds)
    }

    static func sameSite(_ raw: Int64) -> BrowserCookie.SameSite? {
        switch raw {
        case 0:  return BrowserCookie.SameSite.none
        case 1:  return .lax
        case 2:  return .strict
        default: return nil
        }
    }
}
