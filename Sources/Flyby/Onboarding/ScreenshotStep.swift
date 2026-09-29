import SwiftUI

// MARK: - Screenshot

/// Ask about your screen: the shortcut that takes a picture of the window
/// you're in and opens Flyby with it — shown, played, and kept, changed or
/// turned off. In the walkthrough after the practice run; on its own, as
/// what's new, for people updating from before screenshots.
struct ScreenshotStep: View {
    @ObservedObject var settings: AppSettings
    /// Pauses the live hot keys while the recorder is armed.
    let onRecordingChanged: (Bool) -> Void
    /// For someone who already knows Flyby: say it's new.
    var isNew = false

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: isNew ? "New: ask about your screen" : "Ask about your screen",
                subtitle: "One press takes a picture of the window you're in and opens Flyby with it — then ask Google or Gemini anything about it."
            )

            // The keys, playing themselves, like the shortcut step's; with the
            // shortcut off, what it would have done.
            ZStack {
                if let shortcut = settings.screenshotShortcut {
                    KeyCapsView(shortcut: shortcut, mode: .demonstrate)
                        .id(shortcut.displayString)
                        .transition(SoftSwapTransition())
                } else {
                    IconBadge("camera.viewfinder", color: .gray, size: 64)
                        .transition(SoftSwapTransition())
                }
            }
            .frame(height: 96)
            .reveal(.content, blurs: false)
            .padding(.top, 30)

            HStack(spacing: 14) {
                Toggle("Shortcut", isOn: settings.screenshotEnabledBinding)
                    .toggleStyle(.switch)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(
                    shortcut: settings.screenshotShortcutBinding,
                    defaultShortcut: .screenshotDefault,
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
            .padding(.top, 30)

            StepFootnote(footnote)
                .id(footnote)
                .transition(SoftSwapTransition())
                .reveal(.footnote)
                .padding(.top, 14)
        }
        .animation(.smooth(duration: 0.4), value: settings.screenshotShortcut)
    }

    private var footnote: String {
        guard settings.screenshotShortcut != nil else {
            return "The Screenshot button under Flyby's bar still takes one whenever you want."
        }
        return "Just the window you're in, and nothing leaves your Mac until you press Return. macOS asks for Screen Recording the first time."
    }
}
