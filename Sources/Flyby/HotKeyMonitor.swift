import AppKit
import Carbon.HIToolbox
import os

/// Watches for the user's recorded trigger, using whichever of two mechanisms
/// that trigger actually needs.
///
/// A key combo (⌥/, ⌘⇧K) goes through Carbon's `RegisterEventHotKey`, which
/// needs **no** permissions at all. A modifier-only gesture — a held chord or
/// a double-tap — needs a `CGEventTap`: `RegisterEventHotKey` can't express
/// "no key at all", and it can't tell Right ⌘ from Left ⌘ either. Taps are
/// gated behind Accessibility, so picking the cheaper mechanism per shortcut
/// means key-combo users never see a permission prompt.
///
/// Main-actor bound. Both callbacks are delivered on the main run loop — the
/// Carbon handler on the application event target, the tap through a source
/// added to the main run loop — so they hop in with `assumeIsolated`.
@MainActor
final class HotKeyMonitor {
    /// What `reload()` managed to do, which decides what the menu bar says.
    enum Status: Equatable {
        case active
        /// Deliberately off while the recorder has the keyboard.
        case paused
        /// A modifier-only gesture, and no Accessibility grant to watch for it.
        case needsAccessibility
        /// A key combo macOS wouldn't register — usually because another app
        /// already owns it. Polling won't fix that; a different combo will.
        case unavailable(String)
        /// No shortcut is set: this one's been turned off.
        case off
    }

    var onTrigger: (@MainActor () -> Void)?

    /// The tap stopped working while running — Accessibility was revoked, or
    /// macOS disabled the tap for good. The owner should say so and start
    /// polling for the grant again.
    var onAccessibilityLost: (@MainActor () -> Void)?

