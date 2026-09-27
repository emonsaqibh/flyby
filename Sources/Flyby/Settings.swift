import Foundation
import ServiceManagement
import Security
import os

/// A modifier key that can take part in the "hold two modifiers" trigger.
/// Raw values are the device-dependent bits macOS sets on `CGEventFlags`,
/// which is the only way to tell left from right.
enum TriggerKey: UInt64, CaseIterable, Identifiable {
    case leftControl  = 0x0000_0001
    case leftShift    = 0x0000_0002
    case rightShift   = 0x0000_0004
    case leftCommand  = 0x0000_0008
    case rightCommand = 0x0000_0010
    case leftOption   = 0x0000_0020
    case rightOption  = 0x0000_0040
    case rightControl = 0x0000_2000

    var id: UInt64 { rawValue }

    var label: String {
        switch self {
        case .leftControl:  return "Left ⌃"
        case .leftShift:    return "Left ⇧"
        case .rightShift:   return "Right ⇧"
        case .leftCommand:  return "Left ⌘"
        case .rightCommand: return "Right ⌘"
        case .leftOption:   return "Left ⌥"
        case .rightOption:  return "Right ⌥"
        case .rightControl: return "Right ⌃"
        }
    }
}

enum ProviderKind: String, CaseIterable, Identifiable {
    case browser  = "browser"
    /// Stored as "webview" — the name from before AI Mode got a native view.
    case aiMode   = "webview"
    case gemini   = "gemini"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .browser: return "Browser"
        case .aiMode:  return "Google AI Mode"
        case .gemini:  return "Gemini"
        }
    }

    var detail: String {
        switch self {
        case .browser: return "Opens the search in your default browser"
        case .aiMode:  return "Answers from Google AI Mode, in your own Google session"
        case .gemini:  return "Streams an answer inline (needs a free API key)"
        }
    }

    /// Says *where the answer lands*, not "search" — the pill already has a
    /// magnifying glass on the leading edge and a second one there read as
    /// decoration rather than a control.
    var icon: String {
        switch self {
        case .browser: return "safari"
        case .aiMode:  return "sparkle.magnifyingglass"
        case .gemini:  return "text.bubble"
        }
    }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, duckduckgo, bing, perplexity

    var id: String { rawValue }

    var label: String {
        switch self {
        case .google:     return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing:       return "Bing"
        case .perplexity: return "Perplexity"
        }
    }

    /// RFC 3986 unreserved characters only. `.alphanumerics` would let "é" or
    /// "日本" through raw, and "+" left unencoded reads as a space to Google.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    func url(for query: String) -> URL {
        let base: String
        switch self {
        case .google:     base = "https://www.google.com/search?q="
        case .duckduckgo: base = "https://duckduckgo.com/?q="
        case .bing:       base = "https://www.bing.com/search?q="
        case .perplexity: base = "https://www.perplexity.ai/search?q="
        }
        let q = query.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? ""
        // Fully percent-encoded ASCII always parses; the fallbacks only exist
        // so a mistake here can't become a crash.
        return URL(string: base + q) ?? URL(string: base) ?? URL(fileURLWithPath: "/")
    }
}

