import SwiftUI
import AppKit
import FlybyCore

/// Contents of the panel above the pill: a floating control row, then either
/// the native answer or — in AI Mode, when Google needs the user or they ask
/// for it — Google's own page.
///
/// Three layers, back to front, in a structure that never changes shape
/// while a search runs:
///
/// 1. The page. Mounted for as long as AI Mode is the provider on screen and
///    hidden with opacity, never removed — the extractor reads the answer out
///    of it, so unmounting it mid-search would stop the search.
/// 2. The native answer, which scrolls up under the header.
/// 3. The header.
///
/// Nothing *above* the page branches on whether it's showing: the backing and
/// the glass switch by parameter, not by `if`, because a branch around the
/// page would rebuild — and remount — it.
struct ResultPanelView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .top) {
            pageLayer

            // Removed, not hidden, while the page shows: an invisible scroll
            // view above the page would still catch its scrolling, and the
            // page may be a CAPTCHA the user has to reach.
            if !isWeb {
                AnswerView(
                    controller: controller,
                    topInset: PanelMetrics.headerHeight,
                    fadesUnderHeader: usesGlass
                )
                .transition(.opacity)
            }

            PanelHeader(controller: controller, hasBar: !usesGlass || isWeb)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The web view paints its own opaque page, so glass behind it would
        // never be seen — that mode gets a plain theme-aware backing instead.
        .background {
            if isWeb { Color(nsColor: .textBackgroundColor) }
        }
        .clipShape(PanelMetrics.shape)
        // `.regular`, not interactive: this is something you read, and glass
        // that shimmers under the pointer is a distraction in it.
        .surface(PanelMetrics.shape, isVisible: !isWeb)
        .animation(.easeInOut(duration: 0.22), value: isWeb)
        .themed()
        // Links in answers go to the user's real browser, never in place.
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    private var isWeb: Bool { controller.showsWebPage }

    private var usesGlass: Bool {
        LiquidGlass.isSupported && settings.liquidGlass && !reduceTransparency
    }

    private var attention: AIModeEngine.Attention? {
        if case .needsAttention(let why) = controller.phase { return why }
        return nil
    }

    /// Below the header rather than under it: when Google wants a CAPTCHA
    /// solved, every pixel of the page has to be reachable. The banner sits in
    /// the flow above the page for the same reason — pinned over it, it would
    /// cover exactly the checkbox the user needs.
    @ViewBuilder
    private var pageLayer: some View {
        if controller.canShowWebPage {
            VStack(spacing: 0) {
                if let attention {
                    AttentionBanner(attention: attention) { controller.submitToBrowser() }
                        .padding(.horizontal, PanelMetrics.edgeInset)
                        .padding(.top, 2)
                        .padding(.bottom, PanelMetrics.edgeInset)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                WebLayer(engine: controller.aiMode)
                    .opacity(isWeb ? 1 : 0)
                    .allowsHitTesting(isWeb)
                    .accessibilityHidden(!isWeb)
            }
            .padding(.top, PanelMetrics.headerHeight)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: attention)
        }
    }
}

/// Geometry shared by the panel's pieces.
enum PanelMetrics {
    /// Tighter than the pill's half-height, as macOS 27's window corners are,
    /// but still clearly the pill's sibling.
    static let cornerRadius: CGFloat = 22
    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    static let headerHeight: CGFloat = 54
    /// How far floating elements sit in from the panel's edge.
    static let edgeInset: CGFloat = 10
    /// Concentric with the panel's corner: inner radius = outer − inset.
    static var innerRadius: CGFloat { cornerRadius - edgeInset }
}

// MARK: - Header

extension SearchController {
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
}

/// The query, what's happening to it, and the handful of things you might
/// want to do about it — as small glass buttons that merge and split as the
/// set changes, the way Spotlight's do.
private struct PanelHeader: View {
    @ObservedObject var controller: SearchController
    /// A material bar behind the row: for the classic look, and over the page,
    /// where there's no scrolling content to dissolve under a bare row.
    var hasBar: Bool

    @State private var justCopied = false

    var body: some View {
        HStack(spacing: 10) {
            statusGlyph
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(controller.submittedQuery)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            controls
        }
        .padding(.leading, 16)
        .padding(.trailing, PanelMetrics.edgeInset)
        .frame(height: PanelMetrics.headerHeight)
        .background {
            if hasBar {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .overlay(alignment: .bottom) {
            if hasBar { Divider().opacity(0.6) }
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusGlyph: some View {
        if controller.isBusy {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Working")
        } else if case .failed = controller.phase {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        } else if case .needsAttention = controller.phase {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
        } else {
            Image(systemName: controller.activeProvider?.icon ?? "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// "Google AI Mode · Answering…" — which provider, and what it's doing.
    private var statusLine: String {
        let status: String
        switch controller.phase {
        case .idle:           status = ""
        case .working:        status = controller.activeProvider == .aiMode ? "Searching Google…" : "Thinking…"
        case .streaming:      status = "Answering…"
        case .complete:       status = controller.showsWebPage ? "Google's page" : ""
        case .needsAttention: status = "Waiting for you"
        case .failed:         status = "Didn't finish"
        }
        return [controller.activeProvider?.label ?? "", status]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: Controls

    /// The shortcuts in the tooltips are handled app-wide, by the app
    /// delegate's key monitor: typing stays in the pill, so this panel is
    /// almost never the key window and shortcuts attached here would never
    /// fire.
    private var controls: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                if controller.isBusy {
                    headerButton("Stop", systemImage: "stop.fill", help: "Stop (⌘.)") {
                        controller.stop()
                    }
                } else if controller.offersRetry {
                    headerButton("Search Again", systemImage: "arrow.clockwise", help: "Search again (⌘R)") {
                        controller.retry()
                    }
                }

                if !controller.answer.isEmpty {
                    headerButton(
                        justCopied ? "Copied" : "Copy Answer",
                        systemImage: justCopied ? "checkmark" : "doc.on.doc",
                        help: "Copy answer (⌘⇧C)"
                    ) {
                        copy()
                    }
                }

                if showsPageToggle {
                    headerButton(
                        controller.prefersWebPage ? "Show Answer" : "Show Google's Page",
                        systemImage: controller.prefersWebPage ? "text.alignleft" : "globe",
                        help: controller.prefersWebPage ? "Back to Flyby's answer" : "Show Google's page"
                    ) {
                        controller.prefersWebPage.toggle()
                    }
                }

                headerButton("Open in Browser", systemImage: "arrow.up.forward.app", help: "Open in your browser (⌘↩)") {
                    controller.submitToBrowser()
                }

                headerButton("Close", systemImage: "xmark", help: "Close (esc)") {
                    NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: controller.isBusy)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: controller.answer.isEmpty)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showsPageToggle)
    }

    /// Only when there's a page behind the answer, and not while Google is
    /// holding the page open for the user anyway.
    private var showsPageToggle: Bool {
        guard controller.canShowWebPage else { return false }
        if case .needsAttention = controller.phase { return false }
        return true
    }

    private func headerButton(
        _ title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
                .contentTransition(.symbolEffect(.replace))
        }
        .flybyGlassIconButton()
        .help(help)
    }

    private func copy() {
        controller.copyAnswer()
        withAnimation(.easeOut(duration: 0.15)) { justCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeOut(duration: 0.2)) { justCopied = false }
        }
    }
}
