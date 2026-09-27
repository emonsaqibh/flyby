import AppKit
import SwiftUI

/// The one window Flyby draws in: the pill at the bottom of the screen and
/// the panel that grows up out of it.
///
/// Both live in one fixed, oversized, fully transparent window, so the panel
/// can come out of the pill and go back into it as one piece of glass — the
/// Dynamic Island's trick. Two windows can only be animated by resizing them,
/// which is a full relayout every frame and never quite in step; inside one
/// window it's a SwiftUI spring on a shape. Clicks on the transparent parts
/// fall through to whatever is underneath.
final class FlybyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    let stage: PanelStage

    init(controller: SearchController, stage: PanelStage) {
        self.stage = stage
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PillMetrics.windowWidth, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // Glass casts its own shadows, shaped like the glass; a window shadow
        // would trace the whole transparent rectangle.
        hasShadow = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: FlybyRootView(controller: controller, stage: stage))
        host.sizingOptions = []
        contentView = host
    }

    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
    }

    /// The screen the mouse is on, which is the one the user is looking at.
    static var activeScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }

    /// Covers the column the pill and the open panel can occupy, plus room for
    /// their shadows. The lower margin dips behind the Dock, which draws above
    /// it — trimming it to fit would cut the pill's shadow off.
    func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let panelWidth = StageMetrics.panelWidth(on: screen)
        let width = max(panelWidth + StageMetrics.shadowMargin * 2, PillMetrics.windowWidth)
        let bottom = visible.minY + PillMetrics.bottomInset - PillMetrics.verticalMargin
        let panelTop = visible.maxY - StageMetrics.topInset
        let panelBottom = visible.minY + PillMetrics.capsuleTop + StageMetrics.gap
        let top = panelTop + StageMetrics.shadowMargin

        stage.panelSize = CGSize(width: panelWidth, height: max(panelTop - panelBottom, 200))
        setFrame(
            NSRect(x: visible.midX - width / 2, y: bottom, width: width, height: top - bottom),
            display: true
        )
    }
}

/// Whether Flyby is on screen, and how big the panel is on this screen.
/// Opening and closing are animations of `isPresented`; the window itself
/// only appears before the first frame and goes after the last.
@MainActor
final class PanelStage: ObservableObject {
    @Published private(set) var isPresented = false
    @Published var panelSize = CGSize(width: 720, height: 600)

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A springy pop, the way the Dynamic Island opens: fast out of the gate,
    /// a small overshoot, a soft settle.
    private var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.74)
    }

    /// Closing is quicker and doesn't bounce — you're done with it.
    private var closeAnimation: Animation {
        reduceMotion ? .easeIn(duration: 0.14) : .spring(response: 0.3, dampingFraction: 0.92)
    }

    /// The panel growing out of the pill and folding back into it.
    var panelAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.8)
    }

    /// Snaps to hidden without animating, so opening always starts from the
    /// folded-up pill — even if the last close hadn't finished.
    func prepare() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
    }

    func present() {
        withAnimation(openAnimation) { isPresented = true }
    }

    func dismiss(completion: @escaping () -> Void) {
        withAnimation(closeAnimation, completionCriteria: .logicallyComplete) {
            isPresented = false
        } completion: {
            completion()
        }
    }
}

/// Where the panel sits relative to the pill and the screen.
enum StageMetrics {
    /// Between the top of the pill and the bottom of the open panel.
    static let gap: CGFloat = 14
    /// Between the top of the open panel and the top of the usable screen.
    static let topInset: CGFloat = 44
    /// Transparent room around the open panel for its shadow.
    static let shadowMargin: CGFloat = 28

    /// Wide enough to read comfortably, clamped so it doesn't sprawl on an
    /// ultrawide or overflow a laptop display.
    static func panelWidth(on screen: NSScreen) -> CGFloat {
        min(max(screen.visibleFrame.width * 0.52, 620), 960)
    }
}

enum PillMetrics {
    /// The drawn capsule.
    static let height: CGFloat = 52
    static let minWidth: CGFloat = 340
    static let maxWidth: CGFloat = 860
    static let fontSize: CGFloat = 16
    static let horizontalPadding: CGFloat = 18

