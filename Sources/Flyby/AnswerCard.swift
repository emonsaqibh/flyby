import SwiftUI
import AppKit
import FlybyCore

/// What the card holds: two round buttons in its top corners, and under
/// them the conversation, the history list, or — in AI Mode, when Google
/// needs the user or they ask for it — Google's own page. The input and the
/// provider button along the bottom edge aren't in here: they belong to the
/// stage, because they're the bar too.
///
/// Three layers, back to front, in a structure that never changes shape
/// while a search runs:
///
/// 1. The page. Mounted for as long as a live AI Mode turn is on screen and
///    hidden with opacity, never removed — the extractor reads the answer out
///    of it, so unmounting it mid-search would stop the search.
/// 2. The conversation (or the history list), which scrolls the full height
///    of the card, under the buttons and the input, and dissolves at both.
/// 3. The corner buttons.
///
/// The glass and the card's shape come from the stage, which animates them;
/// nothing here branches around the page, since a branch would rebuild — and
/// remount — it.
struct AnswerCard: View {
    @ObservedObject var controller: SearchController
    /// Where questions fly in from, shared with the input.
    let questions: Namespace.ID

    var body: some View {
        ZStack(alignment: .top) {
            pageLayer

            // Removed, not hidden, while the page shows: an invisible scroll
            // view above the page would still catch its scrolling, and the
            // page may be a CAPTCHA the user has to reach.
            if controller.showsHistory {
                HistoryView(controller: controller)
                    .transition(.opacity)
            } else if !isWeb {
                ConversationView(controller: controller, questions: questions)
                    .transition(.opacity)
            }

            CardCorners(controller: controller)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.22), value: isWeb)
        .animation(.easeInOut(duration: 0.2), value: controller.showsHistory)
        // Links in answers go to the user's real browser, never in place.
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }

    private var isWeb: Bool { controller.showsWebPage }

    private var attention: AIModeEngine.Attention? {
        if case .needsAttention(let why) = controller.phase { return why }
        return nil
    }

    /// Inset in the card between the buttons and the input, with the card's
    /// curve, so Google's opaque page sits in the dark glass like a screen in
    /// a bezel. The banner sits in the flow above the page rather than over
    /// it: when Google wants a CAPTCHA solved, every pixel of the page has to
    /// be reachable.
    @ViewBuilder
    private var pageLayer: some View {
        if controller.canShowWebPage {
            VStack(spacing: 10) {
                if let attention, isWeb {
                    AttentionBanner(attention: attention) { controller.submitToBrowser() }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                WebLayer(engine: controller.aiMode)
                    .clipShape(RoundedRectangle(cornerRadius: CardMetrics.innerRadius, style: .continuous))
                    .opacity(isWeb ? 1 : 0)
                    .allowsHitTesting(isWeb)
                    .accessibilityHidden(!isWeb)
            }
            .padding(.horizontal, CardMetrics.edgeInset)
            .padding(.top, CardMetrics.headerInset)
            .padding(.bottom, CardMetrics.footerInset)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: attention)
        }
    }
}

// MARK: - Corners

/// ✕ top-left; Open in Browser top-right, with its shortcut on it, so the key
/// is learned by looking. Recent Chats is the pill under the card. What a
/// header used to hold besides these — stop, search again, copy, the page
/// toggle, new chat — is the provider chip's: it becomes Stop while an answer
/// runs, and the rest are in its menu and on the keyboard.
private struct CardCorners: View {
    @ObservedObject var controller: SearchController

    var body: some View {
        HStack(alignment: .top) {
            GlassGroup {
                GlassCircleButton(
                    systemImage: goesBackToChat ? "chevron.backward" : "xmark",
                    label: closeLabel,
                    help: "\(closeLabel) (esc)",
                    action: close
                )
            }

            Spacer(minLength: 0)

            if offersBrowser {
                GlassGroup {
                    GlassKeyButton(
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        shortcut: "⌘↩",
                        label: "Open in Browser"
                    ) {
                        controller.submitToBrowser()
                    }
                }
                .transition(.scale(scale: 0.6, anchor: .trailing).combined(with: .opacity))
            }
        }
        .padding(CardMetrics.edgeInset)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: offersBrowser)
    }

    /// The history list is over a conversation, so ✕ goes back to it.
    private var goesBackToChat: Bool { controller.showsHistory && controller.isResultVisible }

    private var closeLabel: String {
        if goesBackToChat { return "Back to Chat" }
        return controller.showsHistory ? "Close Recent Chats" : "Close"
    }

    /// Only once there's a question to take there.
    private var offersBrowser: Bool { !controller.showsHistory && !controller.submittedQuery.isEmpty }

    /// Esc, as a button: out of the history list first, then away.
    private func close() {
        if controller.showsHistory {
            controller.closeHistory()
        } else {
            NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
        }
    }
}
