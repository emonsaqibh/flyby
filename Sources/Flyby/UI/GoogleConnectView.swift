import SwiftUI
import AppKit
import FlybyCore

/// Connecting Flyby to the user's Google account — the thing that turns AI
/// Mode from "an anonymous client Google keeps quizzing" into "your browser,
/// basically".
///
/// Shared by Settings and onboarding. In Settings it's a set of sections for
/// a grouped `Form`; in onboarding it's one stacked card. Same rows either way.
///
/// Everything a step asks of the user — Full Disk Access, a Keychain prompt,
/// signing in somewhere first — is said before they click, and when a step
/// fails the fix is drawn right where it failed.
struct GoogleConnectView: View {
    enum Layout {
        /// Sections, for a grouped `Form`.
        case form
        /// One stacked column, for a card.
        case card
    }

    var layout: Layout = .form
    @ObservedObject private var session = GoogleSession.shared

    @ViewBuilder
    var body: some View {
        switch layout {
        case .form: formBody
        case .card: cardBody
        }
    }

    @ViewBuilder
    private var formBody: some View {
        Section {
            GoogleStatusRow(session: session)
            if let problem = session.problem {
                GoogleProblemRow(problem: problem, session: session)
            }
        } footer: {
            Text("AI Mode runs Google in your own session, so Google treats Flyby like your browser — and rarely asks if you're human.")
        }

        Section("Use your browser's sign-in") {
            if browsers.isEmpty {
                NoBrowsersNote()
            } else {
                ForEach(browsers) { browser in
                    GoogleBrowserRow(browser: browser, session: session)
                }
            }
        }

        Section {
            InAppSignInRow(session: session, isPrimary: browsers.isEmpty)
        } footer: {
            PrivacyNote()
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            GoogleStatusRow(session: session)
            if let problem = session.problem {
                GoogleProblemRow(problem: problem, session: session)
            }

            Divider()

            if browsers.isEmpty {
                NoBrowsersNote()
            } else {
                ForEach(browsers) { browser in
                    GoogleBrowserRow(browser: browser, session: session)
                    if browser != browsers.last { Divider() }
                }
            }

            Divider()

            InAppSignInRow(session: session, isPrimary: browsers.isEmpty)
            PrivacyNote()
        }
        .animation(.easeOut(duration: 0.2), value: session.problem)
    }

    private var browsers: [Browser] { session.availableBrowsers }
}

// MARK: - Status

private struct GoogleStatusRow: View {
    @ObservedObject var session: GoogleSession
    @State private var disconnecting = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.isConnected ? "checkmark.circle.fill" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 20))
                .foregroundStyle(session.isConnected ? Color.green : Color.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if session.isConnected {
                Button("Disconnect") {
                    disconnecting = true
                    Task {
                        await session.disconnect()
                        disconnecting = false
                    }
                }
                .disabled(disconnecting)
            }
        }
    }

    private var title: String {
        guard case .connected(let method, _) = session.connection else { return "Not connected" }
        if case .browser(let browser) = method {
            return "Connected through \(browser.displayName)"
        }
        return "Signed in within Flyby"
    }

    private var detail: String {
        guard case .connected(_, let account) = session.connection else {
            return "AI Mode still works, but Google asks anonymous visitors to prove they're human far more often."
        }
        if let account {
            return "Signed in as \(account.displayName)"
        }
        return "Using your Google account"
    }
}

// MARK: - Problems

