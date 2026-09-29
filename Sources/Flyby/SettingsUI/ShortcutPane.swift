import SwiftUI

/// Settings › Shortcut: the gesture that summons Flyby, shown as the keys you
/// actually press, with the recorder to change it right below.
struct ShortcutPane: View {
    @ObservedObject private var settings = AppSettings.shared
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
                        shortcut: $settings.shortcut,
                        onRecordingChanged: onRecordingChanged
                    )
                    .frame(width: 210)
                }
            } footer: {
                Text("Click, then press a key with modifiers for a combo like ⌥Space, hold two or more modifiers and let go for a chord, or tap one modifier twice for a double-tap. Key combos need no permissions; chords and double-taps need Accessibility.")
            }

            Section {
                Toggle("Ask about your screen", isOn: screenshotEnabled)
                if settings.screenshotShortcut != nil {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(
                            shortcut: screenshotShortcut,
                            defaultShortcut: .screenshotDefault,
                            onRecordingChanged: onRecordingChanged
                        )
                        .frame(width: 210)
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

    private var screenshotEnabled: Binding<Bool> {
        Binding(
            get: { settings.screenshotShortcut != nil },
            set: { settings.screenshotShortcut = $0 ? .screenshotDefault : nil }
        )
    }

    /// Only shown while there is one.
    private var screenshotShortcut: Binding<Shortcut> {
        Binding(
            get: { settings.screenshotShortcut ?? .screenshotDefault },
            set: { settings.screenshotShortcut = $0 }
        )
    }
}
