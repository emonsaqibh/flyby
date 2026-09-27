import SwiftUI
import AppKit

/// The settings window: a source list on the left, one pane on the right, in
/// the shape of System Settings — which is where people already look for
/// "how do I change this".
///
/// Built from a plain `List` rather than `NavigationSplitView`: this lives in
/// an `NSWindow` the app delegate creates, and a split view there brings
/// toolbar and column-collapsing behaviour that only makes sense in a
/// SwiftUI-managed window.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @ObservedObject private var google = GoogleSession.shared
    /// Pauses the live hotkey while recording, so the old shortcut doesn't fire
    /// as the user presses their new one.
    let onRecordingChanged: (Bool) -> Void

    @State private var confirmingReset = false

    static let size = CGSize(width: 720, height: 560)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .themed()
        .onReceive(NotificationCenter.default.publisher(for: .flybyShouldShowGoogleSettings)) { _ in
            navigation.section = .google
        }
        .confirmationDialog(
            "Reset Flyby to a fresh install?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset All Data", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your shortcut, appearance, provider settings, Gemini API key and Google connection are all removed, and onboarding starts over. This can't be undone.")
        }
    }

    // MARK: - Chrome

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SettingsSection.allCases) { section in
                Label(section.title, systemImage: section.icon)
                    .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(VisualEffectBackground(material: .sidebar))
        .frame(width: 200)
    }

    /// Clicking empty space in a source list deselects; there's always a pane
    /// on screen, so ignore that rather than showing nothing.
    private var selection: Binding<SettingsSection?> {
        Binding(
            get: { navigation.section },
            set: { if let section = $0 { navigation.section = section } }
        )
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(navigation.section.title)
                .font(.system(size: 20, weight: .bold))
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)

            pane
        }
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.section {
        case .general:    general
        case .appearance: appearance
        case .search:     search
        case .google:     googleAccount
        case .advanced:   advanced
        }
    }

    // MARK: - General

    private var general: some View {
        Form {
            Section {
                about
            }

            Section("Shortcut") {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(
                        shortcut: $settings.shortcut,
                        onRecordingChanged: onRecordingChanged
                    )
                }
                Text(settings.shortcut.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Click, then press a key with modifiers for a combo, hold two or more modifiers and release them for a chord, or tap a single modifier twice for a double-tap like double Right ⌥. Key combos need no permissions; chords and double-taps need Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                // The dev build runs from build/ on purpose.
                if !BuildFlavor.isDev && !Installer.isInstalled {
                    // Login items and the Accessibility grant both key off the
                    // app's path, so this is the fix for half the ways Flyby
                    // can appear broken — worth a row of its own, not a footnote.
                    LabeledContent {
                        Button("Move to Applications") { Installer.performInstall() }
                    } label: {
                        Label("Not installed in Applications", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text("Flyby is running from \(Installer.bundleURL.deletingLastPathComponent().path). Permissions and open-at-login follow the app's location, so they won't stick until it's in Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("Open at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let status = LoginItem.statusDescription {
                    Label(status, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Managed by macOS — you can also turn this off in System Settings › General › Login Items. Registration is tied to where the app lives, so re-toggle after moving it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            UpdateSettingsSection()
        }
        .formStyle(.grouped)
    }

    /// The app's own icon and version, so Settings reads as Flyby's rather than
    /// a generic preferences window — this is the only place a menu-bar app
    /// gets to show its face.
    private var about: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.2), radius: 7, y: 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(BuildFlavor.appName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    if BuildFlavor.isDev {
                        DevBadge()
                    }
                }
                Text(Self.versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Search from anywhere on your Mac with one gesture.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private static var versionString: String {
        var version = "Version \(BuildFlavor.versionLabel)"
        if let commit = BuildFlavor.commit, !commit.isEmpty {
            version += " (\(commit))"
        }
        return version
    }

    // MARK: - Appearance

    private var appearance: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Applies to the pill, the result panel and this window. System follows your macOS setting live.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Material") {
                Toggle("Liquid Glass", isOn: $settings.liquidGlass)
                    .disabled(!LiquidGlass.isSupported)
                Text(LiquidGlass.isSupported
                     ? "Uses macOS's Liquid Glass for the pill and the answer panel, and follows the glass look you've chosen in System Settings. Off falls back to the classic blurred material, as does Reduce Transparency."
                     : "\(LiquidGlass.requirement) Using the classic blurred material.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Accent") {
                LabeledContent("Color") {
                    AccentSwatches(selection: $settings.accent, diameter: 18)
                }
                Text("Tints the ↩ badge, links and source chips. System uses the accent color from System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Search

    private var search: some View {
        Form {
            Section("Provider") {
                Picker("Answer with", selection: $settings.provider) {
                    ForEach(ProviderKind.allCases) {
                        Label($0.label, systemImage: $0.icon).tag($0)
                    }
                }
                Text(settings.provider.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // AI Mode without an account is the path Google quizzes most;
                // say so where the choice is made.
                if settings.provider == .aiMode, !google.isConnected {
                    LabeledContent {
                        Button("Connect…") { navigation.section = .google }
                    } label: {
                        Label("Connect your Google account for fewer “are you human?” checks.", systemImage: "person.crop.circle.badge.plus")
                            .font(.callout)
                    }
                }
            }

            Section("Browser") {
                Picker("Search engine", selection: $settings.engine) {
                    ForEach(SearchEngine.allCases) { Text($0.label).tag($0) }
                }
                Text("Used when opening in your browser, including ⌘Return from any provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Google AI Mode") {
                Toggle("Reader mode", isOn: $settings.readerMode)
                Text("When Flyby shows Google's page itself, hides Google's nav, sign-in and composer so only the answer shows. Turn off if it ever hides too much.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gemini") {
                SecureField("API key", text: $settings.geminiKey)
                TextField("Model", text: $settings.geminiModel, prompt: Text(AppSettings.defaultGeminiModel))
                Link("Get a free key from Google AI Studio",
                     destination: URL(string: "https://aistudio.google.com/apikey")!)
                    .font(.caption)
                Text("Stored in your Keychain, never written to disk in plain text. The free tier covers everyday use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Google Account

    private var googleAccount: some View {
        Form {
            GoogleConnectView(layout: .form)
        }
        .formStyle(.grouped)
    }

    // MARK: - Advanced

    private var advanced: some View {
        Form {
            Section("Walkthrough") {
                LabeledContent("Onboarding") {
                    Button("Show Onboarding Again") { showOnboarding() }
                }
                Text("Runs the first-launch walkthrough again. Nothing is erased.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reset") {
                LabeledContent("Everything") {
                    Button("Reset All Data…", role: .destructive) { confirmingReset = true }
                }
                Text("Clears every preference, disconnects your Google account, forgets the Gemini key in your Keychain and turns off open-at-login — the state a fresh install would have. Reinstalling doesn't do this on its own, because settings live in your user account rather than in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func resetAll() {
        settings.resetAll()
        Task { await GoogleSession.shared.disconnect() }
        navigation.section = .general
        showOnboarding()
    }

    /// The walkthrough lives in a window the app delegate owns, so Settings can
    /// only ask for it.
    private func showOnboarding() {
        settings.hasCompletedOnboarding = false
        NotificationCenter.default.post(name: .flybyShouldShowOnboarding, object: nil)
    }
}

// MARK: - Sections

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, search, google, advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .search:     return "Search"
        case .google:     return "Google Account"
        case .advanced:   return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general:    return "gearshape"
        case .appearance: return "paintbrush"
        case .search:     return "magnifyingglass"
        case .google:     return "person.crop.circle"
        case .advanced:   return "slider.horizontal.3"
        }
    }
}

/// Which pane Settings shows. Shared rather than view state, so a request can
/// land before the window exists — "Connect Google Account…" in the pill
/// sets it, then the app delegate opens the window already on that pane.
@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()

    @Published var section: SettingsSection = .general

    /// Settings › Google Account, from wherever the user hit the wall.
    static func showGoogleAccount() {
        shared.section = .google
        NotificationCenter.default.post(name: .flybyShouldShowGoogleSettings, object: nil)
    }
}

extension Notification.Name {
    /// Asks the app delegate to open Settings on the Google Account pane.
    /// `SettingsNavigation.showGoogleAccount()` posts it after selecting the
    /// pane; an open Settings window also switches when it sees it.
    static let flybyShouldShowGoogleSettings = Notification.Name("flybyShouldShowGoogleSettings")
}

// MARK: - Accent swatches

/// Eight swatches, each in the colour it will actually draw — the derived
/// shade for the current appearance, not a nominal one. Shared with
/// onboarding.
struct AccentSwatches: View {
    @Binding var selection: AccentTheme
    var diameter: CGFloat = 18

    var body: some View {
        HStack(spacing: diameter * 0.45) {
            ForEach(AccentTheme.allCases) { theme in
                let isSelected = selection == theme
                Button {
                    selection = theme
                } label: {
                    Circle()
                        .fill(theme.swatch)
                        .frame(width: diameter, height: diameter)
                        .overlay(
                            // "System" gets a rim, so it doesn't read as
                            // just another colour.
                            Circle()
                                .strokeBorder(.primary.opacity(theme == .system ? 0.35 : 0), lineWidth: 1)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(.primary, lineWidth: 2)
                                .padding(-3)
                                .opacity(isSelected ? 1 : 0)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(theme.label)
                .accessibilityLabel(theme.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accent color")
    }
}
