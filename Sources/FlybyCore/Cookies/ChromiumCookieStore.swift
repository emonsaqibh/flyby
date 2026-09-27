import Foundation

#if canImport(SQLite3)
import SQLite3
#endif

#if canImport(Security)
import Security
#endif

#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Reads cookies from a Chromium-family browser profile.
///
/// Chromium keeps cookies in a SQLite database. Values are either plaintext (an
/// empty `value` with the real data in `encrypted_value`) or AES-encrypted with
/// a key that Chromium stashes in the login Keychain under
/// "<Name> Safe Storage". We copy the database first (it is locked while the
/// browser runs), read the key from the Keychain, and decrypt.
///
/// The password source is injectable so tests can supply a known key instead of
/// prompting the real Keychain.
struct ChromiumCookieStore {
    let browser: Browser
    let profileDirectory: URL
    /// Yields the Chromium "Safe Storage" secret. Defaults to the login
    /// Keychain; overridden in tests.
    let password: @Sendable () throws -> String

    /// The initialiser the importer uses: reads the key from the Keychain.
    init(browser: Browser, profileDirectory: URL) {
        self.browser = browser
        self.profileDirectory = profileDirectory
        let account = ChromiumCookieStore.keychainAccount(for: browser)
        self.password = { try ChromiumCookieStore.keychainPassword(account: account, browser: browser) }
    }

    /// Test seam: supply the Safe Storage secret directly.
    init(browser: Browser, profileDirectory: URL, password: @escaping @Sendable () throws -> String) {
        self.browser = browser
        self.profileDirectory = profileDirectory
        self.password = password
    }

    func read() throws -> [BrowserCookie] {
        #if canImport(SQLite3)
        let cookieFile = try locateCookieFile()

        let tempDirectory = try SQLiteTempCopy.makeDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let copy: URL
        do {
            copy = try SQLiteTempCopy.copyDatabase(cookieFile, into: tempDirectory)
        } catch {
            if let permission = CookieStoreSupport.fullDiskAccessError(from: error) { throw permission }
            throw CookieImportError.unreadableStore((error as NSError).localizedDescription)
        }

        let database = try SQLiteConnection(path: copy.path)
        let metaVersion = readMetaVersion(database)

        // The key is derived at most once, and lazily — an all-plaintext store
        // (or an empty one) never touches the Keychain. A Keychain failure is
        // remembered so we don't prompt repeatedly.
        var derivedKey: Data?
        var keyFailure: Error?
        func key() throws -> Data {
            if let derivedKey { return derivedKey }
            if let keyFailure { throw keyFailure }
            do {
                let derived = try deriveKey(password: password())
                derivedKey = derived
                return derived
            } catch {
                keyFailure = error
                throw error
            }
        }

        let columns = database.columnNames(ofTable: "cookies")
        // Newer Chromium uses is_secure/is_httponly; older used secure/httponly;
        // samesite may be absent. Substitute literals so the column positions
        // stay fixed.
        let secureColumn = columns.contains("is_secure") ? "is_secure" : (columns.contains("secure") ? "secure" : "0")
        let httpOnlyColumn = columns.contains("is_httponly") ? "is_httponly" : (columns.contains("httponly") ? "httponly" : "0")
        let sameSiteColumn = columns.contains("samesite") ? "samesite" : "-1"
        let sql = """
        SELECT host_key, name, value, encrypted_value, path, expires_utc, \
        \(secureColumn), \(httpOnlyColumn), \(sameSiteColumn) FROM cookies
        """

        let statement = try database.prepare(sql)
        var cookies: [BrowserCookie] = []
        var encryptedCount = 0
        var decryptionFailures = 0

        while statement.step() {
            let host = statement.text(0) ?? ""
            let name = statement.text(1) ?? ""
            let plaintext = statement.text(2) ?? ""
            let encrypted = statement.blob(3)
            let path = statement.text(4) ?? "/"
            let expiresUTC = statement.int(5)
            let isSecure = statement.int(6) != 0
            let isHTTPOnly = statement.int(7) != 0
            let sameSiteRaw = statement.int(8)

            let value: String
            if !plaintext.isEmpty {
                value = plaintext
            } else if encrypted.isEmpty {
                value = ""
            } else {
                let prefix = String(bytes: encrypted.prefix(3), encoding: .ascii) ?? ""
                if prefix == "v10" || prefix == "v11" {
                    encryptedCount += 1
                    // A Keychain denial aborts the whole import.
                    let derived = try key()
                    if let decrypted = decrypt(encrypted, key: derived, dropHashPrefix: metaVersion >= 24) {
                        value = decrypted
                    } else {
                        decryptionFailures += 1
                        continue
                    }
                } else {
                    // Any other prefix is legacy 'old data' stored as plaintext
                    // (yt-dlp's macOS behaviour). Keep it if it's valid UTF-8.
                    guard let legacy = String(data: encrypted, encoding: .utf8) else { continue }
                    value = legacy
                }
            }

            cookies.append(BrowserCookie(
                name: name,
                value: value,
                domain: host,
                path: path.isEmpty ? "/" : path,
                expires: Self.expiry(expiresUTC),
                isSecure: isSecure,
                isHTTPOnly: isHTTPOnly,
                sameSite: Self.sameSite(sameSiteRaw)))
        }

        // If every encrypted cookie failed, the key was wrong (bad password).
        if encryptedCount > 0, decryptionFailures == encryptedCount {
            throw CookieImportError.decryptionFailed(browser)
        }
        return cookies
        #else
        throw CookieImportError.unsupportedFormat("SQLite unavailable on this platform")
        #endif
    }