    /// Suspended while the user is recording a new shortcut, so the old one
    /// doesn't fire underneath the recorder. Pausing tears the hot key down
    /// rather than just ignoring it: a registered Carbon hot key swallows its
    /// keystroke before the recorder can see it, so re-recording the current
    /// combo would otherwise be impossible. Resuming is `reload()`.
    var isPaused = false {
        didSet {
            if isPaused, !oldValue { stop() }
        }
    }

    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "hotkey")

    // Tap path (chords and double-taps).
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthCheck: Task<Void, Never>?
    private var armed = true

    // Double-tap state: a "tap" is the modifier going down and up on its own —
    // no other modifier held, no key pressed while it was down, and briefly
    // enough that it can't have been an option-drag. Times are event
    // timestamps (seconds since boot), not when the callback happened to run.
    private var tapDownPending = false
    private var tapDownTime: TimeInterval = 0
    private var lastTapUpTime: TimeInterval?
    private static let doubleTapWindow: TimeInterval = 0.35
    private static let maxTapHold: TimeInterval = 0.4

    /// Accessibility can be revoked while we run, and macOS doesn't tell the
    /// tap — it just goes quiet. Cheap enough to check this often, and only
    /// while a tap is actually in use.
    private static let healthCheckInterval: UInt64 = 3_000_000_000

    // Carbon path (key combos only).
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Tells this monitor's Carbon hot key from any other the app has
    /// registered: every one of them arrives at the same handler.
    nonisolated let hotKeyNumber: UInt32
    private let currentShortcut: @MainActor () -> Shortcut?

    private var shortcut: Shortcut? { currentShortcut() }

    /// The shortcut that opens Flyby, unless told which to watch.
    init(number: UInt32 = 1, shortcut: @escaping @MainActor () -> Shortcut? = { AppSettings.shared.shortcut }) {
        hotKeyNumber = number
        currentShortcut = shortcut
    }

    deinit {
        // The Carbon handler and the tap both hold an unretained pointer to
        // this object; neither may outlive it. Only the app delegate owns one,
        // on the main thread, so the check is belt and braces.
        if Thread.isMainThread {
            MainActor.assumeIsolated { stop() }
        }
    }

    /// True when the current shortcut can only be delivered by an event tap.
    var requiresAccessibility: Bool {
        switch shortcut {
        case .modifierChord, .doubleTap: return true
        case .keyCombo, nil:             return false
        }
    }

    var isInstalled: Bool { tap != nil || hotKeyRef != nil }

    /// Rebuilds for the current shortcut — the two mechanisms aren't
    /// interchangeable, so this can't just re-read a mask. Does nothing but
    /// stay torn down while paused.
    @discardableResult
    func reload() -> Status {
        stop()
        armed = true
        tapDownPending = false
        lastTapUpTime = nil
        guard !isPaused else { return .paused }
        guard let shortcut else { return .off }

        switch shortcut {
        case .keyCombo(let keyCode, let modifiers):
            let status = installCarbonHotKey(keyCode: keyCode, modifiers: modifiers)
            Self.log.info("""
            carbon hotkey keyCode=\(keyCode, privacy: .public) \
            modifiers=\(modifiers.rawValue, privacy: .public) \
            status=\(String(describing: status), privacy: .public)
            """)
            return status

        case .modifierChord, .doubleTap:
            let ok = installEventTap()
            Self.log.info("""
            event tap installed=\(ok, privacy: .public) \
            trusted=\(Self.isTrusted, privacy: .public)
            """)
            return ok ? .active : .needsAccessibility
        }
    }

    func stop() {
        healthCheck?.cancel()
        healthCheck = nil

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // Without this the port lives on in the kernel, still attached to
            // the event stream, until the process exits.
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil

        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func fire() {
        guard !isPaused else { return }
        Self.log.info("trigger fired")
        // Off the event callback, so a slow window operation can't hold up the
        // tap and get it disabled for timing out.
        Task { @MainActor [weak self] in self?.onTrigger?() }
    }

    // MARK: - Carbon hot key (no permission required)

    private func installCarbonHotKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Status {
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option)  { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift)   { carbonModifiers |= UInt32(shiftKey) }

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            // Every hot key the app registered comes through every handler;
            // another monitor's is passed on to its own.
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

        // Four-char code 'QSch', just an identifier for our own hot key.
        let id = EventHotKeyID(signature: OSType(0x5153_6368), id: hotKeyNumber)
        let registered = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr, hotKeyRef != nil else {
            let combo = Shortcut.keyCombo(keyCode: keyCode, modifiers: modifiers).displayString
            if registered == OSStatus(eventHotKeyExistsErr) {
                return .unavailable("\(combo) is already taken by another app. Record a different shortcut.")
            }
            return .unavailable("macOS wouldn't register \(combo) (error \(registered)). Record a different shortcut.")
        }
        return .active
    }

    // MARK: - Event tap (chords and double-taps, needs Accessibility)

    private func installEventTap() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            if let refcon {
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handleTapEvent(type: type, event: event) }
            }
            return Unmanaged.passUnretained(event)
        }

        // flagsChanged only. Adding keyDown here would drag in a second
        // permission (Input Monitoring) on top of Accessibility.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source
        startHealthCheck()
        return true
    }

    private func startHealthCheck() {
        healthCheck?.cancel()
        healthCheck = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.healthCheckInterval)
                guard !Task.isCancelled, let self else { return }
                self.checkTapHealth()
            }
        }
    }

    private func checkTapHealth() {
        guard let tap else { return }
        if Self.isTrusted, CGEvent.tapIsEnabled(tap: tap) { return }

        // Still trusted but switched off: macOS gave up on it for some reason
        // the disabled-by events didn't cover. One more try.
        if Self.isTrusted {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
        }

        Self.log.error("event tap lost trusted=\(Self.isTrusted, privacy: .public); stopping")
        stop()
        onAccessibilityLost?()
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        // macOS disables taps that take too long; just switch it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged, !isPaused else { return }

        switch shortcut {
        case .modifierChord(let keys):
            handleChord(keys: keys, event: event)
        case .doubleTap(let key):
            handleDoubleTap(key: key, event: event)
        case .keyCombo, nil:
            return
        }
    }

    private func handleChord(keys: Set<TriggerKey>, event: CGEvent) {
        let flags = event.flags.rawValue
        if keys.allSatisfy({ (flags & $0.rawValue) != 0 }) {
            guard armed else { return }
            armed = false
            fire()
        } else {
            // Re-arm only once the chord is released, so holding the keys down
            // doesn't machine-gun Flyby open.
            armed = true
        }
    }

    private func handleDoubleTap(key: TriggerKey, event: CGEvent) {
        let flags = event.flags.rawValue
        let keyIsDown = (flags & key.rawValue) != 0
        let otherModifierDown = TriggerKey.allCases.contains {
            $0 != key && (flags & $0.rawValue) != 0
        }

        // A second modifier in play makes this a chord of some kind, not a tap.
        if otherModifierDown {
            tapDownPending = false
            lastTapUpTime = nil
            return
        }

        let now = Self.timestamp(of: event)
        if keyIsDown, !tapDownPending {
            tapDownPending = true
            tapDownTime = now
        } else if !keyIsDown, tapDownPending {
            tapDownPending = false
            let held = now - tapDownTime

            // Held too long to be a tap (an option-drag, a change of heart), or
            // a key went down while it was held — Right ⌥ as AltGr, typing "@"
            // on a German layout or "ą" on a Polish one. Either way, not a tap.
            guard held <= Self.maxTapHold, !Self.keyWasPressed(within: held) else {
                lastTapUpTime = nil
                return
            }

            if let last = lastTapUpTime, now - last <= Self.doubleTapWindow {
                lastTapUpTime = nil
                fire()
            } else {
                lastTapUpTime = now
            }
        }
    }

    /// Seconds since boot, as AppKit reports it. `CGEvent.timestamp`'s raw
    /// units differ between Intel and Apple silicon; `NSEvent` converts.
    private static func timestamp(of event: CGEvent) -> TimeInterval {
        NSEvent(cgEvent: event)?.timestamp ?? ProcessInfo.processInfo.systemUptime
    }

    /// Whether any key went down in the last `interval` seconds. Asks the
    /// window server rather than watching keyDown ourselves, which would need
    /// Input Monitoring. A reading of zero is treated as "don't know" rather
    /// than "just now", so an OS that withholds the answer can't turn every
    /// tap into a rejected one.
    private static func keyWasPressed(within interval: TimeInterval) -> Bool {
        let since = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        return since > 0.001 && since < interval
    }

    // MARK: - Permission

    nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility access if we don't have it yet.
    @discardableResult
    nonisolated static func ensureAccessibilityPermission() -> Bool {
        // The string behind `kAXTrustedCheckOptionPrompt`, spelled out: the
        // imported global is a mutable C var, which strict concurrency rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
