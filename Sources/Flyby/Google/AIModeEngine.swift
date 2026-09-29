import AppKit
import Combine
import SwiftUI
import WebKit
import os
import FlybyCore

private let aiModeLog = Logger(subsystem: "com.fringecore.flyby", category: "aimode")

/// Google AI Mode, run in a real web page behind Flyby's native answer view.
///
/// One long-lived `WKWebView` does the actual searching, signed in through
/// `GoogleSession`. An injected script reads the answer out of the page as it
/// streams and posts `AnswerSnapshot`s, which the result panel draws natively.
/// The page itself stays mounted underneath — invisible, but laid out and
/// running at full speed — and is revealed only when Google needs the user
/// (a CAPTCHA, a consent wall, a sign-in) or the page can't be read.
///
/// A follow-up is asked in that same page, through AI Mode's own composer,
/// so Google answers it in the conversation it already has. When the page
/// can't take one, it's a fresh search whose query carries the conversation
/// (`AIModeFollowUp`) — never a bare question in a new chat.
@MainActor
final class AIModeEngine: ObservableObject {
    enum Attention: Equatable {
        case captcha
        case consent
        case signIn
        /// The answer loaded but the extractor couldn't make sense of it.
        case unreadable
    }

    enum State: Equatable {
        case idle
        /// Navigating; nothing extracted yet.
        case loading
        /// Some of the answer is on screen, more is coming.
        case streaming
        case complete
        case needsAttention(Attention)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var snapshot: AnswerSnapshot = .empty

    /// The page. Created on first use and reused for every search after.
    let webView: WKWebView

    /// What the page gets when it asks for a file — the screenshot being
    /// attached. Otherwise the picker is cancelled: Flyby never shows the
    /// page's own file dialog.
    var fileForPicker: URL?

    /// Flyby's scripts run in their own world: Google's scripts can't see
    /// them, nor the `webkit.messageHandlers` entry that would otherwise give
    /// away an embedded web view.
    static var contentWorld: WKContentWorld { .world(name: "flyby") }
    static let messageHandlerName = "flyby"

    /// A load that produced nothing readable this long after finishing shows
    /// the page instead.
    private static let unreadableAfter: UInt64 = 15_000_000_000
    /// No progress at all for this long ends the search: failed if nothing
    /// came, complete if the answer simply stopped growing.
    private static let stallAfter: UInt64 = 45_000_000_000
    /// A follow-up sent through the page with nothing of its answer this long
    /// after is asked again as a search. AI Mode starts answering within a
    /// few seconds; a page that's silent this long isn't going to.
    private static let followUpSilentAfter: UInt64 = 20_000_000_000

    private let session: GoogleSession
    private let bridge: AIModeWebBridge
    private var settingsObservers = Set<AnyCancellable>()

    // Per search.
    private var searchID = 0
    private var isSearchActive = false
    /// Stopped by the user or ended by a timeout: nothing the page says now
    /// changes what's on screen.
    private var isFrozen = false
    private var userRevealedPage = false
    private var hasLoadedPage = false
    private var stallTimer: Task<Void, Never>?
    private var unreadableTimer: Task<Void, Never>?
    private var followUpTimer: Task<Void, Never>?
    /// A question with a screenshot, waiting for AI Mode's start page to
    /// finish loading so it can be asked through the composer.
    private var pendingAsk: (question: String, screenshot: Screenshot, searchID: Int)?
    /// The page finished answering the latest question, and nothing since
    /// has taken it from that conversation — so a follow-up can be typed
    /// into it. Only an answer the page itself called finished counts: not
    /// one stopped, timed out, failed or waiting on the user.
    private var isContinuable = false

    // Per document.
    private var acceptsMessages = false
    private var pageID: String?
    /// Which of the document's questions is being answered: 0 for the one it
    /// loaded with, then one more per follow-up. The extractor tags every
    /// message with it.
    private var pageTurn = 0
    private var pageGeneration = 0
    /// Documents committed so far — so a question whose page navigated away
    /// mid-ask (taking the script's answer with it) can be told from one the
    /// page refused.
    private var documentsCommitted = 0
    private var lastAccountReport: AccountReport?
    private var readerRequested: Bool?

    private struct AccountReport: Equatable {
        var account: GoogleAccount?
        var signedIn: Bool
    }