/// Everything the user can change. Backed by UserDefaults, except the API key
/// which lives in the Keychain.
///
/// Main-actor bound: every view, the controller and the hot key layer read it
/// from the main thread, and `@Published` changes have to land there anyway.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// The model a fresh install uses, and the one "Reset" goes back to.
    /// Gemini 3.8 Flash is Google's current GA Flash model; 2.5 Flash is
    /// closed to new API keys and due to shut down.
    nonisolated static let defaultGeminiModel = "gemini-3.8-flash"

    /// Earlier defaults. A stored value that is one of these was never really
    /// the user's choice — it's the default at the time, written back by a
    /// reset — so it follows the default forward instead of pinning a model
    /// Google is retiring.
    private static let retiredDefaultModels: Set<String> = ["gemini-2.5-flash", "gemini-2.0-flash"]

    private static let geminiKeyAccount = "gemini-api-key"

    private let defaults = UserDefaults.standard

    @Published var shortcut: Shortcut {
        didSet { defaults.set(shortcut.storage, forKey: "shortcut") }
    }
    @Published var provider: ProviderKind {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    @Published var engine: SearchEngine {
        didSet { defaults.set(engine.rawValue, forKey: "engine") }
    }
    /// Only a deliberate choice is stored. Leaving the default unstored is what
    /// lets the next release move everyone who never picked a model onto a
    /// newer one.
    @Published var geminiModel: String {
        didSet {
            let trimmed = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == Self.defaultGeminiModel {
                defaults.removeObject(forKey: "geminiModel")
            } else {
                defaults.set(trimmed, forKey: "geminiModel")
            }
        }
    }
    /// Strips Google's nav, sign-in and composer out of the embedded AI Mode
    /// page. Off means you get the raw page, chrome and all.
    @Published var readerMode: Bool {
        didSet { defaults.set(readerMode, forKey: "readerMode") }
    }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var accent: AccentTheme {
        didSet { defaults.set(accent.rawValue, forKey: "accent") }
    }

    /// Mirrors `SMAppService`, which is the real source of truth — the system
    /// can turn this off behind our back from System Settings › Login Items.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != LoginItem.isEnabled else { return }
            do {
                try LoginItem.set(launchAtLogin)
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
                launchAtLogin = LoginItem.isEnabled
            }
        }
    }
    @Published var loginItemError: String?

    /// Stored in the Keychain, not UserDefaults. The text field writes this on
    /// every keystroke, and a Keychain write is a round trip to `securityd`
    /// that can prompt, so the write waits until typing pauses. Everything in
    /// the app reads this property, never the Keychain, so the delay is
    /// invisible.
    @Published var geminiKey: String {
        didSet { scheduleKeychainWrite() }
    }

    /// Gates the first-launch flow. An install that already recorded a
    /// shortcut predates onboarding and shouldn't be walked through it.
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    private var pendingKeychainValue: String?
    private var keychainWrite: Task<Void, Never>?

    private init() {
        // An explicit answer always wins. Only when the flag has never been
        // written does the legacy guess apply — otherwise "reset and show me
        // onboarding again" gets overruled by the shortcut it just rewrote.
        if defaults.object(forKey: "hasCompletedOnboarding") != nil {
            hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        } else {
            hasCompletedOnboarding = defaults.dictionary(forKey: "shortcut") != nil
        }
        shortcut = AppSettings.loadShortcut(from: defaults)
        provider = ProviderKind(rawValue: defaults.string(forKey: "provider") ?? "") ?? .browser
        engine = SearchEngine(rawValue: defaults.string(forKey: "engine") ?? "") ?? .google
        geminiModel = AppSettings.loadGeminiModel(from: defaults)
        readerMode = defaults.object(forKey: "readerMode") as? Bool ?? true
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        accent = AccentTheme(rawValue: defaults.string(forKey: "accent") ?? "") ?? .system
        // Glass stopped being optional in 0.4; forget the old switch.
        defaults.removeObject(forKey: "liquidGlass")
        launchAtLogin = LoginItem.isEnabled
        geminiKey = Keychain.get(AppSettings.geminiKeyAccount) ?? ""
    }

    /// Puts the app back to how it ships: preferences, the Keychain entry and
    /// the login-item registration all go.
    ///
    /// Reinstalling doesn't do this — preferences live in the user's defaults
    /// domain, not in the bundle — so this is the only way back to a first-run
    /// state short of deleting things by hand in Terminal.
    func resetAll() {
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        // Settings written before the app was renamed from Quick Search live in
        // their own domain, unreachable but still on disk. "All data" means all.
        defaults.removePersistentDomain(forName: "com.fringecore.quicksearch")
        try? LoginItem.set(false)

        // Assigning through the published properties updates the live UI and
        // rewrites the defaults behind them, so nothing needs a relaunch.
        shortcut = .default
        provider = .browser
        engine = .google
        geminiModel = Self.defaultGeminiModel
        readerMode = true
        appearance = .system
        accent = .system
        launchAtLogin = false
        loginItemError = nil
        geminiKey = ""
        hasCompletedOnboarding = false
        // Not left to the debounce: "reset" should mean the key is gone now.
        flushPendingWrites()
    }

    /// Writes anything still waiting on the debounce. Called at quit, so a key
    /// pasted a moment before ⌘Q isn't lost.
    func flushPendingWrites() {
        keychainWrite?.cancel()
        keychainWrite = nil
        guard let value = pendingKeychainValue else { return }
        pendingKeychainValue = nil
        Keychain.set(value, for: Self.geminiKeyAccount)
    }

    private func scheduleKeychainWrite() {
        pendingKeychainValue = geminiKey
        keychainWrite?.cancel()
        keychainWrite = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.flushPendingWrites()
        }
    }

    /// Reads the recorded shortcut, falling back to the pre-recorder pair of
    /// modifier settings so an existing install keeps its trigger.
    private static func loadShortcut(from defaults: UserDefaults) -> Shortcut {
        if let stored = defaults.dictionary(forKey: "shortcut"),
           let shortcut = Shortcut(storage: stored) {
            return shortcut
        }
        if let a = (defaults.object(forKey: "triggerA") as? NSNumber).flatMap({ TriggerKey(rawValue: $0.uint64Value) }),
           let b = (defaults.object(forKey: "triggerB") as? NSNumber).flatMap({ TriggerKey(rawValue: $0.uint64Value) }) {
            return .modifierChord([a, b])
        }
        return .default
    }

    private static func loadGeminiModel(from defaults: UserDefaults) -> String {
        let stored = defaults.string(forKey: "geminiModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty || retiredDefaultModels.contains(stored) {
            defaults.removeObject(forKey: "geminiModel")
            return defaultGeminiModel
        }
        return stored
    }
}

