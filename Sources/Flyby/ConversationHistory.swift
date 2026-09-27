import Foundation
import FlybyCore

/// The history list the UI draws, kept in step with the files on disk.
///
/// All disk work happens on the store's actor. Operations are chained, so
/// they land in the order they were asked for and a slow save can't come
/// back after a later delete and resurrect the row.
@MainActor
final class ConversationHistory: ObservableObject {
    static let shared = ConversationHistory()

    /// Newest first.
    @Published private(set) var summaries: [ConversationSummary] = []

    private let store: HistoryStore
    private var tail: Task<Void, Never>?

    init(store: HistoryStore? = nil) {
        self.store = store ?? HistoryStore(directory: Self.directory)
        enqueue { await $0.summaries() }
    }

    /// Application Support, under the bundle identifier — so Flyby Dev and
    /// Flyby keep separate histories, like everything else they store.
    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.fringecore.flyby")
            .appendingPathComponent("History")
    }

    func save(_ conversation: Conversation) {
        enqueue { store in
            if let list = try? await store.save(conversation) { return list }
            return await store.summaries()
        }
    }

    func delete(_ id: UUID) {
        summaries.removeAll { $0.id == id }
        enqueue { await $0.delete(id) }
    }

    func clear() {
        summaries = []
        enqueue { await $0.clear() }
    }

    /// Waits for anything queued before it, so a conversation saved a moment
    /// ago can be opened straight away.
    func load(_ id: UUID) async -> Conversation? {
        await tail?.value
        return await store.load(id)
    }

    private func enqueue(_ operation: @escaping @Sendable (HistoryStore) async -> [ConversationSummary]) {
        let previous = tail
        let store = store
        tail = Task { [weak self] in
            await previous?.value
            let list = await operation(store)
            self?.summaries = list
        }
    }
}
