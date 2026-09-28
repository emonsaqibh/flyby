import SwiftUI

// The second half: the gesture that summons Flyby, the one permission some
// gestures need, a real try of it, and the send-off.

// MARK: - Shortcut

struct ShortcutStep: View {
    @ObservedObject var settings: AppSettings
    /// Pauses the live hotkey while the recorder is armed.
    let onRecordingChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Summon Flyby from anywhere",
                subtitle: settings.shortcut.explanation
            )

            // A new shortcut is a new set of keys: they swap rather than
            // re-label, and the demonstration starts over for the new shape.
            ZStack {
                KeyCapsView(shortcut: settings.shortcut, mode: .demonstrate)
                    .id(settings.shortcut.displayString)
                    .transition(SoftSwapTransition())
            }
            .frame(height: 96)
            .reveal(.content, blurs: false)
            .padding(.top, 30)

            HStack(spacing: 12) {
                Text("Shortcut")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(shortcut: $settings.shortcut, onRecordingChanged: onRecordingChanged)
                    .frame(width: 260)
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
        .animation(.smooth(duration: 0.4), value: settings.shortcut)
    }

    private var footnote: String {
        if case .keyCombo = settings.shortcut {
            return "Key combos work without any special permission."
        }
        return "Double-taps and chords need one Accessibility approval; key combos don't."
    }
}

// MARK: - Accessibility

/// The gate for modifier-only gestures. Moves itself on the moment the
/// switch is flipped; the button in the footer is only an escape hatch.
struct AccessibilityStep: View {
    let isTrusted: Bool

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "One permission to grant",
                subtitle: "macOS only shares modifier-only gestures with apps you approve."
            )

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IconBadge("accessibility", color: .blue, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Turn on Flyby under Accessibility")
                            .font(.system(size: 14, weight: .semibold))
                        Text("System Settings › Privacy & Security › Accessibility")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    status
                    Spacer(minLength: 8)
                    if !isTrusted {
                        Button("Open System Settings") {
                            HotKeyMonitor.ensureAccessibilityPermission()
                            HotKeyMonitor.openAccessibilitySettings()
                        }
                        .buttonStyle(.glass)
                        .transition(SoftSwapTransition())
                    }
                }
                .frame(minHeight: 30)
            }
            .frame(width: 470)
            .glassCard()
            .reveal(.content, blurs: false)
            .padding(.top, 26)

            StepFootnote("Flyby only listens for your shortcut. Nothing you type is recorded.")
                .reveal(.footnote)
                .padding(.top, 16)
        }
        .animation(.spring(duration: 0.5, bounce: 0.25), value: isTrusted)
    }

    /// Waiting, then — the moment permission lands — a check that draws
    /// itself in.
    @ViewBuilder
    private var status: some View {
        if isTrusted {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .green)
                    .transition(.symbolEffect(.drawOn))
                Text("Permission granted")
                    .font(.system(size: 13, weight: .medium))
            }
            .transition(SoftSwapTransition())
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .transition(SoftSwapTransition())
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Practice

/// Proof it all works: the user fires the real shortcut, and Flyby appears.
struct PracticeStep: View {
    let shortcut: Shortcut
    let succeeded: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Trails `succeeded` by a beat, so the keys get their flash before the
    /// check takes their place.
    @State private var showsCheck = false

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: succeeded ? "You've got it!" : "Try it now",
                subtitle: succeeded
                    ? "That's the whole trick. Press Esc to put Flyby away."
                    : shortcut.explanation
            )

            ZStack {
                KeyCapsView(shortcut: shortcut, mode: succeeded ? .celebrating : .waiting)
                    .opacity(showsCheck ? 0 : 1)
                    .blur(radius: showsCheck && !reduceMotion ? 14 : 0)
                    .scaleEffect(showsCheck && !reduceMotion ? 0.8 : 1)

                if showsCheck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 88, weight: .regular))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.45), radius: 24, y: 6)
                        .transition(.symbolEffect(.drawOn))
                        .accessibilityLabel("Success")
                }
            }
            .frame(height: 110)
            .reveal(.content, blurs: false)
            .padding(.top, 30)

            listening
                .reveal(.controls)
                .padding(.top, 26)

            StepFootnote("Flyby opens at the bottom of your screen, over whatever you're doing.")
                .reveal(.footnote)
                .padding(.top, 8)
        }
        .task(id: succeeded) {
            guard succeeded else {
                showsCheck = false
                return
            }
            try? await Task.sleep(for: .seconds(reduceMotion ? 0 : 0.6))
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) { showsCheck = true }
        }
    }

    /// "Listening" while waiting; quietly gone once it's worked.
    private var listening: some View {
        Label("Listening for your shortcut…", systemImage: "dot.radiowaves.left.and.right")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, isActive: !succeeded && !reduceMotion)
            .opacity(succeeded ? 0 : 1)
            .animation(.smooth(duration: 0.3), value: succeeded)
    }
}

// MARK: - Done

/// What was set up, at a glance, and the one thing worth deciding on the way
/// out: whether Flyby is there after a restart.
struct DoneStep: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "You're all set",
                subtitle: "Flyby lives in your menu bar, ready whenever you are."
            )

            VStack(spacing: 0) {
                recapRow("Shortcut", badge: IconBadge("keyboard", color: .gray, size: 26)) {
                    MiniKeyCaps(shortcut: settings.shortcut)
                }

                Divider().padding(.leading, 56)

                recapRow("Answers from", badge: settings.provider.badge(size: 26)) {
                    Text(settings.provider.label)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Divider().padding(.leading, 56)

                recapRow("Open Flyby at login", badge: IconBadge("power", color: .green, size: 26)) {
                    Toggle("Open Flyby at login", isOn: $settings.launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
            .padding(.vertical, 4)
            .frame(width: 440)
            .paneGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .reveal(.content, blurs: false)
            .padding(.top, 28)

            loginNote
                .reveal(.footnote)
                .padding(.top, 12)
        }
    }

    /// A settings-style summary line: badge, what it is, and its value.
    private func recapRow<Value: View>(
        _ title: String,
        badge: IconBadge,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(spacing: 14) {
            badge
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
            Spacer(minLength: 8)
            value()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private var loginNote: some View {
        if let error = settings.loginItemError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
        } else if let status = LoginItem.statusDescription {
            Label(status, systemImage: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        } else {
            StepFootnote("Recommended, so your shortcut works from the moment you sign in.")
        }
    }
}
