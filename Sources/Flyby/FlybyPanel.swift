import AppKit
import SwiftUI

/// The one window Flyby draws in: the bar at the bottom of the screen and the
/// answer card it grows into.
///
/// Both live in one fixed, oversized, fully transparent window, so the bar can
/// become the card and fold back into it as one piece of glass — the Dynamic
/// Island's trick. Two windows can only be animated by resizing them, which is
/// a full relayout every frame and never quite in step; inside one window it's
/// a SwiftUI spring on a shape. Clicks on the transparent parts fall through
/// to whatever is underneath.
///
/// Always dark, like Siri, whatever the system is doing: the window is
/// darkAqua, which is also what Google's page inside it inherits. Settings and
/// onboarding follow the system like any other window.
final class FlybyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    let stage: PanelStage

    init(controller: SearchController, stage: PanelStage) {
        self.stage = stage
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: StageMetrics.windowWidth, height: CardMetrics.maxHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
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

    // MARK: - The input's keyboard focus

    /// The field editor, while the input has the keyboard.
    var inputEditor: NSTextView? {
        guard let editor = firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor
    }

    /// Puts the keyboard in the input now, with the caret at the end — not
    /// on SwiftUI's next pass, which would drop whatever is typed in the
    /// meantime, and not with everything selected, which the next keystroke
    /// would replace. The only text field in this window is the input.
    ///
    /// The very first time Flyby opens, the field may not have been built
    /// yet — the hosting view lays out when it's first shown — so lay out
    /// now, and failing that, try once more on the next pass.
    func focusInput(retrying: Bool = true) {
        guard inputEditor == nil else { return }
        contentView?.layoutSubtreeIfNeeded()
        guard let field = Self.textField(in: contentView) else {
            if retrying {
                DispatchQueue.main.async { [weak self] in self?.focusInput(retrying: false) }
            }
            return
        }
        _ = makeFirstResponder(field)
        if let editor = inputEditor {
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
    }

    /// Takes the keyboard out of the input, so the keys read the answer.
    func leaveInput() {
        guard inputEditor != nil else { return }
        _ = makeFirstResponder(nil)
    }

    /// Every change of keyboard focus comes through here — the input taking
    /// it, a click in an answer or on Google's page, Tab and Esc — which makes
    /// it the one place to tell the stage, so the input can show whether it
    /// has the keyboard.
    ///
    /// And macOS's inline predictions draw their suggestion right after the
    /// caret, exactly where the input's own "— Ask Google" hint goes: off,
    /// each time the input takes the field editor.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        inputEditor?.inlinePredictionType = .no
        // Can arrive in the middle of a SwiftUI update; publish after it,
        // whatever focus has settled on by then.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let focused = self.inputEditor != nil
            if self.stage.isInputFocused != focused { self.stage.isInputFocused = focused }
        }
        return made
    }

    private static func textField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }

    /// The screen the mouse is on, which is the one the user is looking at.
    static var activeScreen: NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
    }

    /// Covers the column the stage can occupy — from the pills under the bar
    /// to as tall as the card gets on this screen — plus room all round for
    /// the glass's shadow. The lower margin dips behind the Dock, which draws
    /// above it; trimming it to fit would cut the pills' shadow off.
    func position(on screen: NSScreen) {
        let visible = screen.visibleFrame
        let margin = StageMetrics.shadowMargin
        let stageBottom = visible.minY + StageMetrics.bottomInset
        let cardBottom = stageBottom + StageMetrics.pillsHeight
        let room = visible.maxY - StageMetrics.topInset - cardBottom
        let cardHeight = max(min(CardMetrics.maxHeight, room), CardMetrics.minHeight)

        stage.cardSize = CGSize(width: CardMetrics.width, height: cardHeight)
        setFrame(
            NSRect(
                x: visible.midX - StageMetrics.windowWidth / 2,
                y: stageBottom - margin,
                width: StageMetrics.windowWidth,
                height: StageMetrics.pillsHeight + cardHeight + margin * 2
            ),
            display: true
        )
    }
}

/// Whether Flyby is on screen, and how big the card is on this screen.
/// The window itself only appears before the first frame and goes after the
/// last; everything in between is an animation of `phase`.
///
/// Opening and closing are deliberately different motions. Opening springs
/// the bar out of a blob, and the card out of the bar. Closing doesn't play
/// that backwards — folding a tall card into the bar while the bar shrinks to
/// a dot is a lot of shape-changing for "go away" — the whole thing shrinks
/// and fades down as it stands, the way a window leaves.
@MainActor
final class PanelStage: ObservableObject {
    enum Phase {
        /// Folded into the blob the bar opens out of; the window is gone or
        /// about to show.
        case hidden
        case presented
        /// Laid out as it was when presented, shrinking and fading down.
        case closing
    }

    @Published private(set) var phase: Phase = .hidden
    /// Fixed for as long as Flyby is open on a screen, so an answer streaming
    /// in never resizes the card — it scrolls instead.
    @Published var cardSize = CGSize(width: CardMetrics.width, height: CardMetrics.maxHeight)
    /// The input has the keyboard. Set by the window, which sees every change
    /// of focus.
    @Published var isInputFocused = false