    // MARK: - Locating the store

    /// Chrome 96+ moved the database to `<profile>/Network/Cookies`, keeping the
    /// old `<profile>/Cookies` as a fallback; when both linger, the newest wins.
    /// A `profileDirectory` that already points at a file is used directly.
    private func locateCookieFile() throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: profileDirectory.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            return profileDirectory
        }
        let network = profileDirectory.appendingPathComponent("Network/Cookies")
        let legacy = profileDirectory.appendingPathComponent("Cookies")
        let networkExists = fm.fileExists(atPath: network.path)
        let legacyExists = fm.fileExists(atPath: legacy.path)
        switch (networkExists, legacyExists) {
        case (true, true):   return modificationDate(network) >= modificationDate(legacy) ? network : legacy
        case (true, false):  return network
        case (false, true):  return legacy
        case (false, false): throw CookieImportError.noProfiles(browser)
        }
    }

    private func modificationDate(_ url: URL) -> Date {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else {
            return .distantPast
        }
        return date
    }

    // MARK: - Metadata

    #if canImport(SQLite3)
    /// `meta.version` — from Chromium's cookie schema version 24 the plaintext
    /// carries a 32-byte SHA-256(host_key) prefix that must be dropped.
    private func readMetaVersion(_ database: SQLiteConnection) -> Int {
        guard let statement = try? database.prepare("SELECT value FROM meta WHERE key = 'version'"),
              statement.step(), let text = statement.text(0), let version = Int(text) else {
            return 0
        }
        return version
    }
    #endif

    /// `expires_utc` is microseconds since 1601-01-01 UTC; 0 is a session cookie.
    static func expiry(_ raw: Int64) -> Date? {
        guard raw > 0 else { return nil }
        let microsecondsBetweenEpochs = 11_644_473_600_000_000.0
        return Date(timeIntervalSince1970: (Double(raw) - microsecondsBetweenEpochs) / 1_000_000.0)
    }

    static func sameSite(_ raw: Int64) -> BrowserCookie.SameSite? {
        switch raw {
        case 0:  return BrowserCookie.SameSite.none
        case 1:  return .lax
        case 2:  return .strict
        default: return nil   // -1 (unspecified) or anything unexpected
        }
    }

    // MARK: - Keychain

    /// The Keychain account/service stem for each browser ("<stem> Safe
    /// Storage" is the service). Verified against yt-dlp; Arc uses "Arc".
    static func keychainAccount(for browser: Browser) -> String {
        switch browser {
        case .chrome:   return "Chrome"
        case .chromium: return "Chromium"
        case .brave:    return "Brave"
        case .edge:     return "Microsoft Edge"
        case .vivaldi:  return "Vivaldi"
        case .arc:      return "Arc"
        case .opera:    return "Opera"
        default:        return browser.displayName
        }
    }

    static func keychainPassword(account: String, browser: Browser) throws -> String {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(account) Safe Storage",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw CookieImportError.keychainAccessDenied(browser)
            }
            return secret
        default:
            // errSecItemNotFound / errSecAuthFailed / errSecUserCanceled /
            // errSecInteractionNotAllowed, or anything else — the user either
            // declined the prompt or the item (e.g. Arc's) isn't there.
            throw CookieImportError.keychainAccessDenied(browser)
        }
        #else
        throw CookieImportError.unsupportedFormat("Keychain unavailable on this platform")
        #endif
    }

    // MARK: - Crypto

    /// PBKDF2-HMAC-SHA1(password, "saltysalt", 1003 iterations) → a 16-byte
    /// AES-128 key. The salt and iteration count are Chromium's on macOS.
    func deriveKey(password: String) throws -> Data {
        #if canImport(CommonCrypto)
        // CCKeyDerivationPBKDF wants the password as `char *`; bind it as Int8
        // so we never force-unwrap a base address (an empty password is legal
        // and yields a nil pointer with length 0).
        let passwordChars = password.utf8.map { Int8(bitPattern: $0) }
        let salt = Array("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: 16)
        let status = derived.withUnsafeMutableBufferPointer { derivedBuffer in
            passwordChars.withUnsafeBufferPointer { passwordBuffer -> Int32 in
                salt.withUnsafeBufferPointer { saltBuffer -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress, passwordChars.count,
                        saltBuffer.baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        derivedBuffer.baseAddress, 16)
                }
            }
        }
        guard status == Int32(kCCSuccess) else {
            throw CookieImportError.decryptionFailed(browser)
        }
        return Data(derived)
        #else
        throw CookieImportError.unsupportedFormat("CommonCrypto unavailable on this platform")
        #endif
    }

    /// AES-128-CBC/PKCS7 with a fixed IV of sixteen 0x20 bytes. Returns nil when
    /// decryption or UTF-8 decoding fails (a wrong key looks like garbage), so
    /// the caller can count the failure and skip the cookie.
    func decrypt(_ encryptedValue: Data, key: Data, dropHashPrefix: Bool) -> String? {
        #if canImport(CommonCrypto)
        let ciphertext = Data(encryptedValue.dropFirst(3))   // strip "v10"/"v11"
        guard !ciphertext.isEmpty else { return nil }
        let iv = Data(repeating: 0x20, count: 16)

        var output = [UInt8](repeating: 0, count: ciphertext.count + kCCBlockSizeAES128)
        var decryptedCount = 0
        let status = output.withUnsafeMutableBufferPointer { outputBuffer in
            ciphertext.withUnsafeBytes { cipherBuffer in
                key.withUnsafeBytes { keyBuffer in
                    iv.withUnsafeBytes { ivBuffer in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBuffer.baseAddress, key.count,
                            ivBuffer.baseAddress,
                            cipherBuffer.baseAddress, ciphertext.count,
                            outputBuffer.baseAddress, outputBuffer.count,
                            &decryptedCount)
                    }
                }
            }
        }
        guard status == Int32(kCCSuccess) else { return nil }

        var plaintext = output.prefix(decryptedCount)
        // Chromium schema >= 24 prepends SHA-256(host_key) to the plaintext.
        if dropHashPrefix {
            guard plaintext.count >= 32 else { return nil }
            plaintext = plaintext.dropFirst(32)
        }
        return String(bytes: plaintext, encoding: .utf8)
        #else
        return nil
        #endif
    }
}
