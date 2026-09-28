import SwiftUI

/// Every key Flyby answers to while it's open, in one list — what the
/// shortcuts overlay (⌘/) shows, with the slash commands under it. The app
/// delegate's key monitor is what makes them work; the two are kept in step
/// by hand, so change both.
enum KeyboardMap {
    struct Shortcut: Identifiable {
        let keys: String
        let action: String
        var id: String { keys + action }
    }

    struct Group: Identifiable {
        let title: String
        let shortcuts: [Shortcut]
        var id: String { title }
    }

    static let asking = Group(title: "Ask", shortcuts: [
        Shortcut(keys: "↩", action: "Ask, or ask a follow-up"),
        Shortcut(keys: "⌥↩", action: "New line"),
        Shortcut(keys: "⌘↩", action: "Open in your browser"),
        Shortcut(keys: "⌘K", action: "Provider menu"),
        Shortcut(keys: "⌘1 – ⌘4", action: "Switch provider"),
    ])

    static let answering = Group(title: "Answer", shortcuts: [
        Shortcut(keys: "⌘.", action: "Stop"),
        Shortcut(keys: "⌘R", action: "Search again"),
        Shortcut(keys: "⇧⌘C", action: "Copy the answer"),
        Shortcut(keys: "⌘N", action: "New chat"),
    ])

    static let reading = Group(title: "Read", shortcuts: [
        Shortcut(keys: "esc", action: "Leave the field to read"),
        Shortcut(keys: "↑ ↓", action: "Scroll"),
        Shortcut(keys: "space", action: "Page down, ⇧ for up"),
        Shortcut(keys: "⇞ ⇟", action: "Page up, page down"),
        Shortcut(keys: "⌘↑ ⌘↓", action: "Top, bottom"),
        Shortcut(keys: "⇥ tab", action: "Back to the field"),
    ])

    static let history = Group(title: "Recent chats", shortcuts: [
        Shortcut(keys: "⌘Y", action: "Show or hide; ↑ when empty"),
        Shortcut(keys: "↑ ↓", action: "Move"),
        Shortcut(keys: "↩", action: "Open"),
        Shortcut(keys: "⌘⌫", action: "Delete"),
        Shortcut(keys: "esc", action: "Back"),
    ])

    static let flyby = Group(title: "Flyby", shortcuts: [
        Shortcut(keys: "esc", action: "Close (bar, or reading)"),
        Shortcut(keys: "⌘W", action: "Close"),
        Shortcut(keys: "⌘/", action: "These shortcuts"),
        Shortcut(keys: "⌘,", action: "Settings"),
    ])
}

/// A key, drawn the way a hint draws one: small, on a faint well, so it
/// reads as "press this" rather than as text.
struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            )
            .fixedSize()
    }
}

/// Every shortcut on one small smoked card, over the bar or the card — ⌘/,
/// the Shortcuts pill, or /shortcuts. Esc, ⌘/ or a click puts it away.
struct ShortcutsOverlay: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Keycap("esc")
                Text("to close")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    group(KeyboardMap.asking)
                    group(KeyboardMap.answering)
                    group(KeyboardMap.flyby)
                }
                VStack(alignment: .leading, spacing: 14) {
                    group(KeyboardMap.reading)
                    group(KeyboardMap.history)
                }
            }

            commands
        }
        .padding(18)
        .frame(width: InputMetrics.width)
        .surface(RoundedRectangle(cornerRadius: CardMetrics.cornerRadius - 6, style: .continuous), style: .smoke)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
    }

    /// The slash commands, as the words to type: each one's description is
    /// in the list that "/" opens.
    private var commands: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Commands")
            HStack(spacing: 5) {
                Text("Type")
                Keycap("/")
                Text("at the start of the field — ↑ ↓ to pick, ↩ or ⇥ to run, esc to hide the list.")
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
            .foregroundStyle(.primary.opacity(0.9))
            FlowLayout(spacing: 5) {
                ForEach(SlashCommand.all) { command in
                    Keycap("/\(command.name)")
                        .help(command.summary)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.bottom, 1)
    }

    private func group(_ group: KeyboardMap.Group) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionTitle(group.title)
            ForEach(group.shortcuts) { shortcut in
                HStack(spacing: 8) {
                    Keycap(shortcut.keys)
                        .frame(width: 68, alignment: .trailing)
                    Text(shortcut.action)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
