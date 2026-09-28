import SwiftUI
import FlybyCore

/// Recent chats, newest first, grouped by when they were last touched.
/// Click one — or reach it with ↑↓ from the input and press Return — to carry
/// on where it left off.
struct HistoryView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject private var history = ConversationHistory.shared

    var body: some View {
        if history.summaries.isEmpty {
            empty
        } else {
            list
        }
    }

    private var list: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    title
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)

                    ForEach(sections, id: \.title) { section in
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(section.items) { summary in
                            HistoryRow(
                                summary: summary,
                                isSelected: summary.id == controller.historySelection,
                                onOpen: { controller.openConversation(summary.id) },
                                onDelete: { controller.deleteConversation(summary.id) }
                            )
                            .id(summary.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .cardScrollEdges()
            .onChange(of: controller.historySelection) {
                guard let id = controller.historySelection else { return }
                withAnimation(.easeOut(duration: 0.15)) { reader.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// The card has no title bar, so the list says what it is.
    /// The card has no title bar, so the list says what it is — and how to
    /// drive it from the keyboard, which is how most people get here (↑).
    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recent Chats")
                    .font(.system(size: 21, weight: .bold))
                Text("\(history.summaries.count) saved on this Mac")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            HStack(spacing: 5) {
                Keycap("↑ ↓")
                Text("move")
                Keycap("↩")
                Text("open")
                    .padding(.trailing, 4)
                Keycap("⌘⌫")
                Text("delete")
                    .padding(.trailing, 4)
                Keycap("esc")
                Text("back")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No chats yet")
                .font(.system(size: 16, weight: .semibold))
            Text("Ask something and it'll be here to come back to.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grouping

    private struct Section {
        let title: String
        let items: [ConversationSummary]
    }

    private var sections: [Section] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        var today: [ConversationSummary] = []
        var yesterday: [ConversationSummary] = []
        var week: [ConversationSummary] = []
        var older: [ConversationSummary] = []
        for summary in history.summaries {
            switch summary.updatedAt {
            case startOfToday...:     today.append(summary)
            case startOfYesterday...: yesterday.append(summary)
            case startOfWeek...:      week.append(summary)
            default:                  older.append(summary)
            }
        }
        return [
            Section(title: "Today", items: today),
            Section(title: "Yesterday", items: yesterday),
            Section(title: "Previous 7 Days", items: week),
            Section(title: "Older", items: older),
        ].filter { !$0.items.isEmpty }
    }
}

private struct HistoryRow: View {
    let summary: ConversationSummary
    let isSelected: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: ProviderKind(rawValue: summary.provider)?.icon ?? "text.bubble")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(summary.title)
                    .font(.system(size: 14.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete this chat")
                    .transition(.opacity)
                } else {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityLabel(summary.title)
        .accessibilityHint("Opens this chat")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button("Open", action: onOpen)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        return Color.primary.opacity(hovering ? 0.07 : 0)
    }

    /// "3 · 2:41 PM", or the date for anything older than today.
    private var detail: String {
        let time = Calendar.current.isDateInToday(summary.updatedAt)
            ? summary.updatedAt.formatted(date: .omitted, time: .shortened)
            : summary.updatedAt.formatted(.dateTime.month(.abbreviated).day())
        return summary.turnCount > 1 ? "\(summary.turnCount) · \(time)" : time
    }
}
