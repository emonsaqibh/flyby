import Foundation

#if canImport(Darwin)
import Darwin
#endif

#if canImport(SQLite3)
import SQLite3
#endif

// Shared plumbing for the cookie stores: a bounds-checked binary reader, a
// thin read-only SQLite wrapper, a temp-copy helper, and the file-permission
// mapping that turns EPERM/EACCES into a Full Disk Access prompt.

enum CookieStoreSupport {
    /// A file read that failed for lack of permission is, on macOS, the
    /// Full-Disk-Access wall — Safari's container has always been fenced off,
    /// and since macOS 27 so are the other browsers' Application Support
    /// folders. Everything else is left for the caller to classify.
    static func fullDiskAccessError(from error: Error) -> CookieImportError? {
        func isPermission(_ e: NSError) -> Bool {
            if e.domain == NSCocoaErrorDomain,
               e.code == CocoaError.Code.fileReadNoPermission.rawValue {
                return true
            }
            #if canImport(Darwin)
            if e.domain == NSPOSIXErrorDomain,
               e.code == Int(EPERM) || e.code == Int(EACCES) {
                return true
            }
            #endif
            return false
        }
        let ns = error as NSError
        if isPermission(ns) { return .fullDiskAccessRequired }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError, isPermission(underlying) {
            return .fullDiskAccessRequired
        }
        return nil
    }
}

/// A cursor over a byte buffer that refuses to read past its end.
///
/// The Safari store is untrusted, hand-packed binary, so every read is
/// bounds-checked and a short or malformed file throws `.unsupportedFormat`
/// rather than trapping.
struct BinaryReader {
    private let bytes: [UInt8]
    private(set) var offset: Int

    init(_ data: Data, at offset: Int = 0) {
        self.bytes = [UInt8](data)
        self.offset = offset
    }

    init(_ bytes: [UInt8], at offset: Int = 0) {
        self.bytes = bytes
        self.offset = offset
    }

    var count: Int { bytes.count }

    mutating func seek(to newOffset: Int) throws {
        guard newOffset >= 0, newOffset <= bytes.count else {
            throw CookieImportError.unsupportedFormat("offset \(newOffset) out of bounds")
        }
        offset = newOffset
    }

    mutating func skip(_ n: Int) throws { try seek(to: offset + n) }

    mutating func readBytes(_ n: Int) throws -> [UInt8] {
        guard n >= 0, offset <= bytes.count, n <= bytes.count - offset else {
            throw CookieImportError.unsupportedFormat("read of \(n) bytes past end of data")
        }
        let slice = Array(bytes[offset ..< offset + n])
        offset += n
        return slice
    }

    mutating func readUInt32BE() throws -> UInt32 {
        let a = try readBytes(4)
        return (UInt32(a[0]) << 24) | (UInt32(a[1]) << 16) | (UInt32(a[2]) << 8) | UInt32(a[3])
    }

    mutating func readUInt32LE() throws -> UInt32 {
        let a = try readBytes(4)
        return UInt32(a[0]) | (UInt32(a[1]) << 8) | (UInt32(a[2]) << 16) | (UInt32(a[3]) << 24)
    }

    /// Reads a little-endian IEEE-754 double (Safari's Mac-absolute timestamps).
    mutating func readDoubleLE() throws -> Double {
        let a = try readBytes(8)
        var raw: UInt64 = 0
        for i in 0 ..< 8 {
            raw |= UInt64(a[i]) << (UInt64(i) * 8)
        }
        return Double(bitPattern: raw)
    }

    /// A NUL-terminated UTF-8 string starting at an absolute offset. Does not
    /// move the cursor, since the record's strings are addressed by offset.
    func cString(at start: Int) throws -> String {
        guard start >= 0, start <= bytes.count else {
            throw CookieImportError.unsupportedFormat("string offset \(start) out of bounds")
        }
        var end = start
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        guard end < bytes.count else {
            throw CookieImportError.unsupportedFormat("unterminated string")
        }
        guard let string = String(bytes: bytes[start ..< end], encoding: .utf8) else {
            throw CookieImportError.unsupportedFormat("string is not valid UTF-8")
        }
        return string
    }
}

/// Copies a SQLite store (and its WAL/journal side-cars) to a private temporary
/// directory. Browsers keep the live database locked while running, so we never
/// touch the original.
enum SQLiteTempCopy {
    static func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("flyby-cookies-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copies `source` into `directory` alongside any `-wal`/`-shm`/`-journal`
    /// files, and returns the path of the copy.
    static func copyDatabase(_ source: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        let base = source.lastPathComponent
        let destination = directory.appendingPathComponent(base)
        try fm.copyItem(at: source, to: destination)
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = source.deletingLastPathComponent().appendingPathComponent(base + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try? fm.copyItem(at: sidecar, to: directory.appendingPathComponent(base + suffix))
            }
        }
        return destination
    }
}

#if canImport(SQLite3)
/// A prepared statement that owns its handle and finalises it on deinit.
final class SQLiteStatement {
    fileprivate var handle: OpaquePointer?

    init(database: OpaquePointer?, sql: String) throws {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard rc == SQLITE_OK, let statement else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "prepare failed"
            sqlite3_finalize(statement)
            throw CookieImportError.unreadableStore(message)
        }
        self.handle = statement
    }

    deinit { sqlite3_finalize(handle) }

    /// Advances to the next row; `false` once the result set is exhausted.
    func step() -> Bool { sqlite3_step(handle) == SQLITE_ROW }

    func text(_ column: Int32) -> String? {
        guard let c = sqlite3_column_text(handle, column) else { return nil }
        return String(cString: c)
    }

    func int(_ column: Int32) -> Int64 { sqlite3_column_int64(handle, column) }

    func blob(_ column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(handle, column) else { return Data() }
        let count = sqlite3_column_bytes(handle, column)
        guard count > 0 else { return Data() }
        return Data(bytes: pointer, count: Int(count))
    }
}

/// A read-only connection to a (copied) cookie database.
final class SQLiteConnection {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var opened: OpaquePointer?
        var rc = sqlite3_open_v2(path, &opened, SQLITE_OPEN_READONLY, nil)
        // A WAL-mode database can refuse a read-only open when its shared-memory
        // file isn't present; fall back to read-write on our throwaway copy.
        if rc != SQLITE_OK {
            if opened != nil { sqlite3_close(opened); opened = nil }
            rc = sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE, nil)
        }
        guard rc == SQLITE_OK, let opened else {
            if opened != nil { sqlite3_close(opened) }
            throw CookieImportError.unreadableStore("cannot open cookie database")
        }
        sqlite3_busy_timeout(opened, 2000)
        self.handle = opened
    }

    deinit { if let handle { sqlite3_close(handle) } }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(database: handle, sql: sql)
    }

    /// `PRAGMA user_version` — Firefox's cookie DB schema number. 0 when it
    /// can't be read.
    func userVersion() -> Int64 {
        guard let statement = try? prepare("PRAGMA user_version"), statement.step() else { return 0 }
        return statement.int(0)
    }

    /// Column names of `table`. The table name is always a trusted literal from
    /// this module, so interpolating it into the PRAGMA is safe.
    func columnNames(ofTable table: String) -> Set<String> {
        guard let statement = try? prepare("PRAGMA table_info(\(table))") else { return [] }
        var names: Set<String> = []
        while statement.step() {
            if let name = statement.text(1) { names.insert(name) }
        }
        return names
    }
}
#endif
