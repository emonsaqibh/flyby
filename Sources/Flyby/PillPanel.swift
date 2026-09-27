import AppKit
import SwiftUI

/// The pill: a small capsule at the bottom centre of the screen that grows as
/// you type.
///
/// The window itself is a fixed, oversized, fully transparent frame — only the
/// capsule inside it is drawn. Resizing an NSWindow on every keystroke animates
/// badly and lags a fast typist, whereas animating the capsule's width inside a
/// static window is a smooth spring. Clicks on the transparent margins fall
/// through to whatever is underneath.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(controller: SearchController) {
        super.init(
            contentRect: NSRect(
                x: 0, y: 0,
                width: PillMetrics.windowWidth,
                height: PillMetrics.windowHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        // The capsule casts its own shadow in SwiftUI; a window shadow would
        // trace the full transparent rectangle.
        hasShadow = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let host = NSHostingView(rootView: PillView(controller: controller))
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

    /// The capsule sits `bottomInset` above the visible area; the window itself
    /// is deliberately taller than that, so its lower margin dips behind the
    /// Dock. That margin is empty except for the shadow, and the Dock draws at a
    /// higher level, so nothing shows — whereas trimming it to fit would cut the
    /// shadow off again.
    func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        setFrame(
            NSRect(
                x: visible.midX - PillMetrics.windowWidth / 2,
                y: visible.minY + PillMetrics.bottomInset - PillMetrics.verticalMargin,
                width: PillMetrics.windowWidth,
                height: PillMetrics.windowHeight
            ),
            display: true
        )
    }
}

enum PillMetrics {
    /// The drawn capsule.
    static let height: CGFloat = 52
    static let minWidth: CGFloat = 340
    static let maxWidth: CGFloat = 860
    static let fontSize: CGFloat = 16
    static let horizontalPadding: CGFloat = 18
    static let placeholder = "Search anything…"

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

    /// Transparent breathing room around the capsule, for the shadow and for
    /// the capsule to grow into. Sized from the shadow so the two can't drift
    /// apart: the offset pushes the shadow down, so the vertical margin has to
    /// cover the radius *and* the offset.
    static var verticalMargin: CGFloat { shadowExtent + shadowOffsetY }
    static var horizontalMargin: CGFloat { shadowExtent }
    static var windowWidth: CGFloat { maxWidth + horizontalMargin * 2 }
    static var windowHeight: CGFloat { height + verticalMargin * 2 }

    /// Top of the capsule, measured from the bottom of the visible screen area.
    static var capsuleTop: CGFloat { bottomInset + height }

    // MARK: - Width

    /// Measured against the same font the text field renders in, so the
    /// capsule tracks the caret rather than guessing.
    static func textWidth(_ query: String) -> CGFloat {
        let text = query.isEmpty ? placeholder : query
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
    static func classicWidth(for query: String) -> CGFloat {
        var width = textWidth(query) + fieldChrome
        width += providerChipWidth + 10
        if !query.isEmpty { width += returnBadgeSize + 10 }
        return min(max(width, minWidth), maxWidth)
    }

    /// The glass pill's text capsule alone — the bubbles sit beside it. At
    /// rest the whole row is `minWidth`, like the classic pill, and at most the
    /// row is `maxWidth`, which is what the window is sized for.
    static func glassCapsuleWidth(for query: String) -> CGFloat {
        var bubbles = bubbleSpacing + glassChipWidth
        if !query.isEmpty { bubbles += bubbleSpacing + bubbleSize }
        let atRest = minWidth - (bubbleSpacing + glassChipWidth)
        return min(max(textWidth(query) + fieldChrome, atRest), maxWidth - bubbles)
    }
}
