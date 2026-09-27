import Foundation
import Testing
@testable import FlybyCore

private func turn(_ query: String, answer: String, provider: String = "gemini", at seconds: TimeInterval = 0) -> ConversationTurn {
    ConversationTurn(
        query: query,
        provider: provider,
        answer: answer.isEmpty ? .empty : AnswerSnapshot(
            blocks: [.paragraph(answer)],
            sources: [WebSource(title: "Example", url: URL(string: "https://example.com")!)],
            isComplete: true
        ),
        date: Date(timeIntervalSinceReferenceDate: seconds)
    )
}

private func conversation(_ title: String, updated seconds: TimeInterval) -> Conversation {
    Conversation(
        turns: [turn(title, answer: "An answer to \(title)")],
        createdAt: Date(timeIntervalSinceReferenceDate: seconds),
        updatedAt: Date(timeIntervalSinceReferenceDate: seconds)
    )
}

@Suite struct ChatContextTests {
    @Test func alternatesQuestionsAndAnswersWithoutSources() {
        let messages = ChatContext.messages(from: [
            turn("How tall is Kilimanjaro?", answer: "5,895 m."),
            turn("And Everest?", answer: "8,849 m."),
        ])
        #expect(messages == [
            ChatMessage(role: .user, text: "How tall is Kilimanjaro?"),
            ChatMessage(role: .model, text: "5,895 m."),
            ChatMessage(role: .user, text: "And Everest?"),
            ChatMessage(role: .model, text: "8,849 m."),
        ])
    }

    @Test func skipsTurnsThatNeverGotAnAnswer() {
        let messages = ChatContext.messages(from: [
            turn("first", answer: ""),
            turn("second", answer: "yes"),
        ])
        #expect(messages.map(\.text) == ["second", "yes"])
    }

    @Test func keepsOnlyTheMostRecentTurns() {
        let turns = (1...10).map { turn("q\($0)", answer: "a\($0)") }
        let messages = ChatContext.messages(from: turns, maxTurns: 3)
        #expect(messages.map(\.text) == ["q8", "a8", "q9", "a9", "q10", "a10"])
    }

    @Test func capsLongAnswers() {
        let messages = ChatContext.messages(from: [turn("q", answer: String(repeating: "x", count: 50))], maxAnswerCharacters: 10)
        #expect(messages.last?.text == String(repeating: "x", count: 10) + "…")
    }

    @Test func dropsTheOldestTurnsWhenTooLongButKeepsTheLast() {
        let turns = [
            turn("old", answer: String(repeating: "a", count: 100)),
            turn("new", answer: String(repeating: "b", count: 100)),
        ]
        #expect(ChatContext.messages(from: turns, maxTotalCharacters: 150).map(\.text).first == "new")
        #expect(ChatContext.messages(from: [turns[1]], maxTotalCharacters: 10).count == 2)
    }
}

@Suite struct HistoryStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("flyby-history-\(UUID().uuidString)")
    }

    @Test func savesLoadsAndListsNewestFirst() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)

        let older = conversation("older", updated: 10)
        let newer = conversation("newer", updated: 20)
        try await store.save(older)
        let list = try await store.save(newer)

        #expect(list.map(\.title) == ["newer", "older"])
        #expect(await store.load(older.id) == older)
    }

    @Test func resavingMovesAConversationToTheTop() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)

        var first = conversation("first", updated: 10)
        try await store.save(first)
        try await store.save(conversation("second", updated: 20))
        first.turns.append(turn("follow-up", answer: "more"))
        first.updatedAt = Date(timeIntervalSinceReferenceDate: 30)
        let list = try await store.save(first)

        #expect(list.map(\.title) == ["first", "second"])
        #expect(list.first?.turnCount == 2)
    }

    @Test func prunesTheLeastRecentBeyondTheLimit() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir, limit: 2)

        let oldest = conversation("a", updated: 1)
        try await store.save(oldest)
        try await store.save(conversation("b", updated: 2))
        let list = try await store.save(conversation("c", updated: 3))

        #expect(list.map(\.title) == ["c", "b"])
        #expect(await store.load(oldest.id) == nil)
    }

    @Test func survivesALostIndex() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = conversation("kept", updated: 5)
        try await HistoryStore(directory: dir).save(saved)
        try FileManager.default.removeItem(at: dir.appendingPathComponent("index.json"))

        #expect(await HistoryStore(directory: dir).summaries().map(\.id) == [saved.id])
    }

    @Test func deleteAndClear() async throws {
        let dir = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        let a = conversation("a", updated: 1)
        try await store.save(a)
        try await store.save(conversation("b", updated: 2))

        #expect(await store.delete(a.id).map(\.title) == ["b"])
        #expect(await store.clear().isEmpty)
        #expect(await HistoryStore(directory: dir).summaries().isEmpty)
    }
}