    /// Open and staying open. False as soon as a close begins, so the
    /// shortcut pressed mid-close opens Flyby again rather than closing it.
    var isPresented: Bool { phase == .presented }
    /// Laid out open — the bar at full size, the card out if it has something
    /// to show. Still true while closing: the close moves the layout as one
    /// piece rather than folding it up.
    var isExpanded: Bool { phase != .hidden }
    var isClosing: Bool { phase == .closing }

    /// How far the close gets: the size it shrinks to, and how far it drops.
    static let closedScale: CGFloat = 0.9
    static let closedDrop: CGFloat = 18

    private var closeGeneration = 0

    /// Snaps to hidden without animating, so opening always starts from the
    /// folded-up blob — even if the last close hadn't finished.
    func prepare() {
        snap(to: .hidden)
    }

    func present() {
        withAnimation(Motion.open) { phase = .presented }
    }

    /// `completion` runs once the close has played — the place to take the
    /// window down. Then the stage folds itself away, unless it was reopened
    /// or closed again in the meantime. Both happen without animation: by
    /// then there's nothing on screen to animate, and anything left running
    /// would still be playing when Flyby next opens.
    func dismiss(completion: @escaping () -> Void) {
        closeGeneration += 1
        let generation = closeGeneration
        // Closed before it ever opened: there's nothing to shrink, and
        // "closing" would lay the bar out at full size to fade it.
        guard phase != .hidden else {
            Self.withoutAnimation(completion)
            return
        }
        withAnimation(Motion.close, completionCriteria: .logicallyComplete) {
            phase = .closing
        } completion: { [weak self] in
            guard let self else { return }
            let isCurrent = self.phase == .closing && generation == self.closeGeneration
            Self.withoutAnimation {
                completion()
                if isCurrent { self.phase = .hidden }
            }
        }
    }

    private func snap(to phase: Phase) {
        Self.withoutAnimation { self.phase = phase }
    }

    private static func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

/// Every animation on the stage, in one place, so the pieces that move
/// together move on the same curve — the card growing, the question
/// travelling into its bubble, the input settling at the bottom.
///
/// Under Reduce Motion each is a short ease instead of a spring, and the
/// geometry that would travel cross-fades or snaps (see the stage).
@MainActor
enum Motion {
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// A springy pop, the way the Dynamic Island opens: fast out of the gate,
    /// a small overshoot, a soft settle.
    static var open: Animation {
        reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.44, dampingFraction: 0.74)
    }

    /// Quicker than opening and without a bounce — you're done with it.
    static var close: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .smooth(duration: 0.3)
    }

    /// The bar becoming the card and folding back into it, and a question
    /// travelling into its bubble.
    static var morph: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.48, dampingFraction: 0.82)
    }

    /// The input taking or giving up a line as you type: quick enough to keep
    /// up with typing, settled rather than bouncy — a bounce on every wrap
    /// would be seasickness. `nil` under Reduce Motion: it just changes.
    static var grow: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)
    }

    /// The card's content fading as the card folds back into the bar or
    /// closes: gone well before the glass around it is.
    static let reveal = Animation.easeOut(duration: 0.18)

    /// The input's text and chip coming out as Flyby opens: a beat behind
    /// the glass, so words never lead the shape that holds them — the glass
    /// can take a frame or two to first appear.
    static let contentIn = Animation.easeOut(duration: 0.22).delay(0.09)

    /// …and going as it closes, ahead of the glass.
    static let contentOut = Animation.easeOut(duration: 0.1)

    /// Words swapping in place — the placeholder for the hint, one
    /// provider's name for another.
    static let swap = Animation.easeInOut(duration: 0.2)

    /// The scroll keeping up with an answer as it streams.
    static var follow: Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
    }
}

/// Where the stage sits on the screen and in its window.
enum StageMetrics {
    /// Between the bottom of the usable screen and the bottom of the pills
    /// under the bar. The bar sits on them — the card too, growing up from
    /// where the bar was — which puts it 22pt higher than it stood before
    /// the pills: only the room they need.
    static let bottomInset: CGFloat = 16

    /// The Recent Chats and Shortcuts pills: quieter and smaller than the
    /// bar, a short step below it.
    static let pillHeight: CGFloat = 28
    static let pillGap: CGFloat = 10
    /// Everything between the stage's bottom and the bar's.
    static var pillsHeight: CGFloat { pillHeight + pillGap }
    /// Between the top of the tallest card and the top of the usable screen.
    static let topInset: CGFloat = 44
    /// Transparent room around the card for the glass's shadow. A Gaussian
    /// shadow keeps fading for about twice its radius; give it less than that
    /// and the window edge saws a straight line through the blur.
    static let shadowMargin: CGFloat = 40

    static var windowWidth: CGFloat { CardMetrics.width + shadowMargin * 2 }
}

