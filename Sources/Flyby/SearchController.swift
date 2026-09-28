import AppKit
import Combine
import FlybyCore

/// Owns the state the bar and the answer card render.
///
/// What's on screen is a conversation: the earlier turns, frozen, and one
/// live turn — the one `submittedQuery`, `phase` and `answer` describe.
/// Asking again from the input while a conversation is open is a follow-up:
/// the live turn joins the earlier ones and a new one starts.
///
/// Providers differ wildly underneath — a browser hop, a live Google page, an
/// SSE stream, a model on this Mac — but they all reduce to the same thing
/// here: a `phase` and an `AnswerSnapshot`. The views only ever read those two.
@MainActor
final class SearchController: ObservableObject {
    enum Phase: Equatable {
        /// Nothing submitted; only the bar shows.
        case idle
        /// Submitted, nothing to show yet.
        case working
        /// Part of the answer is on screen and more is coming.
        case streaming
        case complete
        /// AI Mode needs the user to look at the page itself — a CAPTCHA, a
        /// consent wall, a sign-in, or a page the extractor couldn't read.
        case needsAttention(AIModeEngine.Attention)
        case failed(String)
    }

    @Published var query = "" {
        didSet {
            // A new filter starts at the top of the command list, and brings
            // back a list Esc put away.
            guard query != oldValue else { return }
            commandSelection = 0
            if dismissedCommandInput != nil { dismissedCommandInput = nil }
        }
    }

    /// The conversation's finished turns, oldest first. The live turn isn't
    /// among them until the next question moves it here.
    @Published private(set) var earlierTurns: [ConversationTurn] = []

    /// The live turn's question.
    @Published private(set) var submittedQuery = ""
    /// The provider that produced the live turn. `nil` while idle.
    @Published private(set) var activeProvider: ProviderKind?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var answer: AnswerSnapshot = .empty
    /// Identifies the live turn, so the conversation can scroll to each new
    /// question as it's asked.
    @Published private(set) var liveTurnID = UUID()
    /// The identity the next question will have. The input's text carries it
    /// while it's typed, so the question can be seen travelling from the
    /// input into the bubble it becomes.
    @Published private(set) var nextTurnID = UUID()
    /// The live turn was reopened from history rather than asked in this
    /// session, so there's no page behind it and nothing running.
    @Published private(set) var isRestored = false

    /// The user asked to see Google's page instead of the native answer.
    /// Tells the engine too, so reader mode can strip Google's chrome from
    /// the page only while someone's actually looking at it.
    @Published var prefersWebPage = false {
        didSet { aiMode.setPageRevealed(prefersWebPage) }
    }

    /// The history list is showing in the card.
    @Published var showsHistory = false
    /// The keyboard shortcuts are showing, over the bar or the card (⌘/).
    @Published var showsShortcuts = false
    /// The row the arrow keys have reached in the history list.
    @Published var historySelection: UUID?

    let aiMode: AIModeEngine
    let history: ConversationHistory

    private var conversationID = UUID()
    private var conversationStarted = Date()
    private var liveTurnDate = Date()
    /// The streaming answer from Gemini or Apple Intelligence.
    private var answerTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(history: ConversationHistory? = nil) {
        self.history = history ?? .shared
        aiMode = AIModeEngine(session: .shared)
        bindAIMode()
    }

    // MARK: - Derived state

    /// A live turn exists, so the panel has a conversation to show.
    var isResultVisible: Bool { phase != .idle }

    /// The panel is open: a conversation, or the history list.
    var showsPanel: Bool { isResultVisible || showsHistory }

    var isBusy: Bool { phase == .working || phase == .streaming }

    /// Only a live AI Mode turn has a page behind it.
    var canShowWebPage: Bool { activeProvider == .aiMode && !isRestored }

    /// The page is revealed when the user asks for it, and forced whenever
    /// Google needs them — unless they're looking at their history.
    var showsWebPage: Bool {
        guard canShowWebPage, !showsHistory else { return false }
        if case .needsAttention = phase { return true }
        return prefersWebPage
    }

    /// Retry is offered once there's an outcome to redo: a finished answer or
    /// a failure. Not mid-stream (that's Stop's moment) and not while Google
    /// is waiting on the user.
    var offersRetry: Bool {
        guard !submittedQuery.isEmpty, activeProvider != nil else { return false }
        switch phase {
        case .complete, .failed: return true
        default:                 return false
        }
    }

    /// Switching between the answer and Google's page: only when there's a
    /// page behind the answer, and not while Google is holding the page open
    /// for the user anyway.
    var offersPageToggle: Bool {
        guard canShowWebPage else { return false }
        if case .needsAttention = phase { return false }
        return true
    }