/// The last attempt's failure, with the fix for that particular failure.
private struct GoogleProblemRow: View {
    let problem: GoogleSession.Problem
    @ObservedObject var session: GoogleSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    session.clearProblem()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
                .accessibilityLabel("Dismiss")
            }

            actions
                .controlSize(.small)
                .padding(.leading, 24)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.09))
        )
    }

    // `if case` rather than `switch`: a problem this view doesn't know yet
    // still gets its message shown, instead of failing the build.
    private var message: String {
        if case .needsFullDiskAccess = problem {
            return "macOS keeps this browser's cookies in a protected folder. Turn on Flyby under Full Disk Access — Flyby will pick it up when you come back."
        }
        if case .keychainDenied(let browser) = problem {
            return "macOS didn't let Flyby read “\(browser.displayName) Safe Storage” from your Keychain. Click Connect again and choose Always Allow."
        }
        if case .notSignedIn(let browser) = problem {
            return "\(browser.displayName) isn't signed in to Google. Sign in to Google in \(browser.displayName) first, then connect."
        }
        if case .failed(let reason) = problem {
            return reason
        }
        return "Flyby couldn't connect to your Google account."
    }

    @ViewBuilder
    private var actions: some View {
        if case .needsFullDiskAccess = problem {
            Button("Open Full Disk Access Settings") {
                GoogleSession.openFullDiskAccessSettings()
            }
        } else if case .keychainDenied(let browser) = problem {
            Button("Connect Again") {
                Task { await session.connect(using: browser) }
            }
            .disabled(session.busyWith != nil)
        } else if case .notSignedIn(let browser) = problem {
            HStack(spacing: 8) {
                Button("Sign in to Google in \(browser.displayName)") {
                    session.openSignInPage(in: browser)
                }
                Button("Connect Again") {
                    Task { await session.connect(using: browser) }
                }
                .disabled(session.busyWith != nil)
            }
        }
    }
}

// MARK: - Browsers

private struct GoogleBrowserRow: View {
    let browser: Browser
    @ObservedObject var session: GoogleSession

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BrowserIcon(browser: browser)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(browser.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(browser.permissionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // Said before connecting, not discovered a few hours after.
                if let caveat = session.caveat(for: browser) {
                    Label(caveat, systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            trailing
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if session.busyWith == browser {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else if isConnectedHere {
            // Re-copying picks up a session the browser has since rotated —
            // the fix when AI Mode starts asking questions again.
            Button("Reconnect") { connect() }
                .disabled(session.busyWith != nil)
                .help("Copy \(browser.displayName)'s Google sign-in again")
        } else if session.isConnected {
            Button("Connect") { connect() }
                .disabled(session.busyWith != nil)
                .accessibilityLabel("Connect with \(browser.displayName)")
        } else {
            Button("Connect") { connect() }
                .buttonStyle(.borderedProminent)
                .disabled(session.busyWith != nil)
                .accessibilityLabel("Connect with \(browser.displayName)")
        }
    }

    private var isConnectedHere: Bool {
        guard case .connected(let method, _) = session.connection,
              case .browser(let connected) = method else { return false }
        return connected == browser
    }

    private func connect() {
        Task { await session.connect(using: browser) }
    }
}

/// The browser's real icon, from wherever it's installed. Looked up once per
/// browser: `NSWorkspace` hits the disk for both halves.
private struct BrowserIcon: View {
    let browser: Browser

    var body: some View {
        if let icon = AppIconCache.icon(forBundleIdentifier: browser.bundleIdentifier) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

@MainActor
private enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(forBundleIdentifier identifier: String) -> NSImage? {
        if let cached = icons[identifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[identifier] = icon
        return icon
    }
}

/// Nothing to borrow from: say which browsers would work, and point at the
/// fallback right below.
private struct NoBrowsersNote: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Flyby can borrow your Google sign-in from Safari or Firefox, but found neither browser's cookies on this Mac. Sign in within Flyby instead.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Alternatives

/// Signing in inside Flyby's own window. A fallback rather than the default:
/// Google is wary of sign-ins from embedded browsers and sometimes refuses
/// them outright. It becomes the main button when there's no browser to
/// borrow from.
private struct InAppSignInRow: View {
    @ObservedObject var session: GoogleSession
    let isPrimary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isPrimary {
                Button("Sign In to Google within Flyby…") {
                    session.signInWithinFlyby()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Sign in within Flyby instead…") {
                    session.signInWithinFlyby()
                }
                .buttonStyle(.link)
            }
            Text("Google may refuse sign-ins from embedded windows.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PrivacyNote: View {
    var body: some View {
        Label {
            Text("Flyby copies only google.com cookies into its own private store. Nothing leaves your Mac.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.fill")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
