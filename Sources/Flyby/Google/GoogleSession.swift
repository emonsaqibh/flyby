import AppKit
import WebKit
import os
import FlybyCore

private let sessionLog = Logger(subsystem: "com.fringecore.flyby", category: "google-session")

/// The Google identity Flyby's embedded web views run as.
///
/// Google throws CAPTCHAs at anonymous, cookie-less clients. Running AI Mode
/// inside the user's real, signed-in session — borrowed from their browser, or
/// signed into once inside Flyby — is what makes it behave like their browser
/// does. Every Google web view shares `dataStore`, so a session established
/// once is used everywhere.
@MainActor
final class GoogleSession: ObservableObject {
    static let shared = GoogleSession()

    enum Method: Equatable, Codable {
        /// Cookies copied from a browser's store; refreshed from it periodically.
        case browser(Browser)
        /// Signed in through Flyby's own sign-in window.
        case inApp
    }

    enum Connection: Equatable {
        case notConnected
        case connected(Method, account: GoogleAccount?)
    }

    /// Something the user has to act on. Drawn inline by Settings/Onboarding.
    enum Problem: Equatable {
        case needsFullDiskAccess
        case keychainDenied(Browser)
        /// The browser has no signed-in Google session to borrow.
        case notSignedIn(Browser)
        case failed(String)
    }

    @Published private(set) var connection: Connection = .notConnected
    /// Non-nil while an import or verification is in flight.
    @Published private(set) var busyWith: Browser?
    @Published private(set) var problem: Problem?

    /// Persistent, dedicated to Flyby, shared by every Google web view.
    ///
    /// Its own store rather than `.default()`: disconnecting can then wipe it
    /// without touching anything else, and nothing else can leave cookies in
    /// it. WebKit keeps it per app bundle, so the dev and release builds each
    /// get their own.
    let dataStore: WKWebsiteDataStore

    /// Copying cookies out of Chrome, Arc, Brave, Edge and friends is off.
    /// Chrome's device-bound session credentials tie Google's session cookies
    /// to the Mac's secure hardware, so a copy dies within hours; and an
    /// ad-hoc signed Flyby launched normally is refused the "Safe Storage"
    /// Keychain item without even a prompt. Re-enable once builds are
    /// Developer ID signed and re-tested with a normal launch — the import
    /// path itself is intact.
    static let chromiumImportEnabled = false

    /// Bumped whenever the cookies in `dataStore` change hands, so a page
    /// loaded under the old session can't report on the new one.
    private(set) var cookieGeneration = 0

    /// Safari and Firefox rotate `__Secure-1PSIDTS` and friends; so does
    /// Google's own script running in our page, which forks the session away
    /// from the browser's. Re-reading the browser this often keeps Flyby
    /// following the browser's copy. It's a local file read, never a prompt.
    private static let refreshInterval: TimeInterval = 30 * 60

    private static let storeIdentifier = UUID(uuid: (
        0x4F, 0x6C, 0x9B, 0x2A, 0x3D, 0x1E, 0x4A, 0x7B,
        0x9C, 0x55, 0x0E, 0x2F, 0x8A, 0x61, 0xD3, 0xB7
    ))

    static let signInURLString = "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fwww.google.com%2F"

    private enum Keys {
        static let method = "google.method"
        static let lastImport = "google.lastImport"
        static let account = "google.account"
    }

    private enum ImportMode { case connect, refresh }

    /// What to retry when the user comes back from System Settings.
    private enum PendingAccessRetry { case connect(Browser), refresh(Browser) }

    private enum ImportFailure: Error {
        case cookies(CookieImportError)
        case other(String)
    }

    private var lastImport: Date?
    private var lastRefreshAttempt: Date?
    private var isRefreshing = false
    /// A signed-out page gets one silent re-import per launch before the user
    /// is told.
    private var triedSilentRecovery = false
    private var pendingAccessRetry: PendingAccessRetry?
    private var signInWindow: GoogleSignInWindow?
    private var browserCache: (browsers: [Browser], at: Date)?
    private var activationObserver: NSObjectProtocol?

