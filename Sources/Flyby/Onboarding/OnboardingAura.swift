import SwiftUI

/// The glow behind the walkthrough: the app icon's sky — deep indigo, azure,
/// a breath of violet, sky — as soft light pooling low in a near-black
/// window and drifting on a cycle of tens of seconds. Always dark, like the
/// overlay it introduces.
///
/// Each step parks the light somewhere a little different, so moving through
/// the walkthrough feels like moving through a space; a success blooms it.
///
/// The drift redraws about a dozen times a second: at this speed that's a
/// fraction of a point per frame, and anything faster is CPU spent on
/// nothing. A celebration's swell is quicker, so it gets 30 while it lasts.
/// Reduce Motion holds it all still.
struct OnboardingAura: View, Animatable {
    /// Where the light sits. Each step has its own value, and in-between
    /// values interpolate, which is how a step change glides the glow across.
    var phase: Double
    /// Extra light held while something is being celebrated, 0…1.
    var glow: Double
    /// When the last celebration fired: a quick swell of light that fades over
    /// a couple of seconds, computed from the clock rather than animated, so
    /// it rides the drift's own frames.
    var burstDate: Date?

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, glow) }
        set {
            phase = newValue.first
            glow = newValue.second
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How much smaller than the window the mesh is drawn. It's all soft
    /// gradient — nothing in it is sharper than a tenth of the window — so a
    /// small bitmap scaled up looks identical, and costs a sixteenth to draw
    /// every frame.
    private static let downsample: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: frameInterval, paused: reduceMotion)) { context in
                let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let bloom = glow + (reduceMotion ? 0 : burst(at: context.date))
                AuraField(time: time, phase: phase, bloom: bloom).mesh
            }
            .frame(width: proxy.size.width / Self.downsample, height: proxy.size.height / Self.downsample)
            .drawingGroup()
            .scaleEffect(Self.downsample, anchor: .topLeading)
        }
        .background(Color(AuraPalette.base))
        .accessibilityHidden(true)
    }

    private var frameInterval: TimeInterval {
        guard let burstDate, Date.now.timeIntervalSince(burstDate) < Self.burstLength else { return 1 / 8 }
        return 1 / 30
    }

    private static let burstLength: TimeInterval = 3

    /// A fast swell and a slow settle.
    private func burst(at date: Date) -> Double {
        guard let burstDate else { return 0 }
        let t = date.timeIntervalSince(burstDate)
        guard t > 0, t < Self.burstLength else { return 0 }
        let rise = min(1, t / 0.35)
        let fall = t < 0.5 ? 1 : max(0, 1 - (t - 0.5) / 2.5)
        return 0.7 * rise * (2 - rise) * fall * fall
    }
}

// MARK: - Palette

/// Colours from the release icon's gradient (Resources/IconGenerator), plus a
/// violet between azure and indigo for depth. Decoration only: nothing a
/// control depends on is drawn in these.
enum AuraPalette {
    static let sky = rgb(0x6B, 0xB8, 0xFF)
    static let azure = rgb(0x38, 0x6B, 0xF2)
    static let indigo = rgb(0x21, 0x26, 0x9E)
    static let violet = rgb(0x6C, 0x4F, 0xE8)

    /// Near-black with a little blue in it, so the glow has somewhere dark to
    /// come up out of.
    static let base = rgb(0x07, 0x09, 0x1C)
    /// A faint wash along the top, so the upper half isn't flat.
    static let wash = rgb(0x10, 0x14, 0x3A)

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color.Resolved {
        Color.Resolved(red: Float(r) / 255, green: Float(g) / 255, blue: Float(b) / 255)
    }
}

// MARK: - Field

/// One frame of the aura: a 5×5 mesh whose inner points sway, coloured by
/// sampling soft round glows at each point. Glows, not hand-placed vertex
/// colours, so moving the light is moving a centre, and any phase looks
/// deliberate.
private struct AuraField {
    let time: Double
    let phase: Double
    let bloom: Double

