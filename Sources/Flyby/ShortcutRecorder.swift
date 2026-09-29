import SwiftUI
import AppKit
import Combine

/// Click, press a key with modifiers, done — ⌥/, ⌃⌥Space. Shortcuts are key
/// combos only (see `Shortcut`); modifiers on their own get a hint.
///
/// Recording pauses the live hot key (through `onRecordingChanged`), so it
/// must always end: on commit, Esc or Cancel, and also whenever the recorder
/// disappears or its window stops being key — closing Settings, switching
/// tabs, or Continue in onboarding would otherwise leave the shortcut dead.
struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    /// What Reset goes back to.
    let defaultShortcut: Shortcut
    /// Why a shortcut can't be this one — it's the other shortcut's, say —
    /// or nil. A refused one is said under the field and recording goes on.
    let conflict: (Shortcut) -> String?
    var onRecordingChanged: (Bool) -> Void

    @State private var isRecording = false
    /// Modifiers down right now, for the live label.
    @State private var heldModifiers: NSEvent.ModifierFlags = []
    /// A key went down while the modifiers were held, so letting them go was
    /// the end of a combo, not modifiers on their own.
    @State private var gestureHadKey = false
    /// Why the last attempt was refused, shown under the field.
    @State private var hint: String?
    /// Tells this recorder from any other on screen: one records at a time.
    @State private var recorderID = UUID()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        shortcut: Binding<Shortcut>,
        defaultShortcut: Shortcut = .default,
        conflict: @escaping (Shortcut) -> String? = { _ in nil },
        onRecordingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _shortcut = shortcut
        self.defaultShortcut = defaultShortcut
        self.conflict = conflict
        self.onRecordingChanged = onRecordingChanged
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field

            if isRecording, let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: isRecording)
        .animation(.smooth(duration: 0.2), value: hint)
        .background(
            KeyCaptureView(
                isRecording: isRecording,
                onModifiers: handleModifiers,
                onKey: handleKey,
                onWindowResignedKey: { setRecording(false) }
            )
            .frame(width: 0, height: 0)
        )
        .onAppear(perform: startRecordingIfDebugging)
        .onDisappear { setRecording(false) }
        .onReceive(NotificationCenter.default.publisher(for: .flybyRecorderDidStart)) { note in
            if (note.object as? UUID) != recorderID { setRecording(false) }
        }
    }

    /// A field-shaped control, like the shortcut fields in System Settings:
    /// the shortcut in the middle, a keyboard glyph that picks up a pulsing
    /// ellipsis while listening, and — like a search field's clear button —
    /// Reset or Cancel tucked inside the trailing edge.
    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(spacing: 6) {
            Button {
                setRecording(!isRecording)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isRecording ? "keyboard.badge.ellipsis" : "keyboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isRecording ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, isActive: isRecording && !reduceMotion)
                        .frame(width: 16)

                    Text(label)
                        .font(.system(size: 13, weight: isRecording ? .regular : .medium))
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.opacity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Recording a new shortcut" : "Shortcut, \(shortcut.voiceOverDescription)")
            .accessibilityHint(isRecording ? "Press the new shortcut, or Escape to cancel." : "Records a new shortcut.")

            trailingButton
                .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(shape.fill(isRecording ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.fill.tertiary)))
        .overlay(
            shape.strokeBorder(
                isRecording ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator),
                lineWidth: isRecording ? 1.5 : 0.5
            )
        )
    }

    /// Cancel while listening; Reset once there's something to reset. The
    /// slot stays reserved either way, so the label doesn't jump sideways.
    @ViewBuilder
    private var trailingButton: some View {
        if isRecording {
            fieldButton("xmark.circle.fill", help: "Cancel") { setRecording(false) }
        } else if shortcut != defaultShortcut {
            // Not while the default is the other shortcut's.
            let blocked = conflict(defaultShortcut)
            fieldButton("arrow.counterclockwise.circle.fill", help: blocked ?? "Reset to \(defaultShortcut.voiceOverDescription)") {
                shortcut = defaultShortcut
            }
            .disabled(blocked != nil)
            .opacity(blocked == nil ? 1 : 0.35)
        } else {
            Color.clear
        }
    }

    private func fieldButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .transition(.opacity)
    }

    private var label: String {
        if isRecording {
            if !heldModifiers.isEmpty {
                return Shortcut.modifierSymbols(heldModifiers) + " …"
            }
            return "Press a shortcut…"
        }
        return shortcut.displayString
    }

    /// Dev builds only: `-FlybyDebugRecording 1` opens the recorder already
    /// listening, so its recording state can be looked at (and screenshotted)
    /// without clicking.
    private func startRecordingIfDebugging() {
        guard BuildFlavor.isDev, UserDefaults.standard.bool(forKey: "FlybyDebugRecording") else { return }
        setRecording(true)
    }

    /// Idempotent, so every exit path can call it without double-reporting.
    private func setRecording(_ recording: Bool) {
        heldModifiers = []
        gestureHadKey = false
        hint = nil
        guard recording != isRecording else { return }
        isRecording = recording
        if recording {
            NotificationCenter.default.post(name: .flybyRecorderDidStart, object: recorderID)
        }
        onRecordingChanged(recording)
    }

    private func handleKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard isRecording else { return }
        if keyCode == Shortcut.escapeKeyCode {  // Cancels rather than becoming the shortcut.
            setRecording(false)
            return
        }
        gestureHadKey = true
        if let reason = Shortcut.rejectionReason(keyCode: keyCode, modifiers: modifiers) {
            hint = reason
            return
        }
        commit(Shortcut(keyCode: keyCode, modifiers: modifiers))
    }

    /// The recorded shortcut, unless it's taken: then why, under the field,
    /// and still listening.
    private func commit(_ candidate: Shortcut) {
        if let reason = conflict(candidate) {
            hint = reason
            return
        }
        shortcut = candidate
        setRecording(false)
    }

    /// Held modifiers show in the field as they go down. Let go with no key
    /// in between — a double-tap, a chord, from before shortcuts were key
    /// combos only — and the field says what it's waiting for.
    private func handleModifiers(_ pressed: NSEvent.ModifierFlags) {
        guard isRecording else { return }
        let starting = !pressed.isEmpty && heldModifiers.isEmpty
        let released = pressed.isEmpty && !heldModifiers.isEmpty
        heldModifiers = pressed
        if starting { gestureHadKey = false }
        if released, !gestureHadKey {
            hint = "Hold the modifiers and press a key too — like ⌥/."
        }
    }
}

