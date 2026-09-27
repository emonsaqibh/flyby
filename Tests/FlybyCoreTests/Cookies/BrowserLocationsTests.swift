import Foundation
import Testing
@testable import FlybyCore

@Suite struct BrowserLocationsTests {
    private func makeHome() throws -> URL {
        try CookieTestSupport.makeTemporaryDirectory()
    }

    private func touch(_ url: URL) throws {
        try CookieTestSupport.write(Data(), to: url)
    }

    // MARK: - Chromium

    @Test func chromeOrdersLastUsedProfileFirstAndNamesFromLocalState() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/Google/Chrome")

        try touch(base.appendingPathComponent("Default/Cookies"))
        // Newer Chrome keeps the store under Network/.
        try touch(base.appendingPathComponent("Profile 1/Network/Cookies"))

        let localState = """
        {"profile":{"last_used":"Profile 1","info_cache":{
            "Default":{"name":"Personal"},"Profile 1":{"name":"Work"}}}}
        """
        try CookieTestSupport.write(Data(localState.utf8), to: base.appendingPathComponent("Local State"))

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .chrome)
        #expect(profiles.map(\.name) == ["Work", "Personal"])
        #expect(profiles.first?.location.lastPathComponent == "Profile 1")
    }

    @Test func chromeFallsBackToDefaultFirstWithoutLocalState() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/Google/Chrome")
        try touch(base.appendingPathComponent("Default/Cookies"))
        try touch(base.appendingPathComponent("Profile 2/Cookies"))

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .chrome)
        #expect(profiles.first?.name == "Default")
        #expect(Set(profiles.map(\.name)) == ["Default", "Profile 2"])
    }

    @Test func braveUsesBraveSoftwarePath() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser")
        try touch(base.appendingPathComponent("Default/Cookies"))

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .brave)
        #expect(profiles.count == 1)
        #expect(profiles.first?.browser == .brave)
    }

    @Test func operaKeepsCookiesAtRoot() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/com.operasoftware.Opera")
        try touch(base.appendingPathComponent("Cookies"))

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .opera)
        #expect(profiles.count == 1)
        #expect(profiles.first?.location.lastPathComponent == "com.operasoftware.Opera")
    }

    @Test func absentBrowserReturnsNoProfiles() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        #expect(try BrowserLocations(homeDirectory: home).profiles(for: .chrome).isEmpty)
    }

    // MARK: - Firefox

    @Test func firefoxPutsDefaultProfileFirst() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let base = home.appendingPathComponent("Library/Application Support/Firefox")

        let profilesINI = """
        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/aaaa.default-release

        [Profile1]
        Name=alt
        IsRelative=1
        Path=Profiles/bbbb.alt
        """
        try CookieTestSupport.write(Data(profilesINI.utf8), to: base.appendingPathComponent("profiles.ini"))

        let installsINI = """
        [3A9C7B2D]
        Default=Profiles/aaaa.default-release
        Locked=1
        """
        try CookieTestSupport.write(Data(installsINI.utf8), to: base.appendingPathComponent("installs.ini"))

        try touch(base.appendingPathComponent("Profiles/aaaa.default-release/cookies.sqlite"))
        try touch(base.appendingPathComponent("Profiles/bbbb.alt/cookies.sqlite"))

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .firefox)
        #expect(profiles.map(\.name) == ["default-release", "alt"])
    }

    // MARK: - Safari

    @Test func safariPresentWhenContainerDirectoryExists() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let containerDir = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies")
        try FileManager.default.createDirectory(at: containerDir, withIntermediateDirectories: true)

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .safari)
        #expect(profiles.count == 1)
        #expect(profiles.first?.name == "Safari")
        #expect(profiles.first?.location == containerDir.appendingPathComponent("Cookies.binarycookies"))
    }

    @Test func safariPrefersLegacyPathWhenPresent() throws {
        let home = try makeHome()
        defer { CookieTestSupport.remove(home) }
        let legacy = home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        try touch(legacy)

        let profiles = try BrowserLocations(homeDirectory: home).profiles(for: .safari)
        #expect(profiles.first?.location == legacy)
    }
}
