import Foundation

/// Past conversations, kept on this Mac only.
///
/// One small JSON file per conversation plus an index of summaries, so the
/// history list opens by reading one file however much has piled up, and
/// saving a turn rewrites only its own conversation. Beyond `limit`, the
/// conversations touched longest ago are deleted — history is for getting
/// back to recent things, and an unbounded folder only costs disk and a
/// slower list.
public actor HistoryStore {
    public static let defaultLimit = 200

    public let directory: URL
    public let limit: Int

    /// Newest first. Loaded on first use.
    private var index: [ConversationSummary]?

    private static let indexName = "index.json"

    public init(directory: URL, limit: Int = HistoryStore.defaultLimit) {
        self.directory = directory
        self.limit = max(limit, 1)
    }

    /// Newest first.
    public func summaries() -> [ConversationSummary] {
        loadedIndex()
    }

    public func load(_ id: UUID) -> Conversation? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? Self.decoder.decode(Conversation.self, from: data)
    }

    /// Writes the conversation and moves it to the top of the list. Returns
    /// the list as it now stands.
    @discardableResult
    public func save(_ conversation: Conversation) throws -> [ConversationSummary] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(conversation).write(to: fileURL(for: conversation.id), options: .atomic)

        var list = loadedIndex().filter { $0.id != conversation.id }
        list.insert(conversation.summary, at: 0)
        list.sort { $0.updatedAt > $1.updatedAt }
        if list.count > limit {
            for dropped in list[limit...] {
                try? FileManager.default.removeItem(at: fileURL(for: dropped.id))
            }
            list.removeSubrange(limit...)
        }
        try writeIndex(list)
        return list
    }

    @discardableResult
    public func delete(_ id: UUID) -> [ConversationSummary] {
        try? FileManager.default.removeItem(at: fileURL(for: id))
        let list = loadedIndex().filter { $0.id != id }
        try? writeIndex(list)
        return list
    }

    /// Everything goes: the files and the index.
    @discardableResult
    public func clear() -> [ConversationSummary] {
        try? FileManager.default.removeItem(at: directory)
        index = []
        return []
    }

    // MARK: - Files

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private var indexURL: URL { directory.appendingPathComponent(Self.indexName) }

    private func loadedIndex() -> [ConversationSummary] {
        if let index { return index }
        let list: [ConversationSummary]
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? Self.decoder.decode([ConversationSummary].self, from: data) {
            list = decoded
        } else {
            // No index, or an unreadable one: rebuild it from the files
            // themselves rather than losing the history it pointed at.
            list = rebuiltIndex()
            if !list.isEmpty { try? writeIndex(list) }
        }
        index = list
        return list
    }

    private func rebuiltIndex() -> [ConversationSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.indexName }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return (try? Self.decoder.decode(Conversation.self, from: data))?.summary
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func writeIndex(_ list: [ConversationSummary]) throws {
        index = list
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(list).write(to: indexURL, options: .atomic)
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
}