    init() {
        dataStore = WKWebsiteDataStore(forIdentifier: GoogleSession.storeIdentifier)

        let defaults = UserDefaults.standard
        if let method = Self.storedMethod(in: defaults) {
            lastImport = defaults.object(forKey: Keys.lastImport) as? Date
            connection = .connected(method, account: Self.storedAccount(in: defaults))
            Task { [weak self] in await self?.verifyStoredSession() }
        }

        // Full Disk Access takes effect without a relaunch, and the user comes
        // back from System Settings expecting it to just work.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.applicationDidBecomeActive() }
        }
    }

    var isConnected: Bool {
        if case .connected = connection { return true }
        return false
    }

    /// Browsers with a cookie store on this Mac, in a sensible order (the
    /// user's default browser first).
    ///
    /// Only Safari and Firefox while `chromiumImportEnabled` is off, the
    /// default first if it's one of them; Chromium browsers would follow, the
    /// default one leading. Detection asks Launch Services whether the app is
    /// installed rather than probing cookie stores, because on current macOS
    /// merely looking into another app's data can raise a system prompt, and
    /// this is read every time Settings draws.
    var availableBrowsers: [Browser] {
        if let cache = browserCache, Date().timeIntervalSince(cache.at) < 30 {
            return cache.browsers
        }
        let installed = Browser.allCases.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier) != nil
        }
        let browsers = Self.order(installed, defaultBrowser: Self.defaultBrowser())
        browserCache = (browsers, Date())
        return browsers
    }

    /// A line the UI shows next to a browser that works, but not well.
    func caveat(for browser: Browser) -> String? {
        switch browser.engine {
        case .chromium:
            return "\(browser.displayName) ties Google sign-in to this Mac, so a copied session only lasts a few hours. Safari or Firefox work best."
        case .webKit, .gecko:
            return nil
        }
    }

    /// Copies the browser's Google cookies into `dataStore`. On failure sets
    /// `problem` and leaves any existing connection alone.
    func connect(using browser: Browser) async {
        guard busyWith == nil else { return }
        busyWith = browser
        problem = nil
        signInWindow?.close()
        await importCookies(from: browser, mode: .connect)
        busyWith = nil
    }

    /// Opens Flyby's own Google sign-in window, backed by `dataStore`.
    ///
    /// Best effort: Google refuses sign-in from embedded browsers for many
    /// accounts. The window notices and says so, and `problem` points the user
    /// at a browser instead.
    func signInWithinFlyby() {
        if let window = signInWindow {
            window.show()
            return
        }
        let window = GoogleSignInWindow(dataStore: dataStore)
        window.onSignedIn = { [weak self] account in
            self?.adopt(.inApp, account: account)
            sessionLog.info("Signed in within Flyby")
        }
        window.onRejected = { [weak self] in
            self?.problem = .failed(GoogleSignInWindow.rejectionMessage)
        }
        window.onClose = { [weak self] in
            self?.signInWindow = nil
        }
        signInWindow = window
        window.show()
    }

    /// Opens Google's sign-in page in `browser`, for when it has no session to
    /// borrow yet (`.notSignedIn`).
    func openSignInPage(in browser: Browser) {
        guard let url = URL(string: Self.signInURLString) else { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleIdentifier) {
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// Removes every Google cookie from `dataStore` and forgets the method.
    func disconnect() async {
        signInWindow?.close()
        let store = dataStore.httpCookieStore
        for cookie in await store.flybyAllCookies() where GoogleCookies.isGoogleDomain(cookie.domain) {
            await store.flybyDeleteCookie(cookie)
        }
        // Local storage, caches and the like; YouTube's too, since Google's
        // sign-in sets its session there as well.
        let records = await dataStore.flybyDataRecords().filter { record in
            let name = record.displayName.lowercased()
            return name.contains("google") || name.contains("youtube")
        }
        if !records.isEmpty {
            await dataStore.flybyRemoveData(for: records)
        }
        lastImport = nil
        lastRefreshAttempt = nil
        triedSilentRecovery = false
        pendingAccessRetry = nil
        cookieGeneration += 1
        connection = .notConnected
        problem = nil
        persist()
        sessionLog.info("Disconnected from Google")
    }

    /// Re-imports from the connected browser if the copy is old, so a session
    /// the browser has since rotated doesn't go stale here. Cheap to call; the
    /// app calls it at launch and before AI Mode searches. Never prompts.
    ///
    /// Safari and Firefox only. A Chromium import can raise a Keychain prompt,
    /// which must never appear out of nowhere; those are only re-imported when
    /// the user asks.
    func refreshIfStale() async {
        guard case .connected(.browser(let browser), _) = connection,
              browser.engine != .chromium, busyWith == nil, !isRefreshing else { return }
        let now = Date()
        if let lastImport, now.timeIntervalSince(lastImport) < Self.refreshInterval { return }
        // A browser that can't be read right now shouldn't be re-read before
        // every single search.
        if let lastRefreshAttempt, now.timeIntervalSince(lastRefreshAttempt) < Self.refreshInterval { return }
        await refresh(from: browser)
    }

    /// The AI Mode page reports who it's signed in as (or that it isn't).
    func noteAccount(_ account: GoogleAccount?, signedIn: Bool) {
        guard busyWith == nil, !isRefreshing else { return }

        if signedIn {
            switch connection {
            case .notConnected:
                // Signed in on the page itself — a sign-in wall AI Mode
                // revealed, completed in place.
                sessionLog.info("The page is signed in; keeping it as an in-app session")
                adopt(.inApp, account: account)
            case .connected(let method, let known):
                if let account, account != known {
                    connection = .connected(method, account: account)
                    persist()
                }
                if problem == .failed(Self.expiredMessage(for: method)) { problem = nil }
            }
            return
        }

        guard case .connected(let method, _) = connection else { return }
        let expired = Problem.failed(Self.expiredMessage(for: method))
        guard problem != expired else { return }
        sessionLog.info("The page says it's signed out")
        if case .browser(let browser) = method, browser.engine != .chromium, !triedSilentRecovery {
            triedSilentRecovery = true
            Task { [weak self] in
                guard let self else { return }
                if await self.refresh(from: browser) { return }
                self.problem = expired
            }
        } else {
            problem = expired
        }
    }

    func clearProblem() { problem = nil }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// True when `cookies` hold an unexpired Google sign-in.
    static func hasSession(_ cookies: [HTTPCookie]) -> Bool {
        let now = Date()
        return cookies.contains { cookie in
            GoogleCookies.sessionCookieNames.contains(cookie.name)
                && GoogleCookies.isGoogleDomain(cookie.domain)
                && (cookie.expiresDate.map { $0 > now } ?? true)
        }
    }

    // MARK: - Importing

    @discardableResult
    private func refresh(from browser: Browser) async -> Bool {
        guard !isRefreshing, busyWith == nil else { return false }
        isRefreshing = true
        lastRefreshAttempt = Date()
        let refreshed = await importCookies(from: browser, mode: .refresh)
        isRefreshing = false
        if refreshed { sessionLog.info("Refreshed the Google session from \(browser.rawValue, privacy: .public)") }
        return refreshed
    }

    /// `.connect` is the user asking: every failure is surfaced, and cookies
    /// the browser doesn't have are cleared out, so switching browsers or
    /// accounts leaves nothing of the old session behind.
    ///
    /// `.refresh` is silent: only a lost Full Disk Access grant is worth
    /// telling the user about, and cookies are only overwritten, never
    /// removed — Google's page sets some of its own here (a solved CAPTCHA's
    /// exemption, for one) that the browser never had.
    @discardableResult
    private func importCookies(from browser: Browser, mode: ImportMode) async -> Bool {
        switch await Self.readCookies(from: browser) {
        case .success(let cookies):
            guard GoogleCookies.hasSignedInSession(cookies) else {
                sessionLog.info("\(browser.rawValue, privacy: .public) has no signed-in Google session")
                if mode == .connect { problem = .notSignedIn(browser) }
                return false
            }
            if mode == .refresh {
                // The user may have connected something else meanwhile.
                guard busyWith == nil, case .connected(.browser(let current), _) = connection, current == browser else {
                    return false
                }
            }
            await install(cookies, removingOthers: mode == .connect)
            pendingAccessRetry = nil
            adopt(.browser(browser))
            sessionLog.info("Imported \(cookies.count, privacy: .public) Google cookies from \(browser.rawValue, privacy: .public)")
            return true

        case .failure(let failure):
            let problem = Self.mapFailure(failure)
            sessionLog.error("Couldn't import from \(browser.rawValue, privacy: .public): \(String(describing: problem), privacy: .private)")
            if problem == .needsFullDiskAccess {
                pendingAccessRetry = mode == .connect ? .connect(browser) : .refresh(browser)
                self.problem = problem
            } else if mode == .connect {
                self.problem = problem
            }
            return false
        }
    }

    /// Blocking file I/O (and, for Chromium, a possible Keychain prompt), so
    /// it runs off the main actor.
    private static func readCookies(from browser: Browser) async -> Result<[BrowserCookie], ImportFailure> {
        await Task.detached(priority: .userInitiated) { () -> Result<[BrowserCookie], ImportFailure> in
            do {
                return .success(try CookieImporter().googleCookies(from: browser))
            } catch let error as CookieImportError {
                return .failure(.cookies(error))
            } catch {
                return .failure(.other(error.localizedDescription))
            }
        }.value
    }

    private static func mapFailure(_ failure: ImportFailure) -> Problem {
        switch failure {
        case .cookies(.fullDiskAccessRequired):          return .needsFullDiskAccess
        case .cookies(.keychainAccessDenied(let browser)): return .keychainDenied(browser)
        case .cookies(let error):                         return .failed(error.localizedDescription)
        case .other(let message):                         return .failed(message)
        }
    }

    /// Sets the imported cookies first and removes stale ones after, so a
    /// page loading meanwhile never sees the store without a session.
    private func install(_ imported: [BrowserCookie], removingOthers: Bool) async {
        let store = dataStore.httpCookieStore
        let fresh = imported.compactMap { $0.makeHTTPCookie() }
        var existing: [HTTPCookie] = []
        if removingOthers {
            existing = await store.flybyAllCookies().filter { GoogleCookies.isGoogleDomain($0.domain) }
        }
        for cookie in fresh {
            await store.flybySetCookie(cookie)
        }
        guard removingOthers else { return }
        let keep = Set(fresh.map(CookieKey.init))
        for cookie in existing where !keep.contains(CookieKey(cookie)) {
            await store.flybyDeleteCookie(cookie)
        }
    }

    /// Cookie identity as the store sees it. Host-only and domain cookies are
    /// deliberately conflated: a stale one surviving is harmless, deleting
    /// the one just set is not.
    private struct CookieKey: Hashable {
        let name: String
        let domain: String
        let path: String

        init(_ cookie: HTTPCookie) {
            name = cookie.name
            let domain = cookie.domain.lowercased()
            self.domain = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            path = cookie.path.isEmpty ? "/" : cookie.path
        }
    }

    // MARK: - State

    private func adopt(_ method: Method, account: GoogleAccount? = nil) {
        var known = account
        if known == nil, case .connected(let current, let currentAccount) = connection, current == method {
            known = currentAccount
        }
        connection = .connected(method, account: known)
        if case .browser = method {
            lastImport = Date()
        } else {
            lastImport = nil
        }
        cookieGeneration += 1
        problem = nil
        persist()
    }

    /// A session restored from last launch may have been cleared or expired
    /// since. Safari and Firefox can be re-read quietly; anything else is the
    /// user's call.
    private func verifyStoredSession() async {
        guard case .connected(let method, _) = connection else { return }
        let cookies = await dataStore.httpCookieStore.flybyAllCookies()
        guard !Self.hasSession(cookies) else { return }
        sessionLog.info("The stored Google session is gone")
        if case .browser(let browser) = method, browser.engine != .chromium, await refresh(from: browser) {
            return
        }
        cookieGeneration += 1
        connection = .notConnected
        problem = .failed(Self.expiredMessage(for: method))
        persist()
    }

    private func applicationDidBecomeActive() async {
        browserCache = nil
        guard problem == .needsFullDiskAccess, let retry = pendingAccessRetry,
              busyWith == nil, !isRefreshing else { return }
        switch retry {
        case .connect(let browser):
            busyWith = browser
            await importCookies(from: browser, mode: .connect)
            busyWith = nil
        case .refresh(let browser):
            await refresh(from: browser)
        }
    }

    private static func expiredMessage(for method: Method) -> String {
        switch method {
        case .browser(let browser): return "Your Google session from \(browser.displayName) expired — reconnect"
        case .inApp:                return "Your Google sign-in in Flyby expired — sign in again"
        }
    }

    // MARK: - Browsers

    private static func order(_ installed: [Browser], defaultBrowser: Browser?) -> [Browser] {
        let borrowable = installed.filter { $0.engine != .chromium }
        var ordered = borrowable
        if let defaultBrowser, let index = ordered.firstIndex(of: defaultBrowser) {
            ordered.remove(at: index)
            ordered.insert(defaultBrowser, at: 0)
        }
        guard chromiumImportEnabled else { return ordered }
        var chromium = installed.filter { $0.engine == .chromium }
        if let defaultBrowser, let index = chromium.firstIndex(of: defaultBrowser) {
            chromium.remove(at: index)
            chromium.insert(defaultBrowser, at: 0)
        }
        return ordered + chromium
    }

    private static func defaultBrowser() -> Browser? {
        guard let probe = URL(string: "https://www.google.com/"),
              let app = NSWorkspace.shared.urlForApplication(toOpen: probe),
              let identifier = Bundle(url: app)?.bundleIdentifier else { return nil }
        return Browser.allCases.first { $0.bundleIdentifier == identifier }
    }

    // MARK: - Persistence

    private func persist() {
        let defaults = UserDefaults.standard
        guard case .connected(let method, let account) = connection else {
            defaults.removeObject(forKey: Keys.method)
            defaults.removeObject(forKey: Keys.account)
            defaults.removeObject(forKey: Keys.lastImport)
            return
        }
        switch method {
        case .browser(let browser): defaults.set(browser.rawValue, forKey: Keys.method)
        case .inApp:                defaults.set("inApp", forKey: Keys.method)
        }
        if let account, let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: Keys.account)
        } else {
            defaults.removeObject(forKey: Keys.account)
        }
        if let lastImport {
            defaults.set(lastImport, forKey: Keys.lastImport)
        } else {
            defaults.removeObject(forKey: Keys.lastImport)
        }
    }

    private static func storedMethod(in defaults: UserDefaults) -> Method? {
        guard let raw = defaults.string(forKey: Keys.method) else { return nil }
        if raw == "inApp" { return .inApp }
        return Browser(rawValue: raw).map { Method.browser($0) }
    }

    private static func storedAccount(in defaults: UserDefaults) -> GoogleAccount? {
        guard let data = defaults.data(forKey: Keys.account) else { return nil }
        return try? JSONDecoder().decode(GoogleAccount.self, from: data)
    }
}
