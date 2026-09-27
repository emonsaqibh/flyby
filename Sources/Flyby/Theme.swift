import SwiftUI
import AppKit

/// Light, dark, or whatever the system is doing.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// `nil` means "inherit", which is how AppKit spells "follow the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// What the mode actually resolves to right now. The web view needs a
    /// concrete answer because `prefers-color-scheme` has no "system" value.
    var isDark: Bool {
        switch self {
        case .light: return false
        case .dark:  return true
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }
}

/// Tint used for the accent details — the ↩ badge, the caret, links, source
/// chips, and every control in Settings.
///
/// A theme is stored as a *hue*, not a colour. The actual colour is derived per
/// appearance by solving for the brightness that hits a target luminance, so
/// every accent lands at roughly the same contrast against the surface it's
/// drawn on: dark and saturated on a light background, light and soft on a dark
/// one. Fixed colours can't do this — a mid-tone blue that reads well on dark
/// is washed out on light, and equal-brightness hues have wildly different
/// luminance (yellow is far lighter than blue at the same HSB brightness).
enum AccentTheme: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, green, graphite

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:   return "System"
        case .blue:     return "Blue"
        case .purple:   return "Purple"
        case .pink:     return "Pink"
        case .red:      return "Red"
        case .orange:   return "Orange"
        case .green:    return "Green"
        case .graphite: return "Graphite"
        }
    }

    /// Hue in 0…1. `nil` means greyscale; `.system` resolves at draw time from
    /// whatever accent the user picked in System Settings.
    private var hue: CGFloat? {
        switch self {
        case .blue:     return 0.58
        case .purple:   return 0.75
        case .pink:     return 0.90
        case .red:      return 0.99
        case .orange:   return 0.08
        case .green:    return 0.36
        case .graphite: return nil
        case .system:   return nil  // handled separately
        }
    }

    /// Resolves live against the current appearance, so switching Light/Dark —
    /// or the system doing it for you at sunset — re-derives without any
    /// observation code on our side.
    var nsColor: NSColor {
        NSColor(name: NSColor.Name("accent-\(rawValue)")) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

            let resolvedHue: CGFloat?
            if case .system = self {
                resolvedHue = AccentTheme.systemAccentHue
            } else {
                resolvedHue = self.hue
            }

            return AccentTheme.solve(
                hue: resolvedHue,
                maxSaturation: isDark ? Tuning.darkSaturation : Tuning.lightSaturation,
                targetLuminance: isDark ? Tuning.darkLuminance : Tuning.lightLuminance
            )
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// The settings swatch draws the same resolved colour the UI will use.
    var swatch: Color { color }

    // MARK: - Derivation

    private enum Tuning {
        /// Measured at 4.15:1 against the light pill surface, for every hue.
        static let lightLuminance: CGFloat = 0.15
        /// Measured at 4.00:1 against the dark pill surface, for every hue.
        static let darkLuminance: CGFloat = 0.55

        /// Saturation ceilings. Vivid on light, softer on dark — a fully
        /// saturated colour on a dark surface reads as glare.
        static let lightSaturation: CGFloat = 0.88
        static let darkSaturation: CGFloat = 0.62
    }

    /// The system accent as a hue, or nil when the user picked Graphite.
    private static var systemAccentHue: CGFloat? {
        guard let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return 0.58 }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        accent.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return s < 0.1 ? nil : h
    }

    /// Finds the colour of this hue that hits `targetLuminance`, using whichever
    /// axis can actually get there.
    ///
    /// Dimming alone isn't enough: a saturated blue or purple can't reach the
    /// light-on-dark target even at full brightness, because saturated blue is
    /// intrinsically dark. When that happens, desaturate toward white instead.
    /// Solving on only one axis is what left purple at 2.17:1 while green sat
    /// at 4.00:1.
    private static func solve(hue: CGFloat?, maxSaturation: CGFloat, targetLuminance: CGFloat) -> NSColor {
        guard let hue else {
            return searchBrightness(hue: 0, saturation: 0, target: targetLuminance)
        }
        let vivid = NSColor(hue: hue, saturation: maxSaturation, brightness: 1, alpha: 1)
        return relativeLuminance(vivid) >= targetLuminance
            ? searchBrightness(hue: hue, saturation: maxSaturation, target: targetLuminance)
            : searchSaturation(hue: hue, maxSaturation: maxSaturation, target: targetLuminance)
    }

    /// Luminance rises monotonically with brightness at fixed saturation.
    private static func searchBrightness(hue: CGFloat, saturation: CGFloat, target: CGFloat) -> NSColor {
        var low: CGFloat = 0
        var high: CGFloat = 1
        var result = NSColor(hue: hue, saturation: saturation, brightness: 0.5, alpha: 1)

        for _ in 0..<16 {
            let mid = (low + high) / 2
            result = NSColor(hue: hue, saturation: saturation, brightness: mid, alpha: 1)
            if relativeLuminance(result) < target { low = mid } else { high = mid }
        }
        return result
    }

    /// At full brightness, luminance *falls* as saturation rises — so the
    /// comparison flips.
    private static func searchSaturation(hue: CGFloat, maxSaturation: CGFloat, target: CGFloat) -> NSColor {
        var low: CGFloat = 0
        var high = maxSaturation
        var result = NSColor(hue: hue, saturation: maxSaturation, brightness: 1, alpha: 1)

        for _ in 0..<16 {
            let mid = (low + high) / 2
            result = NSColor(hue: hue, saturation: mid, brightness: 1, alpha: 1)
            if relativeLuminance(result) > target { low = mid } else { high = mid }
        }
        return result
    }

    /// WCAG relative luminance, which is what "contrast" actually means —
    /// unlike HSB brightness, it accounts for the eye being far more sensitive
    /// to green than to blue.
    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        guard let srgb = color.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }
}

/// Applies the chosen tint. Appearance itself is set app-wide on `NSApp`, so it
/// doesn't need a modifier.
private struct Themed: ViewModifier {
    @ObservedObject private var settings = AppSettings.shared

    func body(content: Content) -> some View {
        content.tint(settings.accent.color)
    }
}

extension View {
    func themed() -> some View { modifier(Themed()) }
}
