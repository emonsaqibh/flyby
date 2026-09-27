import AppKit
import Combine
import FlybyCore
import os

/// Tells the user when a newer release is out, and how to install it.
///
/// Installing is always the README's one-line script, run in Terminal: the app
/// only checks and hands over the command. The script downloads with curl, so
/// the new copy isn't quarantined and opens without Gatekeeper's "could not
/// verify" block — which matters until releases are notarized.
///
/// Checks happen shortly after launch, every six hours while running, and when
/// the app comes back to the front after six hours or more. The time of the
/// last check is kept, so relaunching doesn't ask again. Off in the dev build,
/// which `./build.sh` replaces.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// The app's own public repository; each GitHub release carries the app as
    /// a zip, which `install.sh` downloads.
    static let repo = "emonsaqibh/flyby"

    /// The README's installer. Run in Terminal it quits Flyby, installs the
    /// newest release and reopens it; settings and the Google session are kept.
    static var installCommand: String {
        let base = "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/install.sh | bash"
        return Updater.shared.includesPrereleases ? base + " -s -- --beta" : base
    }

    static let checkInterval: TimeInterval = 6 * 60 * 60

    struct Release: Equatable {
        var version: SemanticVersion
        var notes: String
        var page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case failed(String)
    }

    @Published private(set) var available: Release?
    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date? {
        didSet { defaults.set(lastChecked, forKey: Keys.lastChecked) }
    }

    @Published var checksAutomatically: Bool {
        didSet {
            defaults.set(checksAutomatically, forKey: Keys.automatic)
            applyAutomaticChecks()
        }
    }

    /// Betas are GitHub pre-releases. Off by default: a release build should
    /// only ever be offered other releases unless the user opts in.
    @Published var includesPrereleases: Bool {
        didSet {
            defaults.set(includesPrereleases, forKey: Keys.prereleases)
            available = nil
            Task { await check() }
        }
    }

    /// Off in the dev build, which is replaced by rebuilding rather than updating.
    var isEnabled: Bool { !BuildFlavor.isDev }

    var currentVersion: SemanticVersion? { SemanticVersion(BuildFlavor.versionLabel) }

    private let defaults = UserDefaults.standard
    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "updates")

    private enum Keys {
        static let lastChecked = "updates.lastChecked"
        static let automatic = "updates.automatic"
        static let prereleases = "updates.includePrereleases"
    }

    private init() {
        lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
        checksAutomatically = defaults.object(forKey: Keys.automatic) as? Bool ?? true
        includesPrereleases = defaults.bool(forKey: Keys.prereleases)
    }

    // MARK: - Automatic checks

    private var timer: Task<Void, Never>?
    private var activation: NSObjectProtocol?

    /// Starts — or, with the setting off, stops — the automatic checks. Called
    /// once at launch; the setting's didSet calls it again.
    func applyAutomaticChecks() {
        timer?.cancel()
        timer = nil
        if let activation { NotificationCenter.default.removeObserver(activation) }
        activation = nil
        guard isEnabled, checksAutomatically else { return }

        timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(nanoseconds: UInt64(Self.checkInterval * 1_000_000_000))
            }
        }
        activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    private func checkIfDue() async {
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.checkInterval, available == nil {
            return
        }
        await check()
    }

    // MARK: - Checking

    /// Asks GitHub for the newest release. True when one newer than this build
    /// exists.
    @discardableResult
    func check() async -> Bool {
        guard isEnabled, state != .checking else { return available != nil }
        state = .checking
        do {
            let newest = try await Self.fetchNewest(includingPrereleases: includesPrereleases)
            lastChecked = Date()
            if let newest, let current = currentVersion, current < newest.version {
                if available != newest {
                    Self.log.info("update \(newest.version.description, privacy: .public) available (running \(current.description, privacy: .public))")
                }
                available = newest
                state = .idle
                return true
            }
            available = nil
            state = .upToDate
            return false
        } catch {
            state = .failed("Couldn’t reach GitHub. Check your connection and try again.")
            Self.log.error("update check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The highest-versioned published release that has the app zip attached
    /// (so the install command will work). Tags that aren't versions — the
    /// legacy `Golden` and `beta` releases — are ignored.
    private static func fetchNewest(includingPrereleases: Bool) async throws -> Release? {
        guard let list = try await getJSON("https://api.github.com/repos/\(repo)/releases?per_page=30")
                as? [[String: Any]] else { throw URLError(.cannotParseResponse) }

        let candidates: [(version: SemanticVersion, json: [String: Any])] = list.compactMap { release in
            guard release["draft"] as? Bool != true,
                  let tag = release["tag_name"] as? String,
                  let version = SemanticVersion(tag),
                  includingPrereleases || !version.isPrerelease
            else { return nil }
            return (version, release)
        }

        for candidate in candidates.sorted(by: { $0.version > $1.version }) {
            var assets = candidate.json["assets"] as? [[String: Any]] ?? []
            // GitHub sometimes lags filling in a release's embedded asset list;
            // its own assets endpoint is current.
            if !hasZip(assets), let id = candidate.json["id"] as? Int {
                assets = try await getJSON("https://api.github.com/repos/\(repo)/releases/\(id)/assets")
                    as? [[String: Any]] ?? []
            }
            guard hasZip(assets),
                  let page = (candidate.json["html_url"] as? String).flatMap(URL.init(string:))
            else { continue }
            return Release(version: candidate.version, notes: candidate.json["body"] as? String ?? "", page: page)
        }
        return nil
    }

    private static func hasZip(_ assets: [[String: Any]]) -> Bool {
        assets.contains { ($0["name"] as? String)?.hasSuffix(".zip") == true }
    }

    private static func getJSON(_ url: String) async throws -> Any {
        guard let url = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Installing (in Terminal)

    static func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
    }

    static func openTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
    }
}
