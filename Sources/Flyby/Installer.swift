import AppKit
import os

/// Where Flyby lives on disk, and getting it somewhere it can actually work.
///
/// A menu-bar app has more riding on its location than most. `SMAppService`
/// registers a *path* for open-at-login, and Accessibility permission is bound
/// to the exact bundle it was granted to. Run the app straight off the disk
/// image and macOS hands it a randomised read-only mount — App Translocation —
/// so both of those break on the next launch, in ways that read as bugs in the
/// app rather than as "it's still on the DMG".
enum Installer {
    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "install")

    private static let declinedKey = "declinedInstallToApplications"

    /// Posted just before the installed copy is launched, so this one can let
    /// go of its hot key first — the two briefly overlap.
    static let willRelaunch = Notification.Name("FlybyInstallerWillRelaunch")
    /// The installed copy couldn't be launched, so this one has to carry on.
    static let relaunchDidFail = Notification.Name("FlybyInstallerRelaunchDidFail")

    static var bundleURL: URL { Bundle.main.bundleURL }

    private static var systemApplications: URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    private static var userApplications: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    private static var downloads: URL? {
        try? FileManager.default.url(
            for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
    }

    /// Gatekeeper's read-only shadow copy, used for quarantined apps launched
    /// from outside an Applications folder.
    static var isTranslocated: Bool {
        bundleURL.path.contains("/AppTranslocation/")
    }

    /// True for a disk image, a network share, or a USB stick — anywhere the
    /// bundle can vanish out from under the system.
    static var isOnRemovableVolume: Bool {
        if isTranslocated { return true }
        let values = try? bundleURL.resourceValues(
            forKeys: [.volumeIsReadOnlyKey, .volumeIsRemovableKey]
        )
        return values?.volumeIsReadOnly == true || values?.volumeIsRemovable == true
    }

    /// Either Applications folder counts, and so does any folder inside one —
    /// plenty of people file utilities under /Applications/Utilities or a
    /// folder of their own. All of them are real installs as far as Launch
    /// Services and login items are concerned.
    static var isInstalled: Bool {
        guard !isTranslocated else { return false }
        return [systemApplications, userApplications].contains { isInside($0) }
    }

    /// Where a DMG's contents or a zip usually end up when someone skips the
    /// drag to Applications.
    private static var isInDownloads: Bool {
        guard !isTranslocated, let downloads else { return false }
        return isInside(downloads)
    }

    private static func isInside(_ folder: URL) -> Bool {
        let folderPath = folder.resolvingSymlinksInPath().path
        let bundlePath = bundleURL.resolvingSymlinksInPath().path
        return bundlePath.hasPrefix(folderPath.hasSuffix("/") ? folderPath : folderPath + "/")
    }

    /// Nagging every `./build.sh --run` would be worse than the problem, so the
    /// prompt is limited to the placements that genuinely misbehave: a disk
    /// image or translocated copy, and the download folder.
    static var shouldOfferInstall: Bool {
        // The dev build lives in build/ and is replaced by every ./build.sh;
        // moving it anywhere would only strand a stale copy.
        guard !BuildFlavor.isDev else { return false }
        guard !isInstalled else { return false }
        guard !UserDefaults.standard.bool(forKey: declinedKey) else { return false }
        return isOnRemovableVolume || isInDownloads
    }

    /// `/Applications` when this account may write there, the per-user folder
    /// otherwise — a standard (non-admin) account can't install system-wide,
    /// and failing loudly there helps nobody.
    private static var destinationDirectory: URL {
        if FileManager.default.isWritableFile(atPath: systemApplications.path) { return systemApplications }
        return userApplications
    }

    enum InstallError: LocalizedError {
        case occupied(URL, bundleID: String?)

        var errorDescription: String? {
            switch self {
            case .occupied(let url, let bundleID):
                let what = bundleID.map { "a different app (\($0))" } ?? "something that isn't Flyby"
                return "\(url.path) is already \(what). Flyby won't replace it — rename or move it, then try again."
            }
        }
    }

    /// Copies the running bundle into an Applications folder and hands back
    /// where it landed. Copy, not move: the source is usually a read-only disk
    /// image, and a running bundle survives having its original trashed anyway.
    @discardableResult
    static func install() throws -> URL {
        let fm = FileManager.default
        let directory = destinationDirectory
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent(bundleURL.lastPathComponent, isDirectory: true)
        if fm.fileExists(atPath: destination.path) {
            // Only ever replace this same app: a name collision shouldn't cost
            // someone else's. Trash rather than delete, so even a wrong guess
            // is recoverable.
            let existing = bundleIdentifier(at: destination)
            guard existing != nil, existing == Bundle.main.bundleIdentifier else {
                throw InstallError.occupied(destination, bundleID: existing)
            }
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        try fm.copyItem(at: bundleURL, to: destination)
        clearQuarantine(at: destination)

        // A copy sitting in Downloads is just clutter once it's installed, so
        // it goes to the Trash — not deleted, in case it wasn't clutter after
        // all. A translocated or disk-image original isn't ours to touch.
        if isInDownloads {
            do {
                try fm.trashItem(at: bundleURL, resultingItemURL: nil)
            } catch {
                log.error("couldn't trash original: \(error.localizedDescription, privacy: .public)")
            }
        }

        log.info("installed to \(destination.path, privacy: .public)")
        return destination
    }

    /// Read from the plist directly: `Bundle(url:)` caches by path, and may
    /// remember whatever used to be there.
    private static func bundleIdentifier(at url: URL) -> String? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleIdentifier"] as? String
    }

    /// `copyItem` carries `com.apple.quarantine` across, and a quarantined app
    /// launched from anywhere Finder didn't move it to gets translocated again
    /// — straight back to the read-only mount this is meant to escape, with an
    /// install offer on every launch. The user already cleared Gatekeeper to
    /// get this copy running, so the attribute has done its job.
    private static func clearQuarantine(at url: URL) {
        let attribute = "com.apple.quarantine"
        var cleared = 0
        func clear(_ item: URL) {
            if removexattr(item.path, attribute, XATTR_NOFOLLOW) == 0 { cleared += 1 }
        }

        clear(url)
        if let contents = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let item as URL in contents { clear(item) }
        }
        let count = cleared
        log.info("cleared quarantine from \(count, privacy: .public) items")
    }

    /// Starts the installed copy and stands down. The new instance registers
    /// its own hot key, so the overlap lasts about as long as a launch.
    @MainActor
    static func relaunch(at url: URL) {
        NotificationCenter.default.post(name: willRelaunch, object: nil)

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            SingleInstance.replacingArgument,
            String(ProcessInfo.processInfo.processIdentifier),
        ]
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            let failure = error?.localizedDescription
            Task { @MainActor in
                if let failure {
                    log.error("relaunch failed: \(failure, privacy: .public)")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    NotificationCenter.default.post(name: relaunchDidFail, object: nil)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: - UI

    /// Asked once, at launch, before onboarding — moving the app afterwards
    /// would strand the Accessibility grant onboarding just walked through.
    ///
    /// True when the installed copy is being launched to take over. This copy
    /// quits once it has started, so the caller should set nothing else up —
    /// unless `relaunchDidFail` arrives.
    @MainActor
    @discardableResult
    static func offerInstallIfNeeded() -> Bool {
        guard shouldOfferInstall else { return false }

        let place: String
        if isTranslocated {
            place = "a temporary read-only copy macOS made of it"
        } else if isOnRemovableVolume {
            place = "the disk image"
        } else {
            place = "your Downloads folder"
        }

        let alert = NSAlert()
        alert.messageText = "Move Flyby to your Applications folder?"
        alert.informativeText = """
        Flyby is running from \(place), where macOS won't let it keep the things \
        it needs.

        Accessibility permission and “Open at login” are both tied to where the \
        app lives, so from here they'd stop working the next time you launch it.
        """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        NSApp.activate()
        let choice = alert.runModal()

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: declinedKey)
        }
        guard choice == .alertFirstButtonReturn else { return false }

        return performInstall()
    }

    /// Shared by the launch prompt and the Settings button. True when the
    /// installed copy is being launched and this one is about to quit.
    @MainActor
    @discardableResult
    static func performInstall() -> Bool {
        do {
            let destination = try install()
            relaunch(at: destination)
            return true
        } catch {
            log.error("install failed: \(error.localizedDescription, privacy: .public)")
            let failure = NSAlert()
            failure.messageText = "Couldn't move Flyby"
            failure.informativeText = """
            \(error.localizedDescription)

            You can drag it into Applications yourself — Finder is open at the app now.
            """
            failure.alertStyle = .warning
            NSApp.activate()
            failure.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
            return false
        }
    }
}
