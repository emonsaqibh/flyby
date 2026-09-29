import SwiftUI

/// Settings › Shortcut: the gesture that summons Flyby, shown as the keys you
/// actually press, with the recorder to change it right below.
struct ShortcutPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var health = ShortcutHealthModel.shared
    /// Pauses the live hot key while recording.
    let onRecordingChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            PaneHero(section: .shortcut)

            Section {
                VStack(spacing: 14) {
                    ShortcutKeyCaps(shortcut: settings.shortcut)
                        // A new shortcut resolves out of a blur rather than
                        // snapping in; under Reduce Motion it just crossfades.
                        .id(settings.shortcut.displayString)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))

                    Text(settings.shortcut.explanation)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .animation(reduceMotion ? .smooth(duration: 0.2) : .spring(duration: 0.45, bounce: 0.2),
                           value: settings.shortcut.displayString)
            }

            Section {
                LabeledContent("Record a new shortcut") {
                    ShortcutRecorder(
                        shortcut: mainShortcut,
                        conflict: { settings.conflict(forShortcut: $0) },
                        onRecordingChanged: onRecordingChanged
                    )
                    .frame(width: 210)
                }
                if let problem = health.shownMain {
                    ShortcutProblemNote(problem: problem)
                }
            } footer: {
                Text("Click, then press a key with modifiers for a combo like ⌥Space, hold two or more modifiers and let go for a chord, or tap one modifier twice for a double-tap. Key combos need no permissions; chords and double-taps need Accessibility and Input Monitoring.")
            }

            Section {
                Toggle("Ask about your screen", isOn: screenshotEnabled)
                if settings.screenshotShortcut != nil {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(
                            shortcut: screenshotShortcut,
                            defaultShortcut: .screenshotDefault,
                            conflict: { settings.conflict(forScreenshot: $0) },
                            onRecordingChanged: onRecordingChanged
                        )
                        .frame(width: 210)
                    }
                    if let problem = health.shownScreenshot {
                        ShortcutProblemNote(problem: problem)
                    }
                }
            } header: {
                Text("Screenshot")
            } footer: {
                Text("Takes a picture of the window you're in and opens \(BuildFlavor.appName) with it attached, to ask Google or Gemini about. The Screenshot button under the bar does the same. Needs Screen Recording permission.")
            }
        }
        .formStyle(.grouped)
    }

    private var screenshotEnabled: Binding<Bool> { settings.screenshotEnabledBinding }
    private var mainShortcut: Binding<Shortcut> { settings.shortcutBinding }
    private var screenshotShortcut: Binding<Shortcut> { settings.screenshotShortcutBinding }
}
