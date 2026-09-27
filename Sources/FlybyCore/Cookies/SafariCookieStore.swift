import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// Reads Safari's `Cookies.binarycookies` file.
///
/// The format (as reverse-engineered by the `dtformats` project and mirrored by
/// yt-dlp): a `"cook"` magic, a big-endian page count and per-page sizes, then
/// pages. Each page starts with the signature `00 00 01 00`, a little-endian
/// cookie count and little-endian record offsets; each record carries flags,
/// four offsets to NUL-terminated domain/name/path/value strings, and two
/// little-endian Float64 timestamps (expiry and creation) counted in seconds
/// from the Mac reference date, 2001-01-01. The file ends with an 8-byte
/// checksum we don't need.
struct SafariCookieStore {
    let location: URL

    func read() throws -> [BrowserCookie] {
        let data: Data
        do {
            data = try Data(contentsOf: location, options: [.uncached])
        } catch {
            if let permission = CookieStoreSupport.fullDiskAccessError(from: error) {
                throw permission
            }
            let ns = error as NSError
            if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.Code.fileReadNoSuchFile.rawValue {
                throw CookieImportError.noProfiles(.safari)
            }
            #if canImport(Darwin)
            if ns.domain == NSPOSIXErrorDomain, ns.code == Int(ENOENT) {
                throw CookieImportError.noProfiles(.safari)
            }
            #endif
            if !FileManager.default.fileExists(atPath: location.path) {
                throw CookieImportError.noProfiles(.safari)
            }
            throw CookieImportError.unreadableStore(ns.localizedDescription)
        }
        return try Self.parse(data)
    }

    /// Parses a whole `binarycookies` blob. Exposed for tests.
    static func parse(_ data: Data) throws -> [BrowserCookie] {
        var reader = BinaryReader(data)

        guard try reader.readBytes(4) == Array("cook".utf8) else {
            throw CookieImportError.unsupportedFormat("missing binarycookies magic")
        }
        let pageCount = try reader.readUInt32BE()
        // Guard against a corrupt count asking us to allocate absurd amounts.
        guard pageCount <= 1_000_000 else {
            throw CookieImportError.unsupportedFormat("implausible page count \(pageCount)")
        }
        var pageSizes: [Int] = []
        pageSizes.reserveCapacity(Int(pageCount))
        for _ in 0 ..< pageCount {
            pageSizes.append(Int(try reader.readUInt32BE()))
        }

        var cookies: [BrowserCookie] = []
        for size in pageSizes {
            let page = try reader.readBytes(size)
            try parsePage(page, into: &cookies)
        }
        return cookies
    }

    private static func parsePage(_ page: [UInt8], into cookies: inout [BrowserCookie]) throws {
        var reader = BinaryReader(page)
        guard try reader.readBytes(4) == [0x00, 0x00, 0x01, 0x00] else {
            throw CookieImportError.unsupportedFormat("bad cookie page signature")
        }
        let cookieCount = try reader.readUInt32LE()
        guard cookieCount <= 1_000_000 else {
            throw CookieImportError.unsupportedFormat("implausible cookie count \(cookieCount)")
        }
        var offsets: [Int] = []
        offsets.reserveCapacity(Int(cookieCount))
        for _ in 0 ..< cookieCount {
            offsets.append(Int(try reader.readUInt32LE()))
        }
        for offset in offsets {
            try parseRecord(page, at: offset, into: &cookies)
        }
    }

    private static func parseRecord(_ page: [UInt8], at recordOffset: Int, into cookies: inout [BrowserCookie]) throws {
        guard recordOffset >= 0, recordOffset < page.count else {
            throw CookieImportError.unsupportedFormat("record offset out of bounds")
        }
        // Offsets inside a record are relative to the record's own start.
        var reader = BinaryReader(page, at: recordOffset)
        let recordSize = Int(try reader.readUInt32LE())
        guard recordSize >= 0, recordSize <= page.count - recordOffset else {
            throw CookieImportError.unsupportedFormat("record size out of bounds")
        }
        try reader.skip(4)                             // unknown field
        let flags = try reader.readUInt32LE()
        try reader.skip(4)                             // unknown field
        let domainOffset = Int(try reader.readUInt32LE())
        let nameOffset = Int(try reader.readUInt32LE())
        let pathOffset = Int(try reader.readUInt32LE())
        let valueOffset = Int(try reader.readUInt32LE())
        try reader.skip(8)                             // unknown field
        let expiry = try reader.readDoubleLE()
        _ = try reader.readDoubleLE()                  // creation date, unused

        let domain = try reader.cString(at: recordOffset + domainOffset)
        let name = try reader.cString(at: recordOffset + nameOffset)
        let path = try reader.cString(at: recordOffset + pathOffset)
        let value = try reader.cString(at: recordOffset + valueOffset)

        // Flags: 0x1 secure, 0x4 httpOnly.
        let isSecure = (flags & 0x1) != 0
        let isHTTPOnly = (flags & 0x4) != 0
        // Expiry of 0 (or a non-finite value) means a session cookie.
        let expires: Date? = (expiry > 0 && expiry.isFinite)
            ? Date(timeIntervalSinceReferenceDate: expiry)
            : nil

        cookies.append(BrowserCookie(
            name: name,
            value: value,
            domain: domain,
            path: path.isEmpty ? "/" : path,
            expires: expires,
            isSecure: isSecure,
            isHTTPOnly: isHTTPOnly,
            sameSite: nil))
    }
}
