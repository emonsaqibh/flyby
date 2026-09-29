import SwiftUI

// The second half: the shortcut that summons Flyby, tried for real, and the
// send-off.

// MARK: - Practice

/// Proof it all works: the user fires the real shortcut, and Flyby appears.
/// The whole trick, tried for real: the shortcut opens the actual bar, and
/// Esc puts it away — which is when it's learned. The bar takes no questions
/// until setup is done. The recorder is a click away for anyone who wants
/// other keys, and out on its own when the shortcut is taken by another app.
struct PracticeStep: View {
    @ObservedObject var settings: AppSettings
    /// The bar is open, waiting for Esc.
    let opened: Bool
    let succeeded: Bool
    /// Pauses the live hot keys while the recorder is armed.
    let onRecordingChanged: (Bool) -> Void

    @ObservedObject private var health = ShortcutHealthModel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Trails `succeeded` by a beat, so the keys get their flash before the
    /// check takes their place.
    @State private var showsCheck = false
    @State private var changing = false

    private var shortcut: Shortcut { settings.shortcut }
    private static let escape = Shortcut(keyCode: Shortcut.escapeKeyCode, modifiers: [])

    private var title: String {
        if succeeded { return "You've got it!" }
        return opened ? "Now press esc" : "Summon Flyby from anywhere"
    }

    private var subtitle: String {
        if succeeded { return "\(shortcut.displayString) to open, esc to put it away — over whatever you're doing." }
        return opened
            ? "That puts Flyby away again. So does \(shortcut.displayString)."
            : "Press \(shortcut.displayString) to open it."
    }

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(title: title, subtitle: subtitle)

            ZStack {
                // The keys to press now: the shortcut, then esc; lit once done.
                KeyCapsView(shortcut: opened && !succeeded ? Self.escape : shortcut, mode: succeeded ? .celebrating : .waiting)
                    .id(opened && !succeeded ? "esc" : shortcut.displayString)
                    .transition(SoftSwapTransition())
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
                .padding(.top, 22)

            change
                .reveal(.footnote)
                .padding(.top, 16)
        }
        .animation(.smooth(duration: 0.4), value: shortcut)
        .animation(.smooth(duration: 0.4), value: opened)
        .animation(.smooth(duration: 0.3), value: changing)
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
        Label(opened ? "Waiting for esc…" : "Listening for your shortcut…", systemImage: "dot.radiowaves.left.and.right")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .symbolEffect(.variableColor.iterative, isActive: !succeeded && !reduceMotion)
            .opacity(succeeded ? 0 : 1)
            .animation(.smooth(duration: 0.3), value: succeeded)
    }

    /// Other keys, if the user wants them — or needs them, when another app
    /// has these.
    @ViewBuilder
    private var change: some View {
        if changing || health.main != nil {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Text("Shortcut")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    ShortcutRecorder(
                        shortcut: settings.shortcutBinding,
                        conflict: { settings.conflict(forShortcut: $0) },
                        onRecordingChanged: onRecordingChanged
                    )
                    .frame(width: 260)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .paneGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))

                if let reason = health.main {
                    ShortcutProblemNote(reason: reason)
                        .frame(width: 420)
                }
            }
            .transition(SoftSwapTransition())
        } else {
            Button("Use a different shortcut") { changing = true }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .transition(SoftSwapTransition())
        }
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

                recapRow("Screenshot", badge: IconBadge("camera.viewfinder", color: .orange, size: 26)) {
                    if let shortcut = settings.screenshotShortcut {
                        MiniKeyCaps(shortcut: shortcut)
                    } else {
                        Text("Off")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
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
