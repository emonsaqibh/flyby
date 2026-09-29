import AppKit
import Carbon.HIToolbox
import os

/// Watches for one of the user's shortcuts — a key combo like ⌥/ — through
/// Carbon's `RegisterEventHotKey`, which needs no permission at all.
///
/// Flyby has two, each with a monitor of its own: the one that opens it and
/// the screenshot one. Every hot key the app registers arrives at every
/// handler, so each monitor answers only to its own number.
///
/// Main-actor bound: the Carbon handler is called on the main run loop, on
/// the application event target, so it hops in with `assumeIsolated`.
@MainActor
final class HotKeyMonitor {
    /// What `reload()` managed to do, which decides what the menu bar says.
    enum Status: Equatable {
        case active
        /// Deliberately off while the recorder has the keyboard.
        case paused
        /// A combo macOS wouldn't register — usually because another app
        /// already owns it. Waiting won't fix that; a different combo will.
        case unavailable(String)
        /// No shortcut is set: this one's been turned off.
        case off
    }

    var onTrigger: (@MainActor () -> Void)?

    /// Suspended while the user is recording a new shortcut, so the old one
    /// doesn't fire underneath the recorder. Pausing tears the hot key down
    /// rather than just ignoring it: a registered hot key swallows its
    /// keystroke before the recorder can see it, so re-recording the current
    /// combo would otherwise be impossible. Resuming is `reload()`.
    var isPaused = false {
        didSet {
            if isPaused, !oldValue { stop() }
        }
    }

    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Tells this monitor's hot key from any other the app has registered.
    nonisolated let hotKeyNumber: UInt32
    private let currentShortcut: @MainActor () -> Shortcut?

    private var shortcut: Shortcut? { currentShortcut() }

    /// The shortcut that opens Flyby, unless told which to watch.
    init(number: UInt32 = 1, shortcut: @escaping @MainActor () -> Shortcut? = { AppSettings.shared.shortcut }) {
        hotKeyNumber = number
        currentShortcut = shortcut
    }

    deinit {
        // The Carbon handler holds an unretained pointer to this object and
        // may not outlive it. Only the app delegate owns monitors, on the
        // main thread, so the check is belt and braces.
        if Thread.isMainThread {
            MainActor.assumeIsolated { stop() }
        }
    }

    /// Registers the current shortcut afresh. Does nothing but stay torn down
    /// while paused.
    @discardableResult
    func reload() -> Status {
        stop()
        guard !isPaused else { return .paused }
        guard let shortcut else { return .off }
        let status = register(shortcut)
        Self.log.info("""
        hotkey \(self.hotKeyNumber, privacy: .public) \(shortcut.displayString, privacy: .public) \
        status=\(String(describing: status), privacy: .public)
        """)
        return status
    }

    func stop() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func fire() {
        guard !isPaused else { return }
        Self.log.info("hotkey \(self.hotKeyNumber, privacy: .public) fired")
        // Off the event callback, so a slow window operation can't hold it up.
        Task { @MainActor [weak self] in self?.onTrigger?() }
    }

    private func register(_ shortcut: Shortcut) -> Status {
        var carbonModifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.option)  { carbonModifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.shift)   { carbonModifiers |= UInt32(shiftKey) }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            // Another monitor's hot key is passed on to its own handler.
            var pressed = EventHotKeyID()
            let read = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed
            )
            guard read == noErr, pressed.id == monitor.hotKeyNumber else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { monitor.fire() }
            return noErr
        }
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else {
            return .unavailable("macOS wouldn't let Flyby listen for hot keys (error \(installed)).")
        }

        // Four-char code 'QSch', just an identifier for our own hot keys.
        let id = EventHotKeyID(signature: OSType(0x5153_6368), id: hotKeyNumber)
        let registered = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr, hotKeyRef != nil else {
            let combo = shortcut.displayString
            if registered == OSStatus(eventHotKeyExistsErr) {
                return .unavailable("\(combo) is already taken by another app. Record a different shortcut.")
            }
            return .unavailable("macOS wouldn't register \(combo) (error \(registered)). Record a different shortcut.")
        }
        return .active
    }
}
