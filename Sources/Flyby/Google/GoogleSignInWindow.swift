import AppKit
import WebKit
import os
import FlybyCore

private let signInLog = Logger(subsystem: "com.fringecore.flyby", category: "google-signin")

/// Flyby's own Google sign-in: a small window with a web view on
/// `GoogleSession.dataStore`, so the session it ends with is the one AI Mode
/// runs in.
///
/// Best effort. Google has refused sign-in from embedded browser frameworks
/// since 2021 for many accounts; the window recognises that refusal, says so
/// in its footer, and leaves the user to pick a browser instead.
@MainActor
final class GoogleSignInWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    static let rejectionMessage = "Google doesn't allow signing in from embedded windows. Connect with Safari or Firefox instead."
    private static let footerText = "If Google won't let you sign in here, connect with your browser instead."
    private static let accountLabelScript =
        "(function(){var a=document.querySelector('a[href*=\"accounts.google.com/SignOutOptions\"]');return a?(a.getAttribute('aria-label')||''):'';})()"
    private static let rejectionTextScript =
        "(function(){return document.body?(document.body.innerText||'').slice(0,5000):'';})()"

    /// Called once, when the window lands back on Google signed in.
    var onSignedIn: ((GoogleAccount?) -> Void)?
    /// Google turned the embedded window away.
    var onRejected: (() -> Void)?
    var onClose: (() -> Void)?

    private let dataStore: WKWebsiteDataStore
    private let window: NSWindow
    private let webView: WKWebView
    private let footer: NSTextField
    private var finished = false
    private var checkingSession = false
    private var rejected = false

    init(dataStore: WKWebsiteDataStore) {
        self.dataStore = dataStore
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 590),
            configuration: GoogleWebIdentity.configuration(dataStore: dataStore)
        )
        footer = NSTextField(wrappingLabelWithString: GoogleSignInWindow.footerText)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Sign in to Google"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 380, height: 480)
        window.contentView = makeContent()
        window.delegate = self
        window.center()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.appearance = AppSettings.shared.appearance.nsAppearance
        if let url = URL(string: GoogleSession.signInURLString) {
            webView.load(URLRequest(url: url))
        }
    }

    func show() {
        // A menu-bar app isn't frontmost by default; without this the window
        // opens behind whatever the user was in.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    private func makeContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        let divider = NSBox()
        divider.boxType = .separator

        footer.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .center
        footer.preferredMaxLayoutWidth = 440
        footer.setContentCompressionResistancePriority(.required, for: .vertical)

        for view in [webView, divider, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.topAnchor.constraint(equalTo: webView.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 10),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])
        return root
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        webView.stopLoading()
        onClose?()
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, navigationAction.targetFrame?.isMainFrame == true else {
            decisionHandler(.allow)
            return
        }
        if Self.isRejection(url) { noteRejected() }
        // Help and privacy links belong in the user's browser, not in here.
        if navigationAction.navigationType == .linkActivated, !Self.belongsToSignIn(url) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        if Self.isRejection(url) {
            noteRejected()
        } else if AIModePage.isSearchHost(url) {
            checkForSession()
        } else if AIModePageKind(url: url) == .signIn {
            checkForRejectionText()
        }
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if AIModePageKind(url: url) == .signIn {
            webView.load(URLRequest(url: url))
        } else if url.scheme == "https" || url.scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    // MARK: - Outcome

    /// Landing back on google.com with a session cookie in the store means the
    /// sign-in went through.
    private func checkForSession() {
        guard !finished, !checkingSession else { return }
        checkingSession = true
        Task { [weak self] in
            guard let self else { return }
            let cookies = await self.dataStore.httpCookieStore.flybyAllCookies()
            self.checkingSession = false
            guard !self.finished, GoogleSession.hasSession(cookies) else { return }
            let label = await self.webView.flybyString(Self.accountLabelScript, in: .defaultClient)
            self.finish(account: label.flatMap { GoogleAccount(accountLabel: $0) })
        }
    }

    /// The URL check is the reliable one; this catches the refusal pages
    /// that don't say so in their path (English only — the path covers the
    /// rest).
    private func checkForRejectionText() {
        guard !rejected else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let text = await self.webView.flybyString(Self.rejectionTextScript, in: .defaultClient) else { return }
            let refusals = ["Couldn't sign you in", "Couldn’t sign you in", "This browser or app may not be secure"]
            if refusals.contains(where: { text.contains($0) }) { self.noteRejected() }
        }
    }

    private func noteRejected() {
        guard !rejected, !finished else { return }
        rejected = true
        signInLog.info("Google refused sign-in from the embedded window")
        footer.stringValue = Self.rejectionMessage
        footer.font = .boldSystemFont(ofSize: 13)
        footer.textColor = .systemRed
        onRejected?()
    }

    private func finish(account: GoogleAccount?) {
        guard !finished else { return }
        finished = true
        onSignedIn?(account)
        window.close()
    }

    private static func isRejection(_ url: URL) -> Bool {
        guard AIModePageKind(url: url) == .signIn,
              let path = URLComponents(url: url, resolvingAgainstBaseURL: true)?.path.lowercased() else { return false }
        return path.contains("/rejected")
    }

    /// Google's account pages and the hops a sign-in makes through
    /// google.com (and YouTube, which Google signs in alongside).
    private static func belongsToSignIn(_ url: URL) -> Bool {
        if AIModePageKind(url: url) == .signIn || AIModePage.isSearchHost(url) { return true }
        guard let host = URLComponents(url: url, resolvingAgainstBaseURL: true)?.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }
}
