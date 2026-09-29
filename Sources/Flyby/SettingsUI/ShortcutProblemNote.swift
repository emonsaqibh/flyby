import SwiftUI

/// What's keeping each shortcut from working right now, for the places that
/// record them — Settings › Shortcut, and the walkthrough and What's new. The
/// app delegate keeps it current as it installs the hot keys and polls for
/// grants.
@MainActor
final class ShortcutHealthModel: ObservableObject {
    static let shared = ShortcutHealthModel()

    enum Problem: Equatable {
        /// A double-tap or chord, without Accessibility or Input Monitoring.
        case needsKeyboardAccess
        /// A key combo macOS wouldn't register, and why.
        case unavailable(String)
    }

    @Published var main: Problem?
    @Published var screenshot: Problem?

    /// Dev builds: `-FlybyDebugShortcutProblem screenshot|main` shows the
    /// permission note there, to look at without revoking a grant.
    var shownMain: Problem? { Self.debugProblem == "main" ? .needsKeyboardAccess : main }
    var shownScreenshot: Problem? { Self.debugProblem == "screenshot" ? .needsKeyboardAccess : screenshot }

    private static let debugProblem: String? =
        BuildFlavor.isDev ? UserDefaults.standard.string(forKey: "FlybyDebugShortcutProblem") : nil
}

/// Why a shortcut isn't working, right under the one it's about, with the
/// way to fix it: the pane that still needs Flyby, and — since an update is
/// the usual cause — how to get macOS to take an entry that looks on but no
/// longer matches.
struct ShortcutProblemNote: View {
    let problem: ShortcutHealthModel.Problem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if problem == .needsKeyboardAccess {
                    Button("Open System Settings") {
                        HotKeyMonitor.requestKeyboardAccess()
                        HotKeyMonitor.openKeyboardAccessSettings()
                    }
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch problem {
        case .needsKeyboardAccess: return "Waiting for permission"
        case .unavailable:         return "Not available"
        }
    }

    private var message: String {
        switch problem {
        case .needsKeyboardAccess:
            let name = BuildFlavor.appName
            return "Double-taps and chords need \(name) turned on under both Accessibility and Input Monitoring. If it's already on there, remove it with − and add it again: macOS treats each update as a new app."
        case .unavailable(let reason):
            return reason
        }
    }
}