    private static let size = 5

    private struct Glow {
        let x: Double
        let y: Double
        let radius: Double
        let color: Color.Resolved
        let strength: Float
    }

    var mesh: MeshGradient {
        var points: [SIMD2<Float>] = []
        var colors: [Color.Resolved] = []
        let glows = self.glows
        let last = Self.size - 1
        for row in 0...last {
            for column in 0...last {
                var x = Double(column) / Double(last)
                var y = Double(row) / Double(last)
                // Edges stay on the edges, or the window's corners show
                // through; the inside sways.
                let seed = Double(row * 7 + column * 13)
                if column != 0, column != last {
                    x += 0.045 * sin(time * 0.13 + seed)
                }
                if row != 0, row != last {
                    y += 0.04 * cos(time * 0.11 + seed * 1.7)
                }
                points.append(SIMD2(Float(x), Float(y)))
                colors.append(color(atX: x, y: y, glows: glows))
            }
        }
        return MeshGradient(
            width: Self.size,
            height: Self.size,
            points: points,
            resolvedColors: colors,
            smoothsColors: true
        )
    }

    /// The light sources for this moment. Each step's `phase` moves where
    /// they rest; `time` walks them slowly around that.
    private var glows: [Glow] {
        let b = bloom
        let swell = 1 + 0.35 * b
        let lift = Float(1 + 0.6 * b)
        return [
            Glow(
                x: 0.5 + 0.22 * sin(phase * 1.1) + 0.08 * sin(time * 0.05),
                y: 1.02 - 0.05 * b,
                radius: 0.58 * swell,
                color: AuraPalette.indigo,
                strength: min(1, 0.85 * lift)
            ),
            Glow(
                x: 0.22 + 0.3 * (0.5 + 0.5 * sin(phase * 0.8 + 0.6)) + 0.1 * sin(time * 0.07 + 1),
                y: 0.9 + 0.06 * cos(time * 0.06),
                radius: 0.4 * swell,
                color: AuraPalette.azure,
                strength: min(1, 0.62 * lift)
            ),
            Glow(
                x: 0.82 - 0.3 * (0.5 + 0.5 * sin(phase * 0.9 + 2.1)) + 0.1 * cos(time * 0.06 + 2),
                y: 0.78 + 0.08 * sin(time * 0.05 + 1),
                radius: 0.34 * swell,
                color: AuraPalette.violet,
                strength: min(1, 0.45 * lift)
            ),
            // Only there while celebrating: the icon's brightest blue,
            // welling up from the bottom centre.
            Glow(
                x: 0.5,
                y: 1.05,
                radius: 0.5 * swell,
                color: AuraPalette.sky,
                strength: Float(min(1, 0.6 * b))
            ),
            Glow(
                x: 0.15 + 0.7 * (0.5 + 0.5 * sin(phase * 0.6 + time * 0.03)),
                y: 0.0,
                radius: 0.45,
                color: AuraPalette.wash,
                strength: 0.9
            ),
        ]
    }

    /// The base, with each glow laid over it by how close this point is to
    /// the glow's centre. Distances are stretched horizontally to the
    /// window's landscape shape, so glows read round rather than tall.
    private func color(atX x: Double, y: Double, glows: [Glow]) -> Color.Resolved {
        var color = AuraPalette.base
        for glow in glows {
            let dx = (x - glow.x) * 1.4
            let dy = y - glow.y
            let falloff = exp(-(dx * dx + dy * dy) / (glow.radius * glow.radius))
            color = mix(color, glow.color, Float(falloff) * glow.strength)
        }
        return color
    }

    private func mix(_ a: Color.Resolved, _ b: Color.Resolved, _ t: Float) -> Color.Resolved {
        let t = min(max(t, 0), 1)
        return Color.Resolved(
            red: a.red + (b.red - a.red) * t,
            green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t,
            opacity: 1
        )
    }
}
