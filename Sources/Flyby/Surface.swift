import SwiftUI
import AppKit

/// Liquid Glass is how Flyby looks — not an option. It's used wherever the
/// system has it; the classic blurred material is only for macOS 14–15 and
/// for Reduce Transparency, which asks for exactly what that material does
/// (it turns opaque by itself) where glass would only frost.
enum LiquidGlass {
    static var isSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// Whether glass is drawn right now.
    static func isActive(reduceTransparency: Bool) -> Bool {
        isSupported && !reduceTransparency
    }
}

/// The background treatment shared by the pill, the result panel and the
/// attention banner.
///
/// Liquid Glass where the OS has it, the classic `NSVisualEffectView`
/// material otherwise. Glass draws its own edge highlight,
/// shadow and shaping — and macOS 27 retunes all of that, plus the user's
/// clear-to-tinted slider, without us doing anything — so the manual clip and
/// hairline border only apply to the fallback. Layering them under glass
/// double-draws the rim.
///
/// Reduce Transparency takes the fallback too: the blurred material turns
/// opaque by itself under that setting, which is exactly what the user asked
/// for, whereas glass only frosts.
struct Surface<S: Shape>: ViewModifier {
    let shape: S
    /// Glass reacts to the pointer. Worth it on the pill, distracting on a
    /// panel you're reading.
    var interactive: Bool = false
    /// Off draws nothing behind the content, for when the content is opaque
    /// anyway (the web page). A parameter rather than a branch, so flipping it
    /// doesn't rebuild everything underneath — that would remount the page.
    var isVisible: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(glass, in: shape)
        } else {
            content
                .background(VisualEffectBackground().opacity(isVisible ? 1 : 0))
                .clipShape(shape)
                .overlay(shape.stroke(rim, lineWidth: 1))
        }
    }

    @available(macOS 26.0, *)
    private var glass: Glass {
        guard isVisible else { return .identity }
        return interactive ? .regular.interactive() : .regular
    }

    /// A white hairline reads as a lit edge on the dark material; Increase
    /// Contrast wants a real boundary in either appearance.
    private var rim: Color {
        contrast == .increased ? Color.primary.opacity(0.4) : Color.white.opacity(0.14)
    }
}

extension View {
    func surface<S: Shape>(_ shape: S, interactive: Bool = false, isVisible: Bool = true) -> some View {
        modifier(Surface(shape: shape, interactive: interactive, isVisible: isVisible))
    }

    /// Glass buttons where the system has them, the bordered pair elsewhere.
    /// Prominent is for the one action a view is asking for.
    func flybyGlassButton(prominent: Bool = false) -> some View {
        modifier(FlybyGlassButton(prominent: prominent))
    }

    /// Round glass icon buttons for control rows floating over content (the
    /// panel header). Without glass they fall back to borderless
    /// glyphs, since a row of bordered circles is heavier than the text it
    /// sits above.
    func flybyGlassIconButton() -> some View {
        modifier(FlybyGlassIconButton())
    }

    /// Content scrolling under a floating header should dissolve rather than
    /// collide with it. The system edge effect on macOS 26+; a no-op before.
    func softTopScrollEdge() -> some View {
        modifier(SoftTopScrollEdge())
    }
}

private struct FlybyGlassButton: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

private struct FlybyGlassIconButton: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SoftTopScrollEdge: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

/// Glass elements that sit near each other should be rendered together, so
/// they can share one sampling pass and blend or morph into each other as
/// they appear — which is what makes a row of buttons read as one control.
/// Transparent without glass.
struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

/// The pre-glass material. `.hudWindow` behind the window is what the pill has
/// always used; Settings borrows it with `.sidebar` for its source list.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
