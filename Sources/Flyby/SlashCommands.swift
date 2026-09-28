import SwiftUI

/// Commands typed into the input. A "/" at the start opens a list of them
/// above the input, filtered as you type; Return or Tab runs the highlighted
/// one, ↑↓ move, Esc puts the list away. When nothing matches, the text is
/// just a question — "/etc/hosts" still searches.
///
/// Each is a door to something that already exists — Settings, the history
/// list, a provider — never a new feature of its own.
struct SlashCommand: Identifiable, Equatable {
    enum Action: Equatable {
        case settings, history, shortcuts, newChat, retry, copy
        case provider(ProviderKind)
    }

    let name: String
    let summary: String
    let symbol: String
    let action: Action

    var id: String { name }

    /// In the order the list shows them when only "/" is typed.
    static let all: [SlashCommand] = [
        SlashCommand(name: "google", summary: "Answer with Google AI Mode", symbol: ProviderKind.aiMode.icon, action: .provider(.aiMode)),
        SlashCommand(name: "gemini", summary: "Answer with Gemini", symbol: ProviderKind.gemini.icon, action: .provider(.gemini)),
        SlashCommand(name: "apple", summary: "Answer with Apple Intelligence", symbol: ProviderKind.appleIntelligence.icon, action: .provider(.appleIntelligence)),
        SlashCommand(name: "browser", summary: "Search in your browser", symbol: ProviderKind.browser.icon, action: .provider(.browser)),
        SlashCommand(name: "new", summary: "Start a new chat", symbol: "square.and.pencil", action: .newChat),
        SlashCommand(name: "retry", summary: "Search again", symbol: "arrow.clockwise", action: .retry),
        SlashCommand(name: "copy", summary: "Copy the answer", symbol: "doc.on.doc", action: .copy),
        SlashCommand(name: "history", summary: "Recent chats", symbol: "clock.arrow.circlepath", action: .history),
        SlashCommand(name: "shortcuts", summary: "Keyboard shortcuts", symbol: "keyboard", action: .shortcuts),
        SlashCommand(name: "settings", summary: "Open Settings", symbol: "gearshape", action: .settings),
    ]

    /// What's typed after the slash, against the names: those that start
    /// with it first, then those that have its letters in order ("stg" finds
    /// settings), each in list order.
    static func matching(_ typed: String, in commands: [SlashCommand]) -> [SlashCommand] {
        let typed = typed.lowercased()
        guard !typed.isEmpty else { return commands }
        let prefixed = commands.filter { $0.name.hasPrefix(typed) }
        let scattered = commands.filter { !$0.name.hasPrefix(typed) && Self.contains(typed, inOrderIn: $0.name) }
        return prefixed + scattered
    }

    private static func contains(_ letters: String, inOrderIn name: String) -> Bool {
        var remaining = letters[...]
        for character in name where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}

/// The matching commands, in a small smoked list just above the input, the
/// highlighted one marked with the key that runs it.
struct CommandList: View {
    @ObservedObject var controller: SearchController
    @ObservedObject private var settings = AppSettings.shared

    static let width: CGFloat = 340

    var body: some View {
        let commands = controller.commands
        let selected = controller.selectedCommandIndex
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                row(command, isSelected: index == selected)
            }
        }
        .padding(6)
        .frame(width: Self.width, alignment: .leading)
        .surface(RoundedRectangle(cornerRadius: 16, style: .continuous), style: .smoke)
        .animation(.easeOut(duration: 0.1), value: selected)
        .animation(.easeOut(duration: 0.15), value: commands.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Commands")
    }

    private func row(_ command: SlashCommand, isSelected: Bool) -> some View {
        Button {
            controller.run(command)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: command.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)
                Text("/\(command.name)")
                    .font(.system(size: 13, weight: .semibold))
                Text(command.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if case .provider(let provider) = command.action, provider == settings.provider {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Keycap("↩")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.13 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { controller.selectCommand(command) } }
        .accessibilityLabel("/\(command.name), \(command.summary)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension Notification.Name {
    /// /settings: close Flyby and open Settings, the way the menu bar's
    /// Settings… does.
    static let flybyShouldOpenSettings = Notification.Name("flybyShouldOpenSettings")
}
