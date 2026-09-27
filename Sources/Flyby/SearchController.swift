import AppKit
import Combine
import FlybyCore

/// Owns the state the pill and result panel render. One instance, shared by
/// both windows.
///
/// Providers differ wildly underneath — a browser hop, a live Google page, an
/// SSE stream — but they all reduce to the same thing here: a `phase` and an
/// `AnswerSnapshot`. The views only ever read those two.
@MainActor
final class SearchController: ObservableObject {
    enum Phase: Equatable {
        /// Nothing submitted; the result panel is closed.
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

    @Published var query = ""

    /// What the result panel is showing, which lags behind `query` once the
    /// user starts typing their next search.
    @Published private(set) var submittedQuery = ""
    /// The provider that produced what's on screen. `nil` while idle.
    @Published private(set) var activeProvider: ProviderKind?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var answer: AnswerSnapshot = .empty

    /// The user asked to see Google's page instead of the native answer.
    /// Tells the engine too, so reader mode can strip Google's chrome from
    /// the page only while someone's actually looking at it.
    @Published var prefersWebPage = false {
        didSet { aiMode.setPageRevealed(prefersWebPage) }
    }

    let aiMode: AIModeEngine

    private var geminiTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        aiMode = AIModeEngine(session: .shared)
        bindAIMode()
    }

    // MARK: - Derived state

    var isResultVisible: Bool { phase != .idle }

    var isBusy: Bool { phase == .working || phase == .streaming }

    /// Only AI Mode has a page behind the answer.
    var canShowWebPage: Bool { activeProvider == .aiMode }

    /// The page is revealed when the user asks for it, and forced whenever
    /// Google needs them.
    var showsWebPage: Bool {
        guard canShowWebPage else { return false }
        if case .needsAttention = phase { return true }
        return prefersWebPage
    }

    // MARK: - Actions

    /// Return in the pill.
    func submit() {
        run(query, with: AppSettings.shared.provider)
    }

    /// A follow-up chip: becomes the new query, answered by the same provider.
    func ask(_ followUp: String) {
        query = followUp
        run(followUp, with: activeProvider ?? AppSettings.shared.provider)
    }

    /// ⌘Return always escapes to the browser, whatever the provider is.
    func submitToBrowser() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        openInBrowser(q.isEmpty ? submittedQuery : q)
    }

    /// Runs the on-screen query again with the same provider.
    func retry() {
        guard !submittedQuery.isEmpty, let provider = activeProvider else { return }
        run(submittedQuery, with: provider)
    }

    /// Freezes the answer as it stands.
    func stop() {
        guard isBusy else { return }
        geminiTask?.cancel()
        geminiTask = nil
        aiMode.stop()
        answer.isComplete = true
        phase = answer.isEmpty ? .failed("Stopped before an answer arrived.") : .complete
    }

    func copyAnswer() {
        guard !answer.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer.plainText, forType: .string)
    }

    /// Full teardown, for when everything closes.
    func reset() {
        geminiTask?.cancel()
        geminiTask = nil
        aiMode.reset()
        query = ""
        submittedQuery = ""
        activeProvider = nil
        answer = .empty
        prefersWebPage = false
        phase = .idle
    }

    // MARK: - Running a search

    private func run(_ raw: String, with provider: ProviderKind) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }

        if provider == .browser {
            openInBrowser(q)
            return
        }

        // Clear the previous result without passing through `.idle`, so a
        // back-to-back search doesn't bounce the panel closed and open again.
        geminiTask?.cancel()
        geminiTask = nil
        if activeProvider == .aiMode, provider != .aiMode { aiMode.stop() }
        submittedQuery = q
        activeProvider = provider
        answer = .empty
        prefersWebPage = false
        phase = .working

        switch provider {
        case .browser:
            break
        case .aiMode:
            aiMode.search(q)
        case .gemini:
            startGemini(q)
        }
    }

    private func openInBrowser(_ q: String) {
        guard !q.isEmpty else { return }
        NSWorkspace.shared.open(AppSettings.shared.engine.url(for: q))
        NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
    }

    // MARK: - Gemini

    private func startGemini(_ q: String) {
        geminiTask = Task { [weak self] in
            var markdown = ""
            var sources: [WebSource] = []
            do {
                for try await event in GeminiProvider.stream(query: q) {
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
            } catch is CancellationError {
                // Stopped or superseded; whoever cancelled owns the state now.
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - AI Mode

    /// The engine publishes on its own schedule; mirror it only while it's the
    /// provider on screen.
    private func bindAIMode() {
        aiMode.$state
            .sink { [weak self] state in
                guard let self, self.activeProvider == .aiMode, self.phase != .idle else { return }
                switch state {
                case .idle:                     break
                case .loading:                  self.phase = .working
                case .streaming:                self.phase = .streaming
                case .complete:                 self.phase = .complete
                case .needsAttention(let why):  self.phase = .needsAttention(why)
                case .failed(let message):      self.phase = .failed(message)
                }
            }
            .store(in: &cancellables)

        aiMode.$snapshot
            .sink { [weak self] snapshot in
                guard let self, self.activeProvider == .aiMode, self.phase != .idle else { return }
                self.answer = snapshot
            }
            .store(in: &cancellables)
    }
}

extension Notification.Name {
    static let quickSearchShouldDismiss = Notification.Name("quickSearchShouldDismiss")
}
