import SwiftUI

// The walkthrough's motion vocabulary. A step leaves quickly — blurring,
// fading and receding — and the next one arrives in order: the headline a
// glyph at a time, then the line under it, then what the step is about, then
// its controls. Everything is keyed to a view's own appearance, so there's no
// shared "transitioning" flag to get stuck: hammer Continue and each page
// simply arrives, or leaves, on its own.

// MARK: - Timing

/// When each part of a step arrives, after the step itself does. The first
/// beat leaves the outgoing page a moment to clear, so two sets of text never
/// read over each other.
enum RevealOrder {
    case hero, headline, subtitle, content, controls, footnote

    var delay: TimeInterval {
        switch self {
        case .hero:     return 0.06
        case .headline: return 0.10
        case .subtitle: return 0.30
        case .content:  return 0.42
        case .controls: return 0.54
        case .footnote: return 0.66
        }
    }
}

/// Which way the walkthrough is moving, so arriving content drifts in from
/// the side the user is heading toward — and from the other side on Back.
enum OnboardingDirection {
    case forward, backward

    /// Where arriving content starts, horizontally.
    var drift: CGFloat { self == .forward ? 22 : -22 }
}

extension EnvironmentValues {
    @Entry var onboardingDirection: OnboardingDirection = .forward
}

// MARK: - Glyph reveal

/// Draws a `Text` one glyph at a time: each rises a few points, tilts upright,
/// un-blurs and fades in a beat after the one before it.
///
/// A `TextRenderer` rather than a view per character, so the text keeps its
/// own shaping, kerning and line breaks, and stays one `Text` to VoiceOver.
/// Only `elapsed` animates, linearly from zero; each glyph runs its own slice
/// of that time through a spring, which is where the stagger and the little
/// overshoot come from.
struct GlyphRevealRenderer: TextRenderer {
    var elapsed: TimeInterval
    var timing: GlyphTiming = .headline

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    /// Glyphs still below the baseline, or still blurred, draw outside the
    /// text's frame; without this they'd be clipped to it.
    var displayPadding: EdgeInsets {
        let spill = timing.blur * 2
        return EdgeInsets(top: spill, leading: spill, bottom: timing.rise + spill, trailing: spill)
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        // Settled: draw the lines whole, exactly as plain text would.
        if elapsed >= timing.total(glyphs: layout.glyphCount) {
            for line in layout { ctx.draw(line) }
            return
        }

        var index = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    let start = Double(index) * timing.stagger
                    index += 1
                    let t = (elapsed - start) / timing.duration
                    if t <= 0 { continue }
                    if t >= 1 {
                        ctx.draw(glyph)
                        continue
                    }
                    draw(glyph, at: t, in: ctx)
                }
            }
        }
    }

    /// One glyph, `t` of the way (0…1) through its own entrance.
    private func draw(_ glyph: Text.Layout.RunSlice, at t: Double, in ctx: GraphicsContext) {
        let settle = timing.spring.value(target: 1.0, time: t * timing.duration)
        let rest = 1 - settle
        // Opacity and focus arrive sooner than position, so a glyph is
        // readable while it's still finishing its bounce.
        let fade = min(1, t / 0.45)
        let focus = max(0, 1 - t / 0.6)

        let bounds = glyph.typographicBounds.rect
        var copy = ctx
        copy.opacity = fade * (2 - fade)
        if focus > 0.01 {
            copy.addFilter(.blur(radius: timing.blur * focus * focus))
        }
        copy.translateBy(x: bounds.midX, y: bounds.maxY + rest * timing.rise)
        copy.rotate(by: .degrees(rest * timing.tilt))
        copy.translateBy(x: -bounds.midX, y: -bounds.maxY)
        copy.draw(glyph)
    }
}

/// How a line of text reveals itself.
struct GlyphTiming {
    /// Between one glyph starting and the next.
    var stagger: TimeInterval
    /// How long each glyph takes to settle.
    var duration: TimeInterval
    /// Points each glyph rises through.
    var rise: CGFloat
    /// Degrees each glyph tilts upright through, pivoting on its baseline.
    var tilt: Double
    var blur: CGFloat
    var spring: Spring

