import SwiftUI
import AppKit
import Combine
import FlybyCore

/// The settings window: a source list on the left, one pane on the right, in
/// the shape of System Settings — which is where people already look for
/// "how do I change this". Always dark, like the rest of Flyby.
///
/// A real `NavigationSplitView`, so the sidebar is the system's own. Each
/// pane is a grouped `Form` that opens with a hero — its badge, its name and
/// what it's for — the way System Settings' panes do; the panes themselves
/// live in `SettingsUI/`. The sidebar can't be collapsed, since there's no
/// pane that wants the room.
struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigation.shared
    /// Pauses the live hotkey while recording, so the old shortcut doesn't fire
    /// as the user presses their new one.
    let onRecordingChanged: (Bool) -> Void

    static let size = CGSize(width: 760, height: 640)
    /// Wide enough for "Google Account" beside its badge, with room to spare.
    static let sidebarWidth: CGFloat = 220

    var body: some View {
        NavigationSplitView {
            // A frame rather than `navigationSplitViewColumnWidth`, which a
            // split view hosted in an AppKit window ignores.
            SettingsSidebar(selection: selection)
                .frame(width: Self.sidebarWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .defaultScrollAnchor(Self.debugScrollAnchor)
        }
        // Fixed width, free height: tall panes (Google Account) get the room
        // on a big screen, and nothing is cut off on a small one.
        .frame(width: Self.size.width)
        .frame(minHeight: 480, idealHeight: Self.size.height, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .flybyShouldShowGoogleSettings)) { _ in
            navigation.section = .google
        }
    }

    /// Dev builds only: `-FlybyDebugScrollToBottom 1` opens each pane
    /// scrolled to its end, to check how content passes under the title
    /// without scrolling by hand.
    private static var debugScrollAnchor: UnitPoint? {
        BuildFlavor.isDev && UserDefaults.standard.bool(forKey: "FlybyDebugScrollToBottom") ? .bottom : nil
    }

    /// Clicking empty space in a source list deselects; there's always a pane
    /// on screen, so ignore that rather than showing nothing.
    private var selection: Binding<SettingsSection?> {
        Binding(
            get: { navigation.section },
            set: { if let section = $0 { navigation.section = section } }
        )
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.section {
        case .general:    GeneralPane()
        case .shortcut:   ShortcutPane(onRecordingChanged: onRecordingChanged)
        case .answers:    AnswersPane()
        case .history:    HistoryPane()
        case .google:     GoogleAccountPane()
        case .advanced:   AdvancedPane()
        }
    }
}

// MARK: - Sections

/// The panes, in sidebar order. `general` and `google` are part of the app's
/// vocabulary — `SettingsNavigation.showGoogleAccount()` and the
/// `-FlybyDebugOpen settings.<rawValue>` hook name them — so keep those.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, shortcut, answers, history, google, advanced

    var id: Self { self }

    /// Grouped the way System Settings clusters its sidebar: the app itself,
    /// then what answers you and what it keeps, then the escape hatches.
    static let sidebarGroups: [[SettingsSection]] = [
        [.general, .shortcut],
        [.answers, .history, .google],
        [.advanced],
    ]

    var title: String {
        switch self {
        case .general:    return "General"
        case .shortcut:   return "Shortcut"
        case .answers:    return "Answers"
        case .history:    return "History"
        case .google:     return "Google Account"
        case .advanced:   return "Advanced"
        }
    }

    /// One line under the pane's name in its hero — what the pane is for,
    /// not a list of what's in it.
    var summary: String {
        switch self {
        case .general:    return "How Flyby starts up, stays current, and which version you’re running."
        case .shortcut:   return "The gesture that brings up Flyby from anywhere on your Mac."
        case .answers:    return "Choose where answers come from, and set up each source."
        case .history:    return "Your recent chats, kept only on this Mac."
        case .google:     return "Sign AI Mode in as you, so Google rarely asks if you’re human."
        case .advanced:   return "Run the walkthrough again, or start over from scratch."
        }
    }

    /// Each pane gets its own hue, so the sidebar can be read by colour at a
    /// glance — though never *only* by colour: every badge has its own symbol.
    var tint: Color {
        switch self {
        case .general:    return .gray
        case .shortcut:   return .indigo
        case .answers:    return .blue
        case .history:    return .orange
        case .google:     return .green
        case .advanced:   return .red
        }
    }

    var symbol: String {
        switch self {
        case .general:    return "gearshape.fill"
        case .shortcut:   return "command"
        case .answers:    return "sparkles"
        case .history:    return "clock.arrow.circlepath"
        case .google:     return "person.crop.circle.fill"
        case .advanced:   return "wrench.and.screwdriver.fill"
        }
    }

    func badge(size: CGFloat) -> IconBadge {
        IconBadge(symbol, color: tint, size: size)
    }
}

/// Which pane Settings shows. Shared rather than view state, so a request can
/// land before the window exists — "Connect Google Account…" in the provider
/// menu sets it, then the app delegate opens the window already on that pane.
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

// MARK: - Window

extension SettingsView {
    /// The Settings window, styled and sized for it. The app delegate owns its
    /// lifetime: it positions it, keeps it, and hears it close.
    ///
    /// Shaped like System Settings: the sidebar runs the full height of the
    /// window, under the traffic lights, and the selected pane's name sits in
    /// a unified toolbar over the detail column.
    ///
    /// Dark whatever the system is set to: Flyby has no light mode, and its
    /// Settings should look like the overlay it configures.
    static func makeWindow(onRecordingChanged: @escaping (Bool) -> Void) -> NSWindow {
        let host = NSHostingController(rootView: SettingsView(onRecordingChanged: onRecordingChanged))
        // Toolbars only. A bridged navigation title never reaches a window
        // SwiftUI didn't create, so the window follows the pane itself.
        host.sceneBridgingOptions = [.toolbars]
        // The window takes its width and its minimum height from SwiftUI but
        // not its ideal height, which would snap back every drag.
        host.sizingOptions = [.minSize, .maxSize]

        let window = SettingsWindow(contentViewController: host)
        window.appearance = NSAppearance(named: .darkAqua)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // Without a toolbar the title bar is a bare strip; an (empty) unified
        // toolbar gives it System Settings' height and puts the title over
        // the detail column rather than across the window.
        window.toolbar = NSToolbar(identifier: "FlybySettings")
        window.toolbarStyle = .unified
        window.collectionBehavior.insert(.fullScreenNone)
        window.setContentSize(size)
        window.followTitle(of: SettingsNavigation.shared)
        return window
    }
}

/// Titled after whichever pane is showing, the way System Settings is — and
/// what Mission Control and the Window menu call it.
private final class SettingsWindow: NSWindow {
    private var titleSubscription: AnyCancellable?

    func followTitle(of navigation: SettingsNavigation) {
        titleSubscription = navigation.$section
            .removeDuplicates()
            .sink { [weak self] section in self?.title = section.title }
    }
}