    /// `nil` means the shared session. (A default argument of `.shared` would
    /// be evaluated outside the main actor, which Swift 6 rejects.)
    init(session: GoogleSession? = nil) {
        let session = session ?? .shared
        self.session = session
        let bridge = AIModeWebBridge()
        self.bridge = bridge

        let config = GoogleWebIdentity.configuration(dataStore: session.dataStore)
        // The page does its work while hidden behind the native view; a
        // throttled page would stream the answer in slow motion.
        config.preferences.inactiveSchedulingPolicy = .none
        let content = config.userContentController
        content.addUserScript(WKUserScript(
            source: AIModeScript.bridge, injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: AIModeEngine.contentWorld
        ))
        content.addUserScript(WKUserScript(
            source: AIModeScript.extractor, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: AIModeEngine.contentWorld
        ))
        // The controller retains its handlers; the bridge only holds the
        // engine weakly, so this doesn't keep the engine alive.
        content.add(bridge, contentWorld: AIModeEngine.contentWorld, name: AIModeEngine.messageHandlerName)

        // The size it'll have in the card, before the card ever mounts it:
        // Google lays the page out responsively, and a zero-width page is not
        // what users get.
        webView = WKWebView(
            frame: NSRect(
                x: 0, y: 0,
                width: CardMetrics.width - CardMetrics.edgeInset * 2,
                height: CardMetrics.maxHeight - CardMetrics.headerInset - CardMetrics.footerInset
            ),
            configuration: config
        )
        bridge.engine = self
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        #if DEBUG
        webView.isInspectable = true
        #endif

        // Google honours prefers-color-scheme, which WebKit takes from the
        // view's appearance. Set here rather than inherited from the card,
        // because the page loads — prewarmed, or searching — before it's ever
        // mounted there; the card is always dark, and so is the page.
        webView.appearance = NSAppearance(named: .darkAqua)
        // @Published emits before the stored value changes, so pass it along.
        AppSettings.shared.$readerMode
            .dropFirst()
            .sink { [weak self] enabled in self?.syncReader(readerMode: enabled) }
            .store(in: &settingsObservers)
    }

    /// With a screenshot the page starts empty, at AI Mode's start page, and
    /// the question is asked through the composer once it's there, with the
    /// picture attached — a URL can't carry one.
    func search(_ query: String, attaching screenshot: Screenshot? = nil) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        freezePage()
        cancelTimers()
        searchID += 1
        isSearchActive = true
        isFrozen = false
        isContinuable = false
        userRevealedPage = false
        acceptsMessages = false
        pageID = nil
        pageTurn = 0
        hasLoadedPage = true
        snapshot = .empty
        transition(to: .loading)
        armStallTimer()
        aiModeLog.info("Search started (\(trimmed.count, privacy: .public) characters\(screenshot == nil ? "" : ", with a screenshot", privacy: .public))")

        // A stale Safari/Firefox copy is re-read first, so the page loads with
        // the browser's current session. It returns at once when fresh.
        let id = searchID
        let language = AIModeQuery.preferredLanguageCode
        let url: URL
        if let screenshot {
            pendingAsk = (trimmed, screenshot, id)
            url = AIModeQuery.startURL(languageCode: language)
        } else {
            pendingAsk = nil
            url = AIModeQuery.url(for: trimmed, languageCode: language)
        }
        Task { [weak self] in
            guard let self else { return }
            await self.session.refreshIfStale()
            guard id == self.searchID, self.isSearchActive, !self.isFrozen else { return }
            self.webView.load(URLRequest(url: url))
        }
    }

    /// Asks `question` in the conversation on the page, through AI Mode's own
    /// composer, so Google answers it with everything asked before. When the
    /// page can't take it — there's no finished conversation on it, the
    /// composer isn't where it was, or the page never starts answering — it's
    /// a search for `fallback` instead, which carries the conversation in
    /// the query.
    ///
    /// The caller has to know the page's conversation is this chat's: every
    /// way of leaving a chat (`reset()`, and `stop()` when another provider
    /// takes a turn) ends it here too.
    func followUp(_ question: String, attaching screenshot: Screenshot? = nil, orSearch fallback: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard canContinueOnPage else {
            aiModeLog.info("Follow-up: no conversation on the page to continue; searching with it in the query")
            search(fallback, attaching: screenshot)
            return
        }

        // The same document carries on, so its extractor isn't frozen: it's
        // told which question it's reading now instead.
        cancelTimers()
        searchID += 1
        isSearchActive = true
        isFrozen = false
        isContinuable = false
        userRevealedPage = false
        pendingAsk = nil
        snapshot = .empty
        transition(to: .loading)
        armStallTimer()
        askOnPage(trimmed, attaching: screenshot, onFreshPage: false, fallback: fallback)
    }

