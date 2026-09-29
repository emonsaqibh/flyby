import AppKit
import Carbon.HIToolbox

/// A user-recorded shortcut: a key and its modifiers — ⌥/, ⌥⇧Space.
///
/// Only key combos, deliberately. Carbon's `RegisterEventHotKey` delivers them
/// with no permission at all; a modifier-only gesture (a double-tap, a held
/// chord) needs an event tap, and on macOS 27 an event tap needs both
/// Accessibility and Input Monitoring — two grants to explain, lost on every
/// update of an app macOS doesn't recognise, for a gesture that's no quicker.
struct Shortcut: Equatable {
    let keyCode: UInt16
    /// Only ⌃ ⌥ ⇧ ⌘: whatever else an event carried (caps lock, fn, the
    /// device-dependent bits) isn't part of the shortcut.
    let modifiers: NSEvent.ModifierFlags

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.control, .option, .shift, .command])
    }

    /// ⌥/: rarely taken by anything else, one hand, no reach.
    static let `default` = Shortcut(keyCode: UInt16(kVK_ANSI_Slash), modifiers: .option)
    /// Screenshots the window you're in and opens Flyby with it.
    static let screenshotDefault = Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.option, .shift])
    /// What turning the screenshot shortcut on picks, in order, skipping any
    /// that's the one that opens Flyby.
    static let screenshotDefaults: [Shortcut] = [
        screenshotDefault,
        Shortcut(keyCode: UInt16(kVK_Space), modifiers: [.control, .option]),
        Shortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: [.control, .option]),
    ]

    var displayString: String {
        Shortcut.modifierSymbols(modifiers) + Shortcut.keyName(for: keyCode)
    }

    var explanation: String { "Press this to open Flyby." }

    // MARK: - Persistence

    /// Stored as a plist-safe dictionary rather than raw bits, so a future
    /// change doesn't silently reinterpret an old value. Double-taps and
    /// chords saved before 0.6 don't read back — the caller falls back to
    /// the default.
    var storage: [String: Any] {
        ["kind": "key", "keyCode": NSNumber(value: keyCode), "modifiers": NSNumber(value: modifiers.rawValue)]
    }

    init?(storage: [String: Any]) {
        guard storage["kind"] as? String == "key",
              let code = storage["keyCode"] as? NSNumber,
              let mods = storage["modifiers"] as? NSNumber else { return nil }
        self.init(keyCode: code.uint16Value, modifiers: NSEvent.ModifierFlags(rawValue: mods.uintValue))
    }

    /// Whether this was saved as a double-tap or a chord, which no longer
    /// exist — so whoever had one can be told what replaced it.
    static func isRetiredGesture(_ storage: [String: Any]) -> Bool {
        ["chord", "doubleTap"].contains(storage["kind"] as? String ?? "")
    }

    // MARK: - Validation

    /// Esc cancels recording rather than becoming a shortcut.
    static let escapeKeyCode = UInt16(kVK_Escape)

    /// Why a key combo would make a bad *global* shortcut, or nil if it's fine.
    ///
    /// A registered hot key is taken from every app on the Mac, so the combos
    /// worth refusing are the ones that would quietly break something else: a
    /// bare key or ⇧ plus a character (that's just typing), and the ⌘
    /// shortcuts every app and macOS itself already mean something by.
    static func rejectionReason(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        let modifiers = modifiers.intersection([.command, .option, .control, .shift])
        let combo = modifierSymbols(modifiers) + keyName(for: keyCode)

        if modifiers.isEmpty {
            return "Add ⌃, ⌥ or ⌘ — a key on its own would fire every time you type it."
        }

        let typed = namedKeys[keyCode] == nil ? Self.character(for: keyCode)?.lowercased() : nil
        if modifiers == .shift, typed != nil {
            return "\(combo) just types a character. Add ⌃, ⌥ or ⌘."
        }

        var meaning: String?
        if modifiers == .command {
            meaning = reservedCommandKeys[keyCode] ?? typed.flatMap { reservedCommandCharacters[$0] }
        } else if modifiers == [.command, .shift], let typed, ["3", "4", "5"].contains(typed) {
            meaning = "takes screenshots"
        } else if modifiers == [.command, .control], typed == "q" {
            meaning = "locks the screen"
        } else if modifiers == .control, keyCode == UInt16(kVK_Space) {
            meaning = "switches input sources"
        }
        guard let meaning else { return nil }
        let fix = modifiers == .command ? "Add ⌥ or ⌃ to make it yours." : "Try a different combo."
        return "\(combo) already \(meaning) everywhere. \(fix)"
    }

    /// ⌘ with these keys, by position: Tab, Space and ` aren't letters, so
    /// the layout doesn't move what they mean.
    private static let reservedCommandKeys: [UInt16: String] = [
        UInt16(kVK_Tab): "switches apps",
        UInt16(kVK_Space): "opens Spotlight",
        UInt16(kVK_ANSI_Grave): "cycles windows",
    ]

    /// ⌘ with these characters, whichever key types them — macOS matches menu
    /// shortcuts by character, so on AZERTY ⌘Q is where the Q is.
    private static let reservedCommandCharacters: [String: String] = [
        "q": "quits apps",
        "w": "closes windows",
        "c": "copies",
        "v": "pastes",
        "x": "cuts",
        "z": "undoes",
        "a": "selects all",
        "s": "saves",
        "n": "opens new windows",
        "t": "opens new tabs",
        "o": "opens files",
        "p": "prints",
        "f": "finds",
        "h": "hides apps",
        "m": "minimises windows",
        ",": "opens settings",
    ]

    // MARK: - Formatting

    static func modifierSymbols(_ modifiers: NSEvent.ModifierFlags) -> String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option)  { out += "⌥" }
        if modifiers.contains(.shift)   { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out
    }

    /// Names for the keys that don't print a useful character.
    private static let namedKeys: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "esc",
        UInt16(kVK_ANSI_KeypadClear): "⌧",
        UInt16(kVK_Help): "Help",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20",
    ]

    static func keyName(for keyCode: UInt16) -> String {
        if let named = namedKeys[keyCode] { return named }
        if let typed = Self.character(for: keyCode) { return typed.uppercased() }
        return "Key \(keyCode)"
    }

    /// What this key types on the current keyboard layout with no modifiers,
    /// so a Dvorak or AZERTY user sees their own legend rather than a QWERTY
    /// guess. Nil for keys that type nothing printable.
    static func character(for keyCode: UInt16) -> String? {
        guard let keyMap = currentLayoutData() else { return nil }
        let data = keyMap as Data

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(-1)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                // A bit *index*, not a mask: passing it raw asked for nothing.
                OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)
        // Return, Tab, Esc and friends translate to control characters, which
        // would draw as nothing (or as a box).
        let printable = string.unicodeScalars.contains { $0.value >= 0x20 && $0.value != 0x7F }
        return printable ? string : nil
    }

    /// The current layout's key map. Input methods — Japanese, Chinese,
    /// Korean — have none of their own, so fall back to the ASCII-capable
    /// layout they type through.
    private static func currentLayoutData() -> CFData? {
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = layoutData(of: source) {
            return data
        }
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
           let data = layoutData(of: source) {
            return data
        }
        return nil
    }

    private static func layoutData(of source: TISInputSource) -> CFData? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
    }
}
