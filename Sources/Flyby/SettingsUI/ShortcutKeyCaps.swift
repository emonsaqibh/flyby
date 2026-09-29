import SwiftUI
import AppKit

/// One key, drawn like the key on a Mac keyboard: a soft-edged cap that sits
/// slightly proud of the surface. Modifiers carry their glyph top-right and
/// their name bottom-left, the way Apple prints them.
///
/// Made for Flyby's dark surfaces: a graphite cap whose top edge catches the
/// light, like the lit rim on the overlay's glass.
struct SettingsKeyCap: View {
    enum Size {
        /// The showcase: the current shortcut, large.
        case large
        /// Inline, beside a row's label.
        case small
    }

    let glyph: String
    /// "option", "right command"… Only modifiers have one, and only large
    /// caps show it.
    var name: String? = nil
    var size: Size = .large

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size == .large ? 9 : 5, style: .continuous)
        label
            .foregroundStyle(.white.opacity(0.92))
            .frame(minWidth: minWidth, minHeight: height, maxHeight: height)
            .background(shape.fill(Self.face))
            .overlay(shape.strokeBorder(Self.rim, lineWidth: size == .large ? 1 : 0.75))
            // The cap's lower edge, then its shadow on the surface.
            .shadow(color: .black.opacity(0.6), radius: 0, y: size == .large ? 2 : 1)
            .shadow(color: .black.opacity(0.35), radius: size == .large ? 6 : 2, y: size == .large ? 3 : 1)
    }

    @ViewBuilder
    private var label: some View {
        switch size {
        case .large:
            if let name {
                VStack(alignment: .leading, spacing: 0) {
                    Text(glyph)
                        .font(.system(size: 15, weight: .regular))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Spacer(minLength: 0)
                    Text(name)
                        .font(.system(size: 10.5, weight: .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 70)
            } else if isWide {
                // Space and the named keys, lowercase like onboarding's caps
                // and the legends on a Mac keyboard.
                Text(glyph.lowercased())
                    .font(.system(size: 13, weight: .regular))
                    .padding(.horizontal, 14)
                    .frame(minWidth: 96)
            } else {
                Text(glyph)
                    .font(.system(size: 20, weight: .regular))
                    .padding(.horizontal, 12)
            }
        case .small:
            Text(glyph)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 5)
        }
    }

    private var height: CGFloat { size == .large ? 48 : 20 }
    private var minWidth: CGFloat { size == .large ? 48 : 20 }
    /// "Space", "Page Up" — too long to set big. F-keys aren't.
    private var isWide: Bool { glyph.count > 3 }

    private static let face = LinearGradient(
        colors: [Color(white: 0.27), Color(white: 0.21)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Lit along the top edge, fading out down the sides.
    private static let rim = LinearGradient(
        colors: [.white.opacity(0.26), .white.opacity(0.07)],
        startPoint: .top,
        endPoint: .bottom
    )
}

// MARK: - A whole shortcut

/// A recorded shortcut as key caps — the answer to "what do I press?", which
/// a line of glyphs like "⌥/" only hints at. Told the way onboarding tells
/// it, in smaller and stiller caps.
struct ShortcutKeyCaps: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ModifierKey.all(in: shortcut.modifiers)) { key in
                SettingsKeyCap(glyph: key.glyph, name: key.name)
            }
            SettingsKeyCap(glyph: Shortcut.keyName(for: shortcut.keyCode))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.voiceOverDescription)
    }
}

/// A modifier as printed on the key, in the order macOS writes them.
private struct ModifierKey: Identifiable {
    let glyph: String
    let name: String
    var id: String { glyph }

    static let control = ModifierKey(glyph: "⌃", name: "control")
    static let option = ModifierKey(glyph: "⌥", name: "option")
    static let shift = ModifierKey(glyph: "⇧", name: "shift")
    static let command = ModifierKey(glyph: "⌘", name: "command")

    static func all(in flags: NSEvent.ModifierFlags) -> [ModifierKey] {
        var keys: [ModifierKey] = []
        if flags.contains(.control) { keys.append(.control) }
        if flags.contains(.option)  { keys.append(.option) }
        if flags.contains(.shift)   { keys.append(.shift) }
        if flags.contains(.command) { keys.append(.command) }
        return keys
    }
}

extension Shortcut {
    /// For VoiceOver, which reads glyphs like "⌥" unevenly: words only.
    var voiceOverDescription: String {
        let names = ModifierKey.all(in: modifiers).map(\.name.capitalized)
        return (names + [Shortcut.keyName(for: keyCode)]).joined(separator: " ")
    }
}