    /// Big and deliberate, for a step's headline.
    static let headline = GlyphTiming(
        stagger: 0.022, duration: 0.7, rise: 12, tilt: 7, blur: 7,
        spring: Spring(duration: 0.62, bounce: 0.3)
    )
    /// Quick and small, for an answer arriving the way a streamed one does.
    static let stream = GlyphTiming(
        stagger: 0.009, duration: 0.45, rise: 5, tilt: 0, blur: 4,
        spring: Spring(duration: 0.4, bounce: 0.15)
    )

    func total(glyphs: Int) -> TimeInterval {
        Double(max(glyphs - 1, 0)) * stagger + duration
    }
}

private extension Text.Layout {
    var glyphCount: Int {
        reduce(0) { lines, line in lines + line.reduce(0) { $0 + $1.count } }
    }
}

/// A headline that writes itself in when it appears. Styled from outside,
/// like any `Text`: `.font`, `.foregroundStyle` and alignment pass through.
///
/// A new string plays again: it's a new view, so it starts from nothing
/// rather than inheriting the old one's finished state.
struct RevealText: View {
    private let text: String
    private let delay: TimeInterval
    private let timing: GlyphTiming

    init(_ text: String, delay: TimeInterval = RevealOrder.headline.delay, timing: GlyphTiming = .headline) {
        self.text = text
        self.delay = delay
        self.timing = timing
    }

    var body: some View {
        RevealTextLine(text: text, delay: delay, timing: timing)
            .id(text)
    }
}

private struct RevealTextLine: View {
    let text: String
    let delay: TimeInterval
    let timing: GlyphTiming

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var elapsed: TimeInterval = 0
    /// Reduce Motion's crossfade, in place of the glyphs.
    @State private var faded = false

    /// Characters stand in for glyphs: close enough to time the animation,
    /// and the renderer draws everything whole once it's past the end anyway.
    private var total: TimeInterval { timing.total(glyphs: text.count) }

    var body: some View {
        Text(text)
            .textRenderer(GlyphRevealRenderer(elapsed: reduceMotion ? total : elapsed, timing: timing))
            .opacity(reduceMotion && !faded ? 0 : 1)
            .onAppear {
                if reduceMotion {
                    withAnimation(.easeOut(duration: 0.25).delay(delay / 2)) { faded = true }
                } else {
                    withAnimation(.linear(duration: total).delay(delay)) { elapsed = total }
                }
            }
    }
}

// MARK: - Staggered arrival

/// Holds a view back until its turn, then brings it in: fading, un-blurring,
/// and drifting from the direction of travel into place.
///
/// Blur is optional because a Liquid Glass shape inside a blur filter loses
/// its lensing for the moment it's blurred, and on the bigger glass panels
/// that reads as a flicker rather than a focus pull.
private struct Reveal: ViewModifier {
    let delay: TimeInterval
    let blurs: Bool

    @Environment(\.onboardingDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let moving = !shown && !reduceMotion
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: moving && blurs ? 10 : 0)
            .scaleEffect(moving ? 0.97 : 1)
            .offset(x: moving ? direction.drift : 0, y: moving ? 14 : 0)
            .onAppear {
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.25).delay(delay / 2)
                    : .spring(duration: 0.75, bounce: 0.2).delay(delay)
                withAnimation(animation) { shown = true }
            }
    }
}

extension View {
    /// Arrives at `order`'s beat after its step does.
    func reveal(_ order: RevealOrder, blurs: Bool = true) -> some View {
        modifier(Reveal(delay: order.delay, blurs: blurs))
    }

    /// Arrives `delay` seconds after its step does.
    func reveal(after delay: TimeInterval, blurs: Bool = true) -> some View {
        modifier(Reveal(delay: delay, blurs: blurs))
    }
}

// MARK: - Leaving

/// How a step leaves: faster than the next arrives, blurring and receding as
/// it fades, the same whichever way the user is going — so a change of
/// direction never has to re-dress the outgoing page first.
struct StepExitTransition: Transition {
    var reduceMotion = false

    func body(content: Content, phase: TransitionPhase) -> some View {
        let gone = !phase.isIdentity
        content
            .opacity(gone ? 0 : 1)
            .blur(radius: gone && !reduceMotion ? 12 : 0)
            .scaleEffect(gone && !reduceMotion ? 0.95 : 1)
    }
}

/// A small blur-and-fade, for pieces that swap in place — a subtitle whose
/// wording changes, a setup row that follows the chosen provider.
struct SoftSwapTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 6)
            .scaleEffect(phase.isIdentity ? 1 : 0.98)
    }
}