    /// What the empty field says: a new search, or the next question in the
    /// conversation that's open.
    static func placeholder(inConversation: Bool) -> String {
        inConversation ? "Ask a follow-up…" : "Search anything…"
    }

    /// The leading magnifying glass / sparkle, and the gap after it.
    static let leadingIconWidth: CGFloat = 18
    static let leadingIconSpacing: CGFloat = 10
    /// Room past the last character, so the caret never touches the edge.
    static let caretAllowance: CGFloat = 12
    /// `DevBadge`, measured; only drawn in the dev build.
    static let devBadgeWidth: CGFloat = 30

    /// The provider well on the trailing edge of the classic pill. Fixed
    /// rather than measured, so the width maths doesn't have to guess at it.
    static let providerChipWidth: CGFloat = 42
    static let providerChipHeight: CGFloat = 26
    /// The classic ↩ badge.
    static let returnBadgeSize: CGFloat = 20

    /// The glass pill's bubbles beside the capsule: ↩ is a circle, the
    /// provider chip a short capsule. A little shorter than the bar so they
    /// read as secondary to it, the way Spotlight's do.
    static let bubbleSize: CGFloat = 44
    static let glassChipWidth: CGFloat = 60
    static let bubbleSpacing: CGFloat = 8

    /// Gap between the bottom of the screen and the bottom of the capsule.
    static let bottomInset: CGFloat = 32

    /// The capsule's drop shadow (the classic pill; glass brings its own).
    static let shadowRadius: CGFloat = 18
    static let shadowOffsetY: CGFloat = 6

    /// A Gaussian shadow keeps fading for about twice its radius. Give it less
    /// room than that and the window edge saws a straight line through the blur.
    static var shadowExtent: CGFloat { shadowRadius * 2 }

    /// Transparent room around the capsule, for its shadow and for it to grow
    /// into. The offset pushes the shadow down, so the vertical margin has to
    /// cover the radius *and* the offset.
    static var verticalMargin: CGFloat { shadowExtent + shadowOffsetY }
    static var horizontalMargin: CGFloat { shadowExtent }
    static var windowWidth: CGFloat { maxWidth + horizontalMargin * 2 }

    /// Top of the capsule, measured from the bottom of the visible screen area.
    static var capsuleTop: CGFloat { bottomInset + height }

    // MARK: - Width

    /// Measured against the same font the text field renders in, so the
    /// capsule tracks the caret rather than guessing.
    static func textWidth(_ query: String, inConversation: Bool) -> CGFloat {
        let text = query.isEmpty ? placeholder(inConversation: inConversation) : query
        return (text as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        ).width
    }

    /// Everything inside the text capsule that isn't text.
    static var fieldChrome: CGFloat {
        var chrome = horizontalPadding * 2 + leadingIconWidth + leadingIconSpacing + caretAllowance
        if BuildFlavor.isDev { chrome += devBadgeWidth + 8 }
        return chrome
    }

    /// The classic pill: one capsule with the badge and the chip inside it.
    static func classicWidth(for query: String, inConversation: Bool) -> CGFloat {
        var width = textWidth(query, inConversation: inConversation) + fieldChrome
        width += providerChipWidth + 10
        if !query.isEmpty { width += returnBadgeSize + 10 }
        return min(max(width, minWidth), maxWidth)
    }

    /// The bubbles beside the glass capsule, and the gaps before them.
    static func glassBubblesWidth(hasQuery: Bool) -> CGFloat {
        var bubbles = bubbleSpacing + glassChipWidth
        if hasQuery { bubbles += bubbleSpacing + bubbleSize }
        return bubbles
    }

    /// The glass pill's text capsule alone — the bubbles sit beside it. At
    /// rest the whole row is `minWidth`, like the classic pill, and at most the
    /// row is `maxWidth`, which is what the window is sized for.
    static func glassCapsuleWidth(for query: String, inConversation: Bool) -> CGFloat {
        let atRest = minWidth - glassBubblesWidth(hasQuery: false)
        let widest = maxWidth - glassBubblesWidth(hasQuery: !query.isEmpty)
        return min(max(textWidth(query, inConversation: inConversation) + fieldChrome, atRest), widest)
    }
}
