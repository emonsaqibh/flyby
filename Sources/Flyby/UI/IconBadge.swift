import SwiftUI

/// A white symbol on a coloured, continuous-cornered square — how System
/// Settings marks its panes, and how Flyby marks its settings panes and its
/// answer providers, in Settings and in onboarding alike. One hue with a soft
/// top-to-bottom sheen, and a hairline highlight on the rim so it reads as an
/// object rather than a flat swatch.
///
/// Sizes that match the system: 20pt in a sidebar row, 28pt in a list row,
/// 48–64pt as a hero.
struct IconBadge: View {
    let symbol: String
    let fill: AnyShapeStyle
    var size: CGFloat = 20

    init(_ symbol: String, color: Color, size: CGFloat = 20) {
        self.symbol = symbol
        self.fill = AnyShapeStyle(color.gradient)
        self.size = size
    }

    init(_ symbol: String, gradient: LinearGradient, size: CGFloat = 20) {
        self.symbol = symbol
        self.fill = AnyShapeStyle(gradient)
        self.size = size
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        shape
            .fill(fill)
            .overlay {
                shape.strokeBorder(.white.opacity(0.22), lineWidth: max(0.5, size / 56))
                    .blendMode(.plusLighter)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.54, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.12), radius: size / 40, y: size / 80)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension ProviderKind {
    /// The provider as an `IconBadge`, the same everywhere it's offered.
    func badge(size: CGFloat) -> IconBadge {
        switch self {
        case .browser:
            return IconBadge(icon, color: .blue, size: size)
        case .aiMode:
            return IconBadge(icon, color: .indigo, size: size)
        case .gemini:
            return IconBadge(icon, color: .teal, size: size)
        case .appleIntelligence:
            // Apple Intelligence's own warm-to-cool sweep.
            return IconBadge(icon, gradient: LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.62, blue: 0.20),
                    Color(red: 0.96, green: 0.30, blue: 0.52),
                    Color(red: 0.62, green: 0.34, blue: 0.96),
                    Color(red: 0.24, green: 0.56, blue: 1.00),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ), size: size)
        }
    }
}