/// An invisible NSView that grabs key events while recording. SwiftUI's
/// `onKeyPress` never sees bare modifier changes, which the live label shows.
///
/// The monitor is app-wide by nature, so it only acts on events addressed to
/// the recorder's own window — anything else, like typing in Flyby while
/// Settings is recording, passes through untouched.
private struct KeyCaptureView: NSViewRepresentable {
    let isRecording: Bool
    let onModifiers: (NSEvent.ModifierFlags) -> Void
    let onKey: (UInt16, NSEvent.ModifierFlags) -> Void
    let onWindowResignedKey: () -> Void

    func makeNSView(context: Context) -> WindowTrackingView {
        let view = WindowTrackingView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.attach()
        return view
    }

    func updateNSView(_ nsView: WindowTrackingView, context: Context) {
        context.coordinator.onModifiers = onModifiers
        context.coordinator.onKey = onKey
        context.coordinator.onWindowResignedKey = onWindowResignedKey
        context.coordinator.isRecording = isRecording
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onModifiers: onModifiers, onKey: onKey, onWindowResignedKey: onWindowResignedKey)
    }

    static func dismantleNSView(_ nsView: WindowTrackingView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Reports which window it lands in, which is how the coordinator knows
    /// what "our window" means.
    final class WindowTrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.windowDidChange(window)
        }
    }

    @MainActor
    final class Coordinator {
        var isRecording = false
        var onModifiers: (NSEvent.ModifierFlags) -> Void
        var onKey: (UInt16, NSEvent.ModifierFlags) -> Void
        var onWindowResignedKey: () -> Void
        weak var view: NSView?
        private var monitor: Any?
        private var resignObserver: AnyCancellable?

        init(onModifiers: @escaping (NSEvent.ModifierFlags) -> Void,
             onKey: @escaping (UInt16, NSEvent.ModifierFlags) -> Void,
             onWindowResignedKey: @escaping () -> Void) {
            self.onModifiers = onModifiers
            self.onKey = onKey
            self.onWindowResignedKey = onWindowResignedKey
        }

        func attach() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                // Local monitors run on the main thread.
                let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                // Swallowed so the shortcut doesn't leak into the UI.
                return consumed ? nil : event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            resignObserver = nil
        }

        /// Losing key status means the user has gone elsewhere — another
        /// window, another app, or the window closing — and a recorder they
        /// can't see shouldn't keep the hot key paused.
        func windowDidChange(_ window: NSWindow?) {
            resignObserver = nil
            guard let window else { return }
            resignObserver = NotificationCenter.default
                .publisher(for: NSWindow.didResignKeyNotification, object: window)
                .sink { [weak self] _ in
                    guard let self, self.isRecording else { return }
                    self.onWindowResignedKey()
                }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard isRecording,
                  let window = view?.window,
                  event.window === window
            else { return false }

            switch event.type {
            case .flagsChanged:
                onModifiers(event.modifierFlags.intersection([.command, .option, .control, .shift]))
                return true
            case .keyDown:
                onKey(
                    event.keyCode,
                    event.modifierFlags
                        .intersection(.deviceIndependentFlagsMask)
                        .intersection([.command, .option, .control, .shift])
                )
                return true
            default:
                return false
            }
        }
    }
}

extension Notification.Name {
    /// A shortcut recorder started listening; any other stops.
    static let flybyRecorderDidStart = Notification.Name("flybyRecorderDidStart")
}
