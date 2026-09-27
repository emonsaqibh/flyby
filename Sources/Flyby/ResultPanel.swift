import AppKit
import SwiftUI

/// The results surface: a tall panel centred above the pill.
///
/// It's anchored to the top of the capsule and grows upward, so the whole thing
/// reads as one object unfolding out of the pill rather than two unrelated
/// windows.
final class ResultPanel: NSPanel {
    /// Clickable and focusable — you need to be able to select text and scroll —
    /// but never made key programmatically, so typing stays in the pill.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(controller: SearchController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 800),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: ResultPanelView(controller: controller))
        host.sizingOptions = []
        contentView = host
    }

    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: .quickSearchShouldDismiss, object: nil)
    }

    // MARK: - Geometry

    /// Gap between the top of the capsule and the bottom of the panel.
    static let gap: CGFloat = 14
    /// Gap between the top of the panel and the top of the usable screen.
    static let topInset: CGFloat = 44

    /// Wide enough to read comfortably, clamped so it doesn't sprawl on an
    /// ultrawide or overflow a laptop display.
    static func width(on screen: NSScreen) -> CGFloat {
        min(max(screen.visibleFrame.width * 0.52, 620), 960)
    }

    static func targetFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let w = width(on: screen)
        let bottom = visible.minY + PillMetrics.capsuleTop + gap
        let top = visible.maxY - topInset
        return NSRect(
            x: visible.midX - w / 2,
            y: bottom,
            width: w,
            height: max(top - bottom, 200)
        )
    }

    // MARK: - Presentation

    /// How far down the unfold starts: the panel begins as a squat slab on the
    /// pill and grows up to full height, so it reads as coming out of it.
    private static let unfoldStart: CGFloat = 0.55

    /// A critically damped spring, as a Bézier: most of the travel happens
    /// early and it settles softly, with no overshoot. Overshoot would briefly
    /// size the window past its target, and every frame of a window resize is
    /// a full SwiftUI (and, in AI Mode, WebKit) layout.
    private static var unfoldCurve: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.22, 1)
    }
    private static let unfoldDuration: TimeInterval = 0.38

    func present(on screen: NSScreen) {
        let target = Self.targetFrame(on: screen)
        guard !isVisible else {
            setFrame(target, display: true)
            return
        }

        // Reduce Motion gets a plain fade in place: movement is the thing
        // that setting is asking us to drop, and a fade still says "new".
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // Unfold upward out of the pill: same bottom edge, growing to height.
        var start = target
        if !reduceMotion { start.size.height = target.height * Self.unfoldStart }
        setFrame(start, display: false)
        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            if reduceMotion {
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            } else {
                context.duration = Self.unfoldDuration
                context.timingFunction = Self.unfoldCurve
                animator().setFrame(target, display: true)
            }
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        alphaValue = 1
    }
}