    /// Types `question` into the composer — after attaching the screenshot,
    /// if there is one — and sends it. When the page won't take it, a
    /// follow-up is asked as a search for `fallback`; a question asked on a
    /// fresh start page (no `fallback`) has nowhere else to go, and fails.
    private func askOnPage(_ question: String, attaching screenshot: Screenshot?, onFreshPage fresh: Bool, fallback: String?) {
        pageTurn += 1
        let id = searchID
        let turn = pageTurn
        let document = documentsCommitted
        var arguments: [String: Any] = [
            "question": question, "turn": turn, "fresh": fresh,
            "image": NSNull(), "imageName": NSNull(), "imageType": NSNull(),
        ]
        if let screenshot {
            do {
                let file = try screenshot.file()
                fileForPicker = file
                arguments["image"] = screenshot.upload.base64EncodedString()
                arguments["imageName"] = file.lastPathComponent
                arguments["imageType"] = screenshot.mimeType
            } catch {
                aiModeLog.error("Couldn't write the screenshot for the page: \(error.localizedDescription, privacy: .public)")
                fail(Self.screenshotFailure)
                return
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await self.webView.flybyCallAsync(
                """
                var f = window.__flyby;
                if (!f || !f.followUp) return 'no-extractor';
                return await f.followUp(question, turn, { fresh: fresh, image: image, imageName: imageName, imageType: imageType });
                """,
                arguments: arguments,
                in: Self.contentWorld
            )
            self.fileForPicker = nil
            guard id == self.searchID, self.isSearchActive, !self.isFrozen else { return }
            let what = screenshot == nil ? "Question" : "Question with a screenshot"
            if result == nil, self.documentsCommitted != document {
                // Sending loaded a new document, which took the script with
                // it; that document answers from its own first turn.
                aiModeLog.info("\(what, privacy: .public) sent; the page moved to a new document to answer it")
                self.armFollowUpTimer(fallback: fallback, attaching: screenshot)
            } else if result == "sent" {
                aiModeLog.info("\(what, privacy: .public) asked in Google's composer (turn \(turn, privacy: .public))")
                self.armFollowUpTimer(fallback: fallback, attaching: screenshot)
            } else if let fallback {
                aiModeLog.error("\(what, privacy: .public) couldn't be asked in the page (\(result ?? "no result", privacy: .public)); searching with the conversation in the query")
                self.search(fallback, attaching: screenshot)
            } else {
                aiModeLog.error("\(what, privacy: .public) couldn't be asked on the start page (\(result ?? "no result", privacy: .public))")
                self.fail(screenshot == nil ? "Google's page wouldn't take the question. Try again." : Self.screenshotFailure)
            }
        }
    }

    private static let screenshotFailure =
        "Google's page wouldn't take the screenshot. Try again, or ask Gemini about it."

    private func fail(_ message: String) {
        isContinuable = false
        cancelTimers()
        transition(to: .failed(message))
    }

    /// The page holds a finished conversation it can be asked more in.
    private var canContinueOnPage: Bool {
        if AIModeDebug.forcesFallback { return false }
        guard isContinuable, isSearchActive, !isFrozen, state == .complete,
              acceptsMessages, pageID != nil, !webView.isLoading,
              let url = webView.url, AIModePage.isResultsPage(url) else { return false }
        return true
    }

    /// Stops loading and freezes the answer as it stands.
    func stop() {
        guard isSearchActive, !isFrozen else { return }
        isFrozen = true
        isContinuable = false
        pendingAsk = nil
        if webView.isLoading { webView.stopLoading() }
        freezePage()
        cancelTimers()
        switch state {
        case .loading, .streaming:
            if snapshot.isEmpty {
                transition(to: .idle)
            } else {
                snapshot.isComplete = true
                transition(to: .complete)
            }
        case .idle, .complete, .needsAttention, .failed:
            break
        }
    }

    /// Back to idle. Keeps the page (and its warm connection) alive.
    func reset() {
        if isSearchActive {
            if webView.isLoading { webView.stopLoading() }
            freezePage()
        }
        cancelTimers()
        isSearchActive = false
        isFrozen = false
        isContinuable = false
        pendingAsk = nil
        fileForPicker = nil
        userRevealedPage = false
        state = .idle
        snapshot = .empty
        syncReader()
    }

    /// Loads google.com in the background so the first real search doesn't pay
    /// for a cold start. Harmless to call repeatedly.
    func prewarm() {
        guard !hasLoadedPage else { return }
        hasLoadedPage = true
        webView.load(URLRequest(url: AIModeQuery.homeURL(languageCode: AIModeQuery.preferredLanguageCode)))
    }

    /// The result panel reports when it shows the page because the user asked
    /// to see it, so Google's chrome can be stripped (when reader mode is on)
    /// while it's on screen — and only then, since the extractor doesn't need
    /// it and the clean-up isn't free.
    func setPageRevealed(_ revealed: Bool) {
        guard userRevealedPage != revealed else { return }
        userRevealedPage = revealed
        syncReader()
    }

    // MARK: - Messages from the page

    fileprivate func receive(_ body: Any, fromMainFrame: Bool) {
        guard fromMainFrame, acceptsMessages, let json = body as? String else { return }
        let message: AIModeMessage
        do {
            message = try AIModeMessage.decode(json)
        } catch {
            aiModeLog.error("Unreadable message from the page: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let id = message.pageID {
            if pageID == nil {
                pageID = id
                syncReader(force: true)
            } else if pageID != id {
                return  // a late message from the document before this one
            }
        }
        if let error = message.error {
            aiModeLog.error("Extractor error: \(error, privacy: .public)")
        }
        reportAccount(from: message)
        guard isSearchActive, !isFrozen, message.turn == pageTurn else { return }
        apply(message)
    }

    private func apply(_ message: AIModeMessage) {
        switch message.kind {
        case .captcha: requireAttention(.captcha)
        case .consent: requireAttention(.consent)
        case .signIn:  requireAttention(.signIn)
        case .answer, .loading:
            let next = message.snapshot
            guard !next.isEmpty else {
                // Back to a normal page with nothing on it yet: a consent
                // dialog accepted in place, say. Carry on waiting.
                if case .needsAttention(let why) = state, why != .unreadable {
                    transition(to: .loading)
                    armStallTimer()
                }
                return
            }
            unreadableTimer?.cancel()
            unreadableTimer = nil
            followUpTimer?.cancel()
            followUpTimer = nil
            if next != snapshot {
                snapshot = next
                armStallTimer()
            }
            if next.isComplete {
                stallTimer?.cancel()
                stallTimer = nil
                transition(to: .complete)
                isContinuable = true
            } else {
                transition(to: .streaming)
            }
        }
    }

    private func reportAccount(from message: AIModeMessage) {
        guard let signedIn = message.signedIn else { return }
        // A page loaded before the cookies changed can't speak for the new
        // session.
        guard pageGeneration == session.cookieGeneration else { return }
        let report = AccountReport(account: message.account, signedIn: signedIn)
        guard report != lastAccountReport else { return }
        lastAccountReport = report
        session.noteAccount(message.account, signedIn: signedIn)
    }

    // MARK: - Navigation

    fileprivate func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy {
        guard let url = action.request.url, action.targetFrame?.isMainFrame == true else { return .allow }
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https" else {
            if scheme == "about" || scheme == "blob" || scheme == "data" { return .allow }
            if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
            return .cancel
        }
        // While Google needs the user, the page is theirs to click through
        // (CAPTCHA help, consent options, a multi-step sign-in). Otherwise a
        // click means "take me there", and there is the user's browser.
        if action.navigationType == .linkActivated, !isAwaitingUser, !isSameDocument(url) {
            openExternally(url)
            return .cancel
        }
        classify(url)
        return .allow
    }

    /// Google usually redirects to its CAPTCHA and consent pages, so the URL
    /// alone tells us before the page even draws. A return to a results page
    /// means the user got through, and the search simply carries on.
    fileprivate func classify(_ url: URL) {
        guard isSearchActive, !isFrozen else { return }
        if let kind = AIModePageKind(url: url) {
            switch kind {
            case .captcha:          requireAttention(.captcha)
            case .consent:          requireAttention(.consent)
            case .signIn:           requireAttention(.signIn)
            case .answer, .loading: break
            }
        } else if AIModePage.isResultsPage(url), isAwaitingUser {
            aiModeLog.info("Back on a results page; resuming")
            transition(to: .loading)
            armStallTimer()
        }
    }

    fileprivate func didCommit() {
        documentsCommitted += 1
        acceptsMessages = true
        pageID = nil
        // A new document starts its questions from 0, and whatever
        // conversation it shows, it isn't one Flyby has read to the end.
        pageTurn = 0
        isContinuable = false
        lastAccountReport = nil
        readerRequested = nil
        pageGeneration = session.cookieGeneration
        if let url = webView.url { classify(url) }
    }

    fileprivate func didFinish() {
        syncReader(force: true)
        // Re-send the page's state, in case a message raced the commit.
        webView.flybyRun("(function(){var f=window.__flyby;if(f&&f.poke)f.poke();return true;})()", in: Self.contentWorld)
        // The start page a screenshot question waits for. Not a CAPTCHA or a
        // consent wall on the way: those hold the question until the user
        // gets through and the page comes back.
        if let pending = pendingAsk, pending.searchID == searchID, isSearchActive, !isFrozen, state == .loading {
            pendingAsk = nil
            askOnPage(pending.question, attaching: pending.screenshot, onFreshPage: true, fallback: nil)
            return
        }
        guard isSearchActive, !isFrozen, state == .loading, snapshot.isEmpty,
              let url = webView.url, AIModePage.isResultsPage(url) else { return }
        armUnreadableTimer()
    }

    fileprivate func didFail(_ error: Error) {
        let nsError = error as NSError
        // Superseded by the next search, or cancelled by our own policy.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 || nsError.code == 204 { return }
        guard isSearchActive, !isFrozen, state != .complete else { return }
        aiModeLog.error("Load failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
        isContinuable = false
        cancelTimers()
        transition(to: .failed(nsError.localizedDescription))
    }

    fileprivate func contentProcessDidTerminate() {
        aiModeLog.error("The page's web content process terminated")
        acceptsMessages = false
        isContinuable = false
        pageID = nil
        hasLoadedPage = false
        guard isSearchActive, !isFrozen else { return }
        switch state {
        case .loading, .streaming, .needsAttention:
            cancelTimers()
            if snapshot.isEmpty {
                transition(to: .failed("Google's page stopped unexpectedly. Try again."))
            } else {
                snapshot.isComplete = true
                transition(to: .complete)
            }
        case .idle, .complete, .failed:
            break
        }
    }

    /// Opens a link from the page in the user's browser. Google's redirect
    /// wrapper and text-fragment highlight are stripped on the way.
    fileprivate func openExternally(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(AIModeLinks.sanitize(url) ?? url)
        // Mid-CAPTCHA, a help link shouldn't close the panel on the user.
        if !isAwaitingUser {
            NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
        }
    }

    // MARK: - Timers

    private func armStallTimer() {
        stallTimer?.cancel()
        let id = searchID
        stallTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: AIModeEngine.stallAfter)
            guard !Task.isCancelled else { return }
            self?.stallTimerFired(searchID: id)
        }
    }

