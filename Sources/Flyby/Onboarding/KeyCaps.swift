import SwiftUI
import AppKit

// The shortcut drawn as the keys you'd press — and pressing them — so the
// gesture is shown rather than spelled out.

// MARK: - Model

/// One key as a Mac keyboard prints it: a modifier's symbol in the top
/// corner and its name along the bottom; a character, big in the middle.
struct KeyCapFace: Hashable {
    enum Kind: Hashable {
        case modifier(symbol: String)
        case character
        /// Space, and named keys too long to set big.
        case wide
    }

    let kind: Kind
    let name: String
    /// What the small recap cap says.
    let short: String
}

extension Shortcut {
    var keyCaps: [KeyCapFace] {
        KeyCapFace.modifiers(modifiers) + [KeyCapFace.key(Shortcut.keyName(for: keyCode))]
    }

    /// Said to VoiceOver in place of the drawn keys.
    var spokenDescription: String {
        (KeyCapFace.modifiers(modifiers).map(\.name) + [Shortcut.keyName(for: keyCode)]).joined(separator: " ")
    }
}

private extension KeyCapFace {
    /// In the order macOS writes them: ⌃ ⌥ ⇧ ⌘.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> [KeyCapFace] {
        let all: [(NSEvent.ModifierFlags, String, String)] = [
            (.control, "⌃", "control"),
            (.option, "⌥", "option"),
            (.shift, "⇧", "shift"),
            (.command, "⌘", "command"),
        ]
        return all.filter { flags.contains($0.0) }.map {
            KeyCapFace(kind: .modifier(symbol: $0.1), name: $0.2, short: $0.1)
        }
    }

    static func key(_ name: String) -> KeyCapFace {
        let kind: Kind = name.count <= 3 ? .character : .wide
        return KeyCapFace(kind: kind, name: kind == .wide ? name.lowercased() : name, short: name)
    }
}

// MARK: - Caps

/// The shortcut's keys, big and glassy, optionally acting the gesture out.
struct KeyCapsView: View {
    enum Mode: Equatable {
        /// Plays the combo on a loop: modifiers held, then the key.
        case demonstrate
        /// Waiting for the user to do it: a slow, soft pulse of light.
        case waiting
        /// Just done: every key lights up and presses at once.
        case celebrating
    }

    let shortcut: Shortcut
    var mode: Mode = .demonstrate

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed: Set<Int> = []
    @State private var breathing = false

    var body: some View {
        let caps = shortcut.keyCaps
        HStack(spacing: 14) {
            ForEach(Array(caps.enumerated()), id: \.offset) { index, face in
                KeyCap(
                    face: face,
                    isPressed: pressed.contains(index) || mode == .celebrating,
                    isLit: mode == .celebrating,
                    glow: glow(pressed: pressed.contains(index))
                )
            }
        }
        .task(id: mode) { await play(caps: caps.count) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.spokenDescription)
    }

    private func glow(pressed: Bool) -> Double {
        switch mode {
        case .celebrating: return 1
        case .waiting:     return breathing ? 0.75 : 0.15
        case .demonstrate: return pressed ? 0.45 : 0
        }
    }

    private func play(caps count: Int) async {
        pressed = []
        breathing = false
        guard !reduceMotion else { return }
        switch mode {
        case .celebrating:
            return
        case .waiting:
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
        case .demonstrate:
            // Lets the step finish arriving before the keys start moving.
            try? await Task.sleep(for: .seconds(1.1))
            while !Task.isCancelled {
                await demonstrate(count)
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    /// The modifiers held, then the key pressed.
    private func demonstrate(_ count: Int) async {
        for index in 0..<(count - 1) {
            hold(index)
            try? await Task.sleep(for: .seconds(0.14))
        }
        try? await Task.sleep(for: .seconds(0.12))
        await press([count - 1], for: 0.16)
        try? await Task.sleep(for: .seconds(0.2))
        withAnimation(.spring(duration: 0.3, bounce: 0.35)) { pressed = [] }
    }

    private func press(_ indices: Set<Int>, for duration: TimeInterval) async {
        withAnimation(.spring(duration: 0.14, bounce: 0.2)) { pressed.formUnion(indices) }
        try? await Task.sleep(for: .seconds(duration))
        withAnimation(.spring(duration: 0.3, bounce: 0.45)) { pressed.subtract(indices) }
    }

    /// Down, and staying down until the whole gesture lets go.
    private func hold(_ index: Int) {
        withAnimation(.spring(duration: 0.16, bounce: 0.2)) { _ = pressed.insert(index) }
    }
}

/// One glass key, white-legended like a Mac's. Pressed, it sinks a couple of
/// points and its shadow tightens; glowing, the accent haloes it; lit, it
/// fills with the accent like a backlit key — the practice step's flash.
struct KeyCap: View {
    let face: KeyCapFace
    var isPressed = false
    var isLit = false
    /// The accent halo, 0…1.
    var glow: Double = 0

    private static let height: CGFloat = 84
    private static let radius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        label
            .frame(width: width, height: Self.height)
            .foregroundStyle(.white)
            .background {
                // A keycap's sheen: catching light along the top, falling
                // off toward the bottom.
                shape.fill(
                    LinearGradient(
                        colors: [.white.opacity(isPressed ? 0.06 : 0.12), .white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                shape.fill(Color.accentColor.opacity(isLit ? 0.8 : 0))
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
            }
            .overlay {
                shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .opacity(isLit ? 0 : glow * 0.8)
            }
            .paneGlass(shape)
            .background {
                // The key's shadow on the "keyboard": deep at rest, tight
                // when pressed — the cheapest convincing sense of travel.
                shape
                    .fill(.black.opacity(isPressed ? 0.3 : 0.45))
                    .blur(radius: isPressed ? 4 : 12)
                    .offset(y: isPressed ? 2 : 9)
                    .padding(.horizontal, 8)
            }
            .shadow(color: Color.accentColor.opacity(0.6 * glow), radius: 10 + 14 * glow)
            .scaleEffect(isPressed ? 0.95 : 1)
            .offset(y: isPressed ? 3 : 0)
    }

    private var width: CGFloat {
        switch face.kind {
        case .modifier:  return 112
        case .character: return 84
        case .wide:      return max(150, CGFloat(face.name.count) * 14 + 60)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch face.kind {
        case .modifier(let symbol):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Text(symbol).font(.system(size: 24, weight: .regular))
                }
                Spacer(minLength: 0)
                Text(face.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
        case .character:
            Text(face.name)
                .font(.system(size: 30, weight: .medium))
        case .wide:
            Text(face.name)
                .font(.system(size: 15, weight: .medium))
        }
    }
}

/// The shortcut in small, quiet caps, for a line of text rather than a stage.
struct MiniKeyCaps: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(shortcut.keyCaps.enumerated()), id: \.offset) { _, face in
                Text(face.short)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(minWidth: 24, minHeight: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.spokenDescription)
    }
}
