import SwiftUI
import Combine

// MARK: - Screenshot

/// Ask about your screen: the shortcut that takes a picture of the window
/// you're in and opens Flyby with it — kept, changed or turned off — and the
/// Screen Recording grant it needs, settled here rather than at the first
/// screenshot. In the walkthrough after the practice run; on its own, as
/// what's new, for people updating from before screenshots.
///
/// The grant is macOS's: Allow asks, System Settings is where it's given,
/// and macOS only lets Flyby use it after a relaunch — its own "Quit &
/// Reopen", or Reopen Flyby here. The walkthrough comes back to this step
/// either way. Once it's allowed, pressing the shortcut is a practice run:
/// the wave crosses the screen and the keys light up, and nothing opens.
struct ScreenshotStep: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var health = ShortcutHealthModel.shared
    /// Pauses the live hot keys while the recorder is armed.
    let onRecordingChanged: (Bool) -> Void
    /// For someone who already knows Flyby: say it's new.
    var isNew = false

    @State private var allowed = ScreenCapture.hasPermission
    /// Allow was clicked: from here, what's left is the relaunch.
    @State private var asked = false
    @State private var tried = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: isNew ? "New: ask about your screen" : "Ask about your screen",
                subtitle: "One press takes a picture of the window you're in and opens Flyby with it — then ask Google or Gemini anything about it."
            )

            // The keys, playing themselves until they can be tried, then
            // waiting for the try, then lit; with the shortcut off, what it
            // would have done.
            ZStack {
                if let shortcut = settings.screenshotShortcut {
                    KeyCapsView(shortcut: shortcut, mode: keysMode)
                        .id(shortcut.displayString)
                        .transition(SoftSwapTransition())
                } else {
                    IconBadge("camera.viewfinder", color: .gray, size: 64)
                        .transition(SoftSwapTransition())
                }
            }
            .frame(height: 96)
            .reveal(.content, blurs: false)
            .padding(.top, 26)

            HStack(spacing: 14) {
                Toggle("Shortcut", isOn: settings.screenshotEnabledBinding)
                    .toggleStyle(.switch)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(
                    shortcut: settings.screenshotShortcutBinding,
                    defaultShortcut: .screenshotDefault,
                    conflict: { settings.conflict(forScreenshot: $0) },
                    onRecordingChanged: onRecordingChanged
                )
                .frame(width: 240)
                .disabled(settings.screenshotShortcut == nil)
                .opacity(settings.screenshotShortcut == nil ? 0.45 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .paneGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .reveal(.controls, blurs: false)
            .padding(.top, 24)

            status
                .transition(SoftSwapTransition())
                .reveal(.footnote)
                .padding(.top, 14)
        }
        .animation(.smooth(duration: 0.4), value: settings.screenshotShortcut)
        .animation(.smooth(duration: 0.4), value: health.screenshot)
        .animation(.smooth(duration: 0.4), value: allowed)
        .animation(.smooth(duration: 0.4), value: asked)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: tried)
        .onReceive(poll) { _ in
            let now = ScreenCapture.hasPermission
            if now != allowed { allowed = now }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flybyDidTriggerScreenshotShortcut)) { _ in
            if allowed { tried = true }
        }
    }

    private var keysMode: KeyCapsView.Mode {
        if tried { return .celebrating }
        return allowed ? .waiting : .demonstrate
    }

    /// One line under the controls: what's in the way, what's next, or that
    /// it works.
    @ViewBuilder
    private var status: some View {
        if let reason = health.screenshot {
            ShortcutProblemNote(reason: reason)
                .padding(12)
                .frame(width: 470)
                .paneGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if settings.screenshotShortcut == nil {
            StepFootnote("The Screenshot button under Flyby's bar still takes one whenever you want.")
        } else if !allowed {
            permission
        } else if tried {
            confirmation("That's it. It goes in with your next question — nothing leaves your Mac until you press Return.")
        } else {
            confirmation("Screen Recording is on. Press \(settings.screenshotShortcut?.displayString ?? "the shortcut") to try it.")
        }
    }

    /// Allow, then — macOS only hands the grant over to a fresh launch —
    /// Reopen.
    private var permission: some View {
        VStack(spacing: 8) {
            Text(asked
                 ? "Turned on \(BuildFlavor.appName) under Screen & System Audio Recording? It takes effect once \(BuildFlavor.appName) reopens — you'll be right back here."
                 : "\(BuildFlavor.appName) needs Screen Recording to see the window you're in. Only that window, only when you press the shortcut.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
            HStack(spacing: 10) {
                if asked {
                    Button("Reopen \(BuildFlavor.appName)") { Installer.relaunch(at: Bundle.main.bundleURL) }
                        .buttonStyle(.glassProminent)
                    Button("Open System Settings") { ScreenCapture.openSettings() }
                        .buttonStyle(.glass)
                } else {
                    Button("Allow Screen Recording") {
                        asked = true
                        // The first time macOS asks itself; after that only
                        // System Settings can say yes.
                        ScreenCapture.requestPermission()
                        ScreenCapture.openSettings()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .controlSize(.regular)
        }
    }

    private func confirmation(_ text: String) -> some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: 480)
    }
}

extension Notification.Name {
    /// The screenshot shortcut, pressed while the walkthrough or What's new is
    /// on screen: a practice run, which the screenshot step shows landing.
    static let flybyDidTriggerScreenshotShortcut = Notification.Name("flybyDidTriggerScreenshotShortcut")
}