/// Start-at-login, via the modern `SMAppService` rather than a login-item
/// helper bundle.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Surfaced in Settings rather than hidden, because the states that aren't
    /// a plain yes/no are exactly the ones worth telling the user about.
    static var statusDescription: String? {
        switch SMAppService.mainApp.status {
        case .enabled, .notRegistered:
            return nil
        case .requiresApproval:
            return "Waiting for approval in System Settings › General › Login Items."
        case .notFound:
            return "macOS can't find this app's registration. Move Flyby to /Applications and toggle again."
        @unknown default:
            return nil
        }
    }
}

enum Keychain {
    /// Keyed to the running bundle, so the dev and release builds each keep
    /// their own Gemini key instead of trampling one shared entry.
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.fringecore.flyby"
    }

    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "keychain")

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let deleted = SecItemDelete(query as CFDictionary)
        if deleted != errSecSuccess && deleted != errSecItemNotFound {
            log.error("delete \(account, privacy: .public) failed: \(deleted, privacy: .public)")
        }
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }

        var add = query
        add[kSecValueData as String] = data
        // From the first unlock after boot onward, locked screen included —
        // the app runs all day in the background — but never before anyone
        // has logged in.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        var added = SecItemAdd(add as CFDictionary, nil)
        if added == errSecParam {
            // The file-based keychain (all an ad-hoc signed app gets) can
            // refuse accessibility classes it doesn't model. Losing the key
            // would be worse than losing the attribute.
            add.removeValue(forKey: kSecAttrAccessible as String)
            added = SecItemAdd(add as CFDictionary, nil)
        }
        if added != errSecSuccess {
            let status = added
            log.error("save \(account, privacy: .public) failed: \(status, privacy: .public)")
        }
    }

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                log.error("read \(account, privacy: .public) failed: \(status, privacy: .public)")
            }
            return nil
        }
        guard let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
