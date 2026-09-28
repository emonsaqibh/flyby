import SwiftUI

// The walkthrough's building blocks: its type, its glass, its progress.

// MARK: - Type

enum OnboardingType {
    /// Large, bold and a little tight, as Apple sets its own welcome screens.
    static let hero = Font.system(size: 38, weight: .bold)
    static let headline = Font.system(size: 30, weight: .bold)
    static let subtitle = Font.system(size: 15)
    static let heroTracking: CGFloat = -0.7
    static let headlineTracking: CGFloat = -0.5
}

/// A step's headline, writing itself in, and one line under it.
struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            RevealText(title)
                .font(OnboardingType.headline)
                .tracking(OnboardingType.headlineTracking)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            // Changes in place on some steps; the new wording swaps softly
            // instead of snapping.
            Text(subtitle)
                .font(OnboardingType.subtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .id(subtitle)
                .transition(SoftSwapTransition())
                .reveal(.subtitle)
        }
        .frame(maxWidth: 560)
    }
}

/// Small print under a step — reassurance, not instructions.
struct StepFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520)
    }
}

// MARK: - Glass

/// Liquid Glass in the given shape — or, under Reduce Transparency, an
/// opaque fill in the same shape with a hairline edge, which asks for exactly
/// that and stays legible over the aura.
private struct PaneGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(.background)
                    if let tint { shape.fill(tint) }
                }
                .overlay {
                    shape.strokeBorder(.separator, lineWidth: contrast == .increased ? 1.5 : 1)
                        .allowsHitTesting(false)
                }
        } else {
            content
                .overlay {
                    // Glass's own rim all but vanishes over a pale aura;
                    // Increase Contrast wants a real boundary.
                    if contrast == .increased {
                        shape.strokeBorder(.primary.opacity(0.35), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return glass.interactive(interactive)
    }
}

extension View {
    func paneGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(PaneGlass(shape: shape, tint: tint, interactive: interactive))
    }

    /// A rounded glass panel, the walkthrough's card.
    func glassCard(cornerRadius: CGFloat = 22, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .paneGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Progress

/// A capsule per step the user will actually see; the current one stretches
/// wide, the ones behind stay a little darker than the ones ahead. Springs
/// between steps, so progress feels like travel.
struct ProgressCapsules: View {
    let count: Int
    let current: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(fill(for: index))
                    .frame(width: index == current ? 22 : 7, height: 7)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.35), value: current)
        .animation(.smooth(duration: 0.3), value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("Step \(current + 1) of \(count)")
    }

    private func fill(for index: Int) -> AnyShapeStyle {
        if index == current { return AnyShapeStyle(Color.accentColor) }
        return AnyShapeStyle(.primary.opacity(index < current ? 0.32 : 0.14))
    }
}
