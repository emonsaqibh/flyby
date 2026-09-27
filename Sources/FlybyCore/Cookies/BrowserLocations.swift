import Foundation

/// Finds each browser's on-disk cookie store under a given home directory.
///
/// Every path is resolved against the injected `homeDirectory` (rather than the
/// process's real home) so the discovery logic can be exercised against a fake
/// home tree in tests.
struct BrowserLocations {
    let homeDirectory: URL

    func profiles(for browser: Browser) throws -> [BrowserProfile] {
        switch browser.engine {
        case .webKit:   return safariProfiles()
        case .chromium: return chromiumProfiles(for: browser)
        case .gecko:    return firefoxProfiles()
        }
    }

    // MARK: - Common roots

    private func applicationSupport() -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    // MARK: - Safari

    /// Safari has exactly one "profile". Its container is TCC-protected, so we
    /// can't rely on `fileExists` seeing it: treat Safari as present when the
    /// app is installed or any of its cookie paths is visible, and hand back a
    /// location the reader can try (mapping a permission failure to a Full Disk
    /// Access prompt).
    private func safariProfiles() -> [BrowserProfile] {
        let fm = FileManager.default
        let containerDir = homeDirectory.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies", isDirectory: true)
        let containerFile = containerDir.appendingPathComponent("Cookies.binarycookies")
        let legacyFile = homeDirectory.appendingPathComponent("Library/Cookies/Cookies.binarycookies")

        let legacyExists = fm.fileExists(atPath: legacyFile.path)
        let containerFileExists = fm.fileExists(atPath: containerFile.path)
        let containerDirExists = fm.fileExists(atPath: containerDir.path)
        let appInstalled = fm.fileExists(atPath: "/Applications/Safari.app")

        guard legacyExists || containerFileExists || containerDirExists || appInstalled else {
            return []
        }

        // yt-dlp reads the legacy path first when present, then the container.
        // With neither visible we still return the container path — TCC usually
        // hides it until Full Disk Access is granted.
        let location = legacyExists ? legacyFile : containerFile
        return [BrowserProfile(browser: .safari, name: "Safari", location: location)]
    }

    // MARK: - Chromium family

    /// Directory under `~/Library/Application Support` for each Chromium-based
    /// browser (verified against yt-dlp's `_get_chromium_based_browser_settings`;
    /// Arc from its own layout).
    private func chromiumSupportDirectory(for browser: Browser) -> String? {
        switch browser {
        case .chrome:   return "Google/Chrome"
        case .chromium: return "Chromium"
        case .brave:    return "BraveSoftware/Brave-Browser"
        case .edge:     return "Microsoft Edge"
        case .vivaldi:  return "Vivaldi"
        case .arc:      return "Arc/User Data"
        case .opera:    return "com.operasoftware.Opera"
        default:        return nil
        }
    }