    // MARK: - Asking

    /// Return in the input: a follow-up if a conversation is open, a new one
    /// otherwise. With the history list open and nothing typed, Return opens
    /// the highlighted conversation instead.
    func submit() {
        // "/set" and Return: the highlighted command, not a search for it.
        if !commands.isEmpty {
            runSelectedCommand()
            return
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            if showsHistory, let id = historySelection { openConversation(id) }
            return
        }
        send(q, with: AppSettings.shared.provider)
    }

    /// A suggested follow-up, asked of whichever provider gave the answer it
    /// came with.
    func ask(_ followUp: String) {
        send(followUp, with: activeProvider ?? AppSettings.shared.provider)
    }

    /// ⌘Return always escapes to the browser, whatever the provider is.
    func submitToBrowser() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        openInBrowser(q.isEmpty ? submittedQuery : q)
    }

    /// Asks the live turn's question again, with the same provider — the same
    /// turn, answered afresh, so the question stays where it is.
    func retry() {
        guard !submittedQuery.isEmpty, let provider = activeProvider else { return }
        run(submittedQuery, with: provider, asTurn: liveTurnID)
    }

    /// Freezes the answer as it stands.
    func stop() {
        guard isBusy else { return }
        answerTask?.cancel()
        answerTask = nil
        aiMode.stop()
        answer.isComplete = true
        phase = answer.isEmpty ? .failed("Stopped before an answer arrived.") : .complete
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer.plainText, forType: .string)
    }

    /// Puts the conversation away (it's in history) and folds back to the
    /// bar.
    func newChat() {
        saveConversation()
        clearConversation()
        showsHistory = false
        requestInputFocus()
    }

    /// Full teardown, for when everything closes. The conversation is saved
    /// first, so closing never loses it.
    func reset() {
        saveConversation()
        clearConversation()
        query = ""
        showsHistory = false
        showsShortcuts = false
        historySelection = nil
    }

    private func send(_ q: String, with provider: ProviderKind) {
        let q = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if provider == .browser {
            openInBrowser(q)
            return
        }

        showsHistory = false
        if isResultVisible {
            stop()
            archiveLiveTurn()
        } else {
            conversationID = UUID()
            conversationStarted = Date()
        }
        query = ""
        run(q, with: provider)
        requestInputFocus()
    }

    // MARK: - History

    func toggleHistory() {
        showsHistory ? closeHistory() : openHistory()
    }

    func openHistory() {
        showsHistory = true
        historySelection = history.summaries.first?.id
    }

    func closeHistory() {
        showsHistory = false
        requestInputFocus()
    }

    /// ↑ and ↓ through the history list, stopping at the ends.
    func moveHistorySelection(by offset: Int) {
        let ids = history.summaries.map(\.id)
        guard !ids.isEmpty else { return }
        let current = historySelection.flatMap { ids.firstIndex(of: $0) } ?? -1
        let next = min(max(current + offset, 0), ids.count - 1)
        historySelection = ids[next]
    }

    /// Reopens a past conversation where it left off, ready for a follow-up.
    func openConversation(_ id: UUID) {
        guard id != conversationID || !isResultVisible else {
            closeHistory()
            return
        }
        Task { [weak self] in
            guard let self, let conversation = await self.history.load(id),
                  let last = conversation.turns.last else { return }
            self.saveConversation()
            self.answerTask?.cancel()
            self.answerTask = nil
            // Before the engine resets: its "empty" snapshot must not land
            // on the restored answer.
            self.isRestored = true
            self.aiMode.reset()

            self.conversationID = conversation.id
            self.conversationStarted = conversation.createdAt
            self.earlierTurns = Array(conversation.turns.dropLast())
            self.submittedQuery = last.query
            self.activeProvider = ProviderKind(rawValue: last.provider) ?? .gemini
            self.answer = last.answer
            self.liveTurnID = last.id
            self.liveTurnDate = last.date
            self.prefersWebPage = false
            self.phase = last.failure.map { .failed($0) } ?? .complete
            self.query = ""
            self.showsHistory = false
            self.requestInputFocus()
        }
    }

    // MARK: - Slash commands

    /// The highlighted row in the command list.
    @Published var commandSelection = 0
    /// The input as it was when Esc put the command list away; the list stays
    /// away until the text changes.
    @Published private var dismissedCommandInput: String?

    /// What's typed after a leading "/" — while it's still one word. A space
    /// makes it a question.
    var commandInput: String? {
        guard query.hasPrefix("/"), !query.contains(where: \.isWhitespace) else { return nil }
        return String(query.dropFirst())
    }

    /// The commands the list shows: matching what's typed, and only those
    /// that would do something now. Empty when there's no list — including
    /// when nothing matches, so Return searches for the text instead.
    var commands: [SlashCommand] {
        guard let typed = commandInput, query != dismissedCommandInput else { return [] }
        return SlashCommand.matching(typed, in: SlashCommand.all.filter(isAvailable))
    }

    var selectedCommandIndex: Int { min(commandSelection, max(commands.count - 1, 0)) }

    func moveCommandSelection(by offset: Int) {
        let count = commands.count
        guard count > 0 else { return }
        commandSelection = min(max(selectedCommandIndex + offset, 0), count - 1)
    }

    func selectCommand(_ command: SlashCommand) {
        if let index = commands.firstIndex(of: command) { commandSelection = index }
    }

    /// Esc with the list open: away with the list, keeping the text.
    func dismissCommands() {
        dismissedCommandInput = query
    }

    func runSelectedCommand() {
        let commands = self.commands
        guard !commands.isEmpty else { return }
        run(commands[selectedCommandIndex])
    }

    /// Clears the "/…" and does it.
    func run(_ command: SlashCommand) {
        query = ""
        switch command.action {
        case .settings:
            NotificationCenter.default.post(name: .flybyShouldOpenSettings, object: nil)
        case .history:
            openHistory()
        case .shortcuts:
            showsShortcuts = true
        case .newChat:
            newChat()
        case .retry:
            retry()
        case .copy:
            copyAnswer()
        case .provider(let provider):
            AppSettings.shared.provider = provider
        }
    }

    private func isAvailable(_ command: SlashCommand) -> Bool {
        switch command.action {
        case .newChat: return showsPanel
        case .retry:   return offersRetry
        case .copy:    return isResultVisible && !answer.isEmpty
        default:       return true
        }
    }

    /// ⌘⌫ in the history list.
    func deleteSelectedConversation() {
        guard showsHistory, let id = historySelection else { return }
        deleteConversation(id)
    }

    func deleteConversation(_ id: UUID) {
        history.delete(id)
        if historySelection == id { historySelection = history.summaries.first?.id }
        // Deleting the conversation on screen: it stays on screen, but under
        // a new identity, so carrying on with it doesn't bring it back.
        if id == conversationID { conversationID = UUID() }
    }

    // MARK: - Running a search

    /// `turn` is the live turn being asked again; a new question takes the
    /// identity its text carried in the input.
    private func run(_ raw: String, with provider: ProviderKind, asTurn turn: UUID? = nil) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        if provider == .browser {
            openInBrowser(q)
            return
        }

        // Clear the previous answer without passing through `.idle`, so a
        // back-to-back search doesn't bounce the panel closed and open again.
        answerTask?.cancel()
        answerTask = nil
        if activeProvider == .aiMode, provider != .aiMode { aiMode.stop() }
        isRestored = false
        submittedQuery = q
        activeProvider = provider
        answer = .empty
        prefersWebPage = false
        if let turn {
            liveTurnID = turn
        } else {
            liveTurnID = nextTurnID
            nextTurnID = UUID()
        }
        liveTurnDate = Date()
        phase = .working

        switch provider {
        case .browser:
            break
        case .aiMode:
            // AI Mode answers each question on its own: its context lives
            // in Google's page, which Flyby doesn't drive.
            aiMode.search(q)
        case .gemini:
            startGemini(q, context: ChatContext.messages(from: earlierTurns))
        case .appleIntelligence:
            startAppleIntelligence(q, context: AppleIntelligenceProvider.context(from: earlierTurns))
        }
    }

    private func openInBrowser(_ q: String) {
        guard !q.isEmpty else { return }
        NSWorkspace.shared.open(AppSettings.shared.engine.url(for: q))
        NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
    }

    /// The input takes the keyboard back — after a question is sent, a chat
    /// is opened, or the history list closes.
    private func requestInputFocus() {
        NotificationCenter.default.post(name: .flybyShouldFocusInput, object: nil)
    }

    // MARK: - The conversation

    /// The live turn as it would be saved, if it's worth saving: something
    /// came back, or it failed in a way worth remembering.
    private var liveTurn: ConversationTurn? {
        guard isResultVisible, !submittedQuery.isEmpty, let activeProvider else { return nil }
        var failure: String?
        switch phase {
        case .failed(let message): failure = message
        case .needsAttention where answer.isEmpty: failure = "Google needed you to check its page."
        default: break
        }
        guard !answer.isEmpty || failure != nil else { return nil }
        var snapshot = answer
        snapshot.isComplete = true
        return ConversationTurn(
            id: liveTurnID,
            query: submittedQuery,
            provider: activeProvider.rawValue,
            answer: snapshot,
            failure: failure,
            date: liveTurnDate
        )
    }

    private func archiveLiveTurn() {
        if let turn = liveTurn { earlierTurns.append(turn) }
    }

    private var conversation: Conversation? {
        let turns = earlierTurns + (liveTurn.map { [$0] } ?? [])
        guard !turns.isEmpty else { return nil }
        return Conversation(
            id: conversationID,
            turns: turns,
            createdAt: conversationStarted,
            updatedAt: turns.last?.date ?? Date()
        )
    }

    private func saveConversation() {
        // A reopened conversation nobody added to is already saved as it is;
        // saving again would only bump it to the top of the list.
        if isRestored { return }
        if let conversation { history.save(conversation) }
    }

    private func clearConversation() {
        answerTask?.cancel()
        answerTask = nil
        aiMode.reset()
        earlierTurns = []
        submittedQuery = ""
        activeProvider = nil
        answer = .empty
        prefersWebPage = false
        isRestored = false
        conversationID = UUID()
        phase = .idle
    }

    /// Saved as each turn settles, so a crash or a quit loses nothing.
    private func turnDidSettle() {
        switch phase {
        case .complete, .failed: saveConversation()
        default: break
        }
    }

    // MARK: - Gemini

    private func startGemini(_ q: String, context: [ChatMessage]) {
        answerTask = Task { [weak self] in
            var markdown = ""
            var sources: [WebSource] = []
            do {
                for try await event in GeminiProvider.stream(query: q, context: context) {
                    guard let self, !Task.isCancelled else { return }
                    switch event {
                    case .text(let chunk):
                        markdown += chunk
                    case .sources(let list):
                        sources.merge(list)
                    }
                    self.answer = AnswerSnapshot(
                        blocks: MarkdownParser.parse(markdown),
                        sources: sources
                    )
                    self.phase = .streaming
                }
                guard let self, !Task.isCancelled else { return }
                self.answer.isComplete = true
                self.phase = self.answer.isEmpty ? .failed("Gemini returned an empty answer.") : .complete
                self.turnDidSettle()
            } catch is CancellationError {
                // Stopped or superseded; whoever cancelled owns the state now.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
                self.turnDidSettle()
            }
        }
    }

    // MARK: - Apple Intelligence

    /// Each element is the whole answer so far, not the next piece of it.
    private func startAppleIntelligence(_ q: String, context: [ChatMessage]) {
        let stream = AppleIntelligenceProvider.stream(query: q, context: context)
        answerTask = Task { [weak self] in
            do {
                for try await markdown in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.answer = AnswerSnapshot(blocks: MarkdownParser.parse(markdown), sources: [])
                    self.phase = .streaming
                }
                guard let self, !Task.isCancelled else { return }
                self.answer.isComplete = true
                self.phase = self.answer.isEmpty ? .failed("Apple Intelligence returned an empty answer.") : .complete
                self.turnDidSettle()
            } catch is CancellationError {
                // Stopped or superseded; whoever cancelled owns the state now.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
                self.turnDidSettle()
            }
        }
    }

    // MARK: - AI Mode

    /// The engine publishes on its own schedule; mirror it only while a live
    /// AI Mode turn is on screen.
    private func bindAIMode() {
        aiMode.$state
            .sink { [weak self] state in
                guard let self, self.activeProvider == .aiMode, !self.isRestored, self.phase != .idle else { return }
                switch state {
                case .idle:                     break
                case .loading:                  self.phase = .working
                case .streaming:                self.phase = .streaming
                case .complete:                 self.phase = .complete
                case .needsAttention(let why):  self.phase = .needsAttention(why)
                case .failed(let message):      self.phase = .failed(message)
                }
                self.turnDidSettle()
            }
            .store(in: &cancellables)

        aiMode.$snapshot
            .sink { [weak self] snapshot in
                guard let self, self.activeProvider == .aiMode, !self.isRestored, self.phase != .idle else { return }
                self.answer = snapshot
                // The final snapshot can land just after `.complete`; save
                // once it has.
                if snapshot.isComplete { self.turnDidSettle() }
            }
            .store(in: &cancellables)
    }
}

extension Notification.Name {
    static let quickSearchShouldDismiss = Notification.Name("quickSearchShouldDismiss")
    /// Puts the keyboard back in the input.
    static let flybyShouldFocusInput = Notification.Name("flybyShouldFocusInput")
}