    private func armUnreadableTimer() {
        unreadableTimer?.cancel()
        let id = searchID
        unreadableTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: AIModeEngine.unreadableAfter)
            guard !Task.isCancelled else { return }
            self?.unreadableTimerFired(searchID: id)
        }
    }

    /// Sent, but is the page answering? If nothing of the answer shows up,
    /// the follow-up is asked as a search instead: slower, but an answer. A
    /// question asked on a fresh page has no search to fall back on.
    private func armFollowUpTimer(fallback: String?, attaching screenshot: Screenshot?) {
        followUpTimer?.cancel()
        let id = searchID
        followUpTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: AIModeEngine.followUpSilentAfter)
            guard !Task.isCancelled, let self else { return }
            guard id == self.searchID, self.isSearchActive, !self.isFrozen,
                  self.state == .loading, self.snapshot.isEmpty else { return }
            if let fallback {
                aiModeLog.error("The page took the follow-up but never answered it; searching with the conversation in the query")
                self.search(fallback, attaching: screenshot)
            } else {
                aiModeLog.error("The page took the question but never answered it")
                self.fail("Google took the question but never answered. Try again.")
            }
        }
    }

    private func cancelTimers() {
        stallTimer?.cancel()
        stallTimer = nil
        unreadableTimer?.cancel()
        unreadableTimer = nil
        followUpTimer?.cancel()
        followUpTimer = nil
    }

    private func stallTimerFired(searchID id: Int) {
        guard id == searchID, isSearchActive, !isFrozen else { return }
        switch state {
        case .loading:
            // A results page that committed but never produced an answer is
            // better shown than failed; no page at all is a failure.
            if acceptsMessages, let url = webView.url, AIModePage.isResultsPage(url) {
                aiModeLog.error("No answer could be read before the watchdog")
                transition(to: .needsAttention(.unreadable))
            } else {
                aiModeLog.error("Google didn't respond before the watchdog")
                isFrozen = true
                if webView.isLoading { webView.stopLoading() }
                freezePage()
                transition(to: .failed("Google didn't respond. Check your connection and try again."))
            }
        case .streaming:
            // Growing stopped without Google saying it's done.
            aiModeLog.info("Answer stalled; treating it as complete")
            snapshot.isComplete = true
            transition(to: .complete)
        case .idle, .complete, .needsAttention, .failed:
            break
        }
    }

    private func unreadableTimerFired(searchID id: Int) {
        guard id == searchID, isSearchActive, !isFrozen, state == .loading, snapshot.isEmpty else { return }
        aiModeLog.error("The page loaded but no answer could be read from it")
        transition(to: .needsAttention(.unreadable))
    }

    // MARK: - Helpers

    /// Captcha, consent or sign-in on screen: the page belongs to the user.
    private var isAwaitingUser: Bool {
        if case .needsAttention(let why) = state { return why != .unreadable }
        return false
    }

    private func requireAttention(_ why: Attention) {
        guard isSearchActive, !isFrozen else { return }
        if state != .needsAttention(why) {
            aiModeLog.info("Google needs the user: \(String(describing: why), privacy: .public)")
        }
        cancelTimers()
        isContinuable = false
        transition(to: .needsAttention(why))
    }

    private func transition(to next: State) {
        guard state != next else { return }
        state = next
        syncReader()
    }

    /// Reader mode strips Google's chrome, but only while the user is looking
    /// at the page for its content — never on a CAPTCHA, consent or sign-in
    /// page, where the script leaves the page alone anyway.
    private func syncReader(force: Bool = false, readerMode: Bool? = nil) {
        let revealed = userRevealedPage || state == .needsAttention(.unreadable)
        let wanted = (readerMode ?? AppSettings.shared.readerMode) && revealed
        guard force || wanted != readerRequested else { return }
        readerRequested = wanted
        webView.flybyRun(
            "(function(){var f=window.__flyby;if(f&&f.setReader)f.setReader(\(wanted));return true;})()",
            in: Self.contentWorld
        )
    }

    /// Stops the current document's extractor, so nothing it says can land
    /// on top of the next search.
    private func freezePage() {
        webView.flybyRun("(function(){var f=window.__flyby;if(f&&f.stop)f.stop();return true;})()", in: Self.contentWorld)
    }

    private func isSameDocument(_ url: URL) -> Bool {
        guard url.fragment != nil, let current = webView.url else { return false }
        return Self.withoutFragment(url) == Self.withoutFragment(current)
    }

    private static func withoutFragment(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

/// The page's delegates and script message handler. A separate object holding
/// the engine weakly: `WKUserContentController` retains its message handlers
/// for as long as the web view lives, which would otherwise be a cycle.
@MainActor
private final class AIModeWebBridge: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var engine: AIModeEngine?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        engine?.receive(message.body, fromMainFrame: message.frameInfo.isMainFrame)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(engine?.policy(for: navigationAction) ?? .allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame, let url = navigationResponse.response.url {
            engine?.classify(url)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url { engine?.classify(url) }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        engine?.didCommit()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        engine?.didFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        engine?.didFail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        engine?.didFail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        engine?.contentProcessDidTerminate()
    }

    /// `target="_blank"` links and `window.open`: to the user's browser. The
    /// page never gets a second window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            engine?.openExternally(url)
        }
        return nil
    }

    /// A file input was clicked: answered with the file being attached, if
    /// any, without a dialog.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        let file = engine?.fileForPicker
        aiModeLog.info("The page asked for a file (\(file == nil ? "none to give" : "attaching one", privacy: .public))")
        completionHandler(file.map { [$0] })
    }
}

/// Hosts the engine's single web view. Reparents rather than recreating, so
/// the page, its scroll position and its session survive the result panel
/// closing and reopening.
struct WebLayer: NSViewRepresentable {
    @ObservedObject var engine: AIModeEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        engine.webView.removeFromSuperview()
        engine.webView.frame = container.bounds
        engine.webView.autoresizingMask = [.width, .height]
        container.addSubview(engine.webView)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if engine.webView.superview !== container {
            engine.webView.removeFromSuperview()
            engine.webView.frame = container.bounds
            engine.webView.autoresizingMask = [.width, .height]
            container.addSubview(engine.webView)
        }
    }
}