    private func chromiumProfiles(for browser: Browser) -> [BrowserProfile] {
        guard let relative = chromiumSupportDirectory(for: browser) else { return [] }
        let base = applicationSupport().appendingPathComponent(relative, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return [] }

        let localState = readLocalState(base.appendingPathComponent("Local State"))

        func hasCookieStore(_ directory: URL) -> Bool {
            fm.fileExists(atPath: directory.appendingPathComponent("Cookies").path)
                || fm.fileExists(atPath: directory.appendingPathComponent("Network/Cookies").path)
        }

        // Directory name ("" = the base itself, for profile-less Opera) paired
        // with its location.
        var found: [(directory: String, url: URL)] = []
        if hasCookieStore(base) {
            found.append((directory: "", url: base))
        }
        if let entries = try? fm.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for entry in entries {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }
                if hasCookieStore(entry) {
                    found.append((directory: entry.lastPathComponent, url: entry))
                }
            }
        }
        guard !found.isEmpty else { return [] }

        func displayName(for directory: String) -> String {
            if directory.isEmpty { return browser.displayName }
            if let name = localState.names[directory], !name.isEmpty { return name }
            return directory
        }

        // Order: the last-used profile first, then "Default", then the rest by
        // directory name.
        func rank(_ directory: String) -> Int {
            if !localState.lastUsed.isEmpty, directory == localState.lastUsed { return 0 }
            if directory == "Default" { return 1 }
            return 2
        }
        let ordered = found.sorted { lhs, rhs in
            let rl = rank(lhs.directory), rr = rank(rhs.directory)
            return rl != rr ? rl < rr : lhs.directory < rhs.directory
        }
        return ordered.map { BrowserProfile(browser: browser, name: displayName(for: $0.directory), location: $0.url) }
    }

    private struct LocalStateInfo {
        var names: [String: String]
        var lastUsed: String
    }

    /// Reads Chrome's `Local State` for human profile names
    /// (`profile.info_cache.<dir>.name`) and the last-used profile
    /// (`profile.last_used`). Tolerates a missing or garbled file.
    private func readLocalState(_ url: URL) -> LocalStateInfo {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let json = object as? [String: Any] else {
            return LocalStateInfo(names: [:], lastUsed: "")
        }
        let profile = json["profile"] as? [String: Any]
        var names: [String: String] = [:]
        if let infoCache = profile?["info_cache"] as? [String: Any] {
            for (directory, value) in infoCache {
                if let entry = value as? [String: Any], let name = entry["name"] as? String {
                    names[directory] = name
                }
            }
        }
        return LocalStateInfo(names: names, lastUsed: (profile?["last_used"] as? String) ?? "")
    }

    // MARK: - Firefox

    private func firefoxProfiles() -> [BrowserProfile] {
        let fm = FileManager.default
        let base = applicationSupport().appendingPathComponent("Firefox", isDirectory: true)
        guard fm.fileExists(atPath: base.path) else { return [] }

        let profilesINI = parseINI(base.appendingPathComponent("profiles.ini"))
        // installs.ini records the default profile per install as `Default=<Path>`.
        let installsINI = parseINI(base.appendingPathComponent("installs.ini"))
        var defaultPaths: Set<String> = []
        for section in installsINI {
            if let path = section.values["Default"] { defaultPaths.insert(path) }
        }

        struct Candidate { var name: String; var url: URL; var isDefault: Bool }
        var candidates: [Candidate] = []

        for section in profilesINI where section.name.lowercased().hasPrefix("profile") {
            guard let path = section.values["Path"] else { continue }
            let isRelative = (section.values["IsRelative"] ?? "1") != "0"
            let directory = isRelative ? base.appendingPathComponent(path) : URL(fileURLWithPath: path)
            guard fm.fileExists(atPath: directory.appendingPathComponent("cookies.sqlite").path) else { continue }
            let name = section.values["Name"] ?? directory.lastPathComponent
            let isDefault = defaultPaths.contains(path) || section.values["Default"] == "1"
            candidates.append(Candidate(name: name, url: directory, isDefault: isDefault))
        }

        // Fallback when profiles.ini is missing or unreadable: glob Profiles/*.
        if candidates.isEmpty {
            let profilesDir = base.appendingPathComponent("Profiles", isDirectory: true)
            if let entries = try? fm.contentsOfDirectory(
                at: profilesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entry in entries where fm.fileExists(atPath: entry.appendingPathComponent("cookies.sqlite").path) {
                    candidates.append(Candidate(name: entry.lastPathComponent, url: entry, isDefault: false))
                }
            }
        }
        guard !candidates.isEmpty else { return [] }

        // Default profile first, otherwise keep the file order stable.
        let ordered = candidates.enumerated().sorted { lhs, rhs in
            lhs.element.isDefault != rhs.element.isDefault
                ? lhs.element.isDefault
                : lhs.offset < rhs.offset
        }
        return ordered.map { BrowserProfile(browser: .firefox, name: $0.element.name, location: $0.element.url) }
    }

    private struct INISection {
        var name: String
        var values: [String: String]
    }

    private func parseINI(_ url: URL) -> [INISection] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var sections: [INISection] = []
        var current: INISection?
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if let current { sections.append(current) }
                current = INISection(name: String(line.dropFirst().dropLast()), values: [:])
            } else if let equals = line.firstIndex(of: "=") {
                let key = String(line[line.startIndex ..< equals]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                current?.values[key] = value
            }
        }
        if let current { sections.append(current) }
        return sections
    }
}
