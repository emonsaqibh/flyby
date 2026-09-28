import SwiftUI
import FlybyCore

/// Settings › History: how many chats Flyby is keeping, how to get at them,
/// and the way to be rid of them.
struct HistoryPane: View {
    @ObservedObject private var history = ConversationHistory.shared
    @State private var confirmingClear = false

    var body: some View {
        Form {
            PaneHero(section: .history)

            Section {
                LabeledContent {
                    Button("Clear History…", role: .destructive) { confirmingClear = true }
                        .disabled(history.summaries.isEmpty)
                } label: {
                    Text("Saved chats")
                    Text(count)
                        .contentTransition(.numericText())
                }

                LabeledContent("Show history") {
                    HStack(spacing: 3) {
                        SettingsKeyCap(glyph: "⌘", size: .small)
                        SettingsKeyCap(glyph: "Y", size: .small)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Command Y")
                }
            } footer: {
                Text("Chats are kept on this Mac only, never uploaded. The newest \(HistoryStore.defaultLimit) are kept; older ones are removed automatically. You can also press ↑ in an empty field.")
            }
        }
        .formStyle(.grouped)
        .animation(.smooth, value: history.summaries.count)
        .confirmationDialog(
            "Clear your chat history?",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { history.clear() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every saved chat is deleted from this Mac. This can't be undone.")
        }
    }

    private var count: String {
        switch history.summaries.count {
        case 0:  return "None yet"
        case 1:  return "1 chat on this Mac"
        case let n: return "\(n) chats on this Mac"
        }
    }
}