/// The answer card, and the round controls in its corners.
enum CardMetrics {
    /// One width on every screen. Siri's card is a column you read, not a
    /// window you fill: at this width a 16pt line holds about 60 characters,
    /// which is what reads comfortably.
    static let width: CGFloat = 560
    /// Siri-tall where there's room, and whatever fits between the bar and the
    /// top of the screen where there isn't.
    static let maxHeight: CGFloat = 700
    static let minHeight: CGFloat = 320

    /// The corner buttons, and the height of a one-line input field — Siri's
    /// controls, scaled to the card.
    static let controlSize: CGFloat = 40
    /// From the card's edge to the controls in its corners and along its
    /// bottom.
    static let edgeInset: CGFloat = 14
    /// Concentric with the controls in the corners: inset + control radius.
    static var cornerRadius: CGFloat { edgeInset + controlSize / 2 }
    /// Things inset in the card — the page, the banner — keep its curve.
    static var innerRadius: CGFloat { cornerRadius - edgeInset }

    /// Content starts below the corner buttons…
    static var headerInset: CGFloat { edgeInset + controlSize + 8 }
    /// …and ends above the input row, scrolling under both and dissolving.
    static var footerInset: CGFloat { edgeInset + controlSize + 10 }
}

/// The input, which is the bar on its own and the field along the bottom of
/// the card: the card's width less its insets, in both, with the same
/// leading edge — so the field never moves sideways, and the provider chip
/// at its trailing end barely moves at all.
enum InputMetrics {
    static var width: CGFloat { CardMetrics.width - CardMetrics.edgeInset * 2 }
}

/// The provider dropdown at the input's trailing end: the provider's name and
/// a chevron in a small capsule — or, while an answer is coming, Stop.
enum ChipMetrics {
    static let height: CGFloat = 28
    static let fontSize: CGFloat = 13
    static let horizontalPadding: CGFloat = 10
    static let spacing: CGFloat = 5
    static let chevronWidth: CGFloat = 9
    static let stopGlyphWidth: CGFloat = 12
    /// Between the end of the text and the chip.
    static let gap: CGFloat = 10

    static var font: NSFont { .systemFont(ofSize: fontSize, weight: .medium) }

    static func textWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func providerWidth(_ provider: ProviderKind) -> CGFloat {
        horizontalPadding * 2 + textWidth(provider.shortLabel) + spacing + chevronWidth
    }

    static var stopWidth: CGFloat {
        horizontalPadding * 2 + stopGlyphWidth + spacing + textWidth("Stop") + spacing + textWidth("⌘.")
    }

    /// The room the text leaves for the chip: whichever of the provider chip
    /// and the stop chip is wider, so the text doesn't rewrap when an answer
    /// starts or stops.
    static func column(for provider: ProviderKind) -> CGFloat {
        max(providerWidth(provider), stopWidth)
    }
}

/// How the input is typeset in each of its two places.
struct InputStyle: Equatable {
    let fontSize: CGFloat
    /// What a vertical-axis `TextField` and a `Text` both lay one line of
    /// this font out at — measured, because it isn't the font's nominal line
    /// height at every size, and the hint only lands after the last
    /// character if the two agree.
    let lineHeight: CGFloat
    let horizontalPadding: CGFloat
    /// One line's height. Also what sets the vertical padding, so a single
    /// line sits centred.
    let minHeight: CGFloat
    let cornerRadius: CGFloat
    /// Past this it stops growing and scrolls.
    let maxLines: Int
    /// From the input's trailing edge to the chip.
    let chipTrailing: CGFloat

    var verticalPadding: CGFloat { (minHeight - lineHeight) / 2 }
    /// The chip is centred on the last line, and stays there — anchored to
    /// the bottom as the input grows upward.
    var chipBottom: CGFloat { (minHeight - ChipMetrics.height) / 2 }

    /// The text column: the input less its leading padding, and less the
    /// chip and the room around it.
    func textWidth(chipColumn: CGFloat) -> CGFloat {
        InputMetrics.width - horizontalPadding - ChipMetrics.gap - chipColumn - chipTrailing
    }

    func height(lines: Int) -> CGFloat {
        minHeight + CGFloat(min(max(lines, 1), maxLines) - 1) * lineHeight
    }

    /// Large type in a big rounded rectangle, Siri's bar at Flyby's scale,
    /// with room around one line to breathe.
    static let bar = InputStyle(
        fontSize: 22,
        lineHeight: 26,
        horizontalPadding: 22,
        minHeight: 68,
        cornerRadius: 26,
        maxLines: 6,
        chipTrailing: 16
    )

    /// A capsule the size of the card's corner buttons, the chip concentric
    /// inside its end.
    static let field = InputStyle(
        fontSize: 15,
        lineHeight: 19,
        horizontalPadding: 16,
        minHeight: CardMetrics.controlSize,
        cornerRadius: CardMetrics.controlSize / 2,
        maxLines: 5,
        chipTrailing: (CardMetrics.controlSize - ChipMetrics.height) / 2
    )
}
