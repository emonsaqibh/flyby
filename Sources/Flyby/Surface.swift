import SwiftUI
import AppKit

/// Which of Flyby's two glasses a shape is drawn in.
enum SurfaceStyle {
    /// The bar and the card: Siri's smoked glass. Near-black at the top,
    /// clearing toward the bottom so what's behind shows through, with a lit
    /// rim — and dark whatever it's over, which glass left to itself isn't.
    case smoke
    /// Controls on the smoke — the round buttons, the card's input field, the
    /// banner. Plain glass, which over the dark card reads a shade lighter,
    /// the way a control should.
    case control
}

/// Liquid Glass, or opaque dark fills in the same shapes under Reduce
/// Transparency — which asks for exactly that, where glass would only frost.
/// Before macOS 26, which has no Liquid Glass, the desktop behind is blurred
/// instead, under the same smoke and rim.
///
/// Glass draws its own edge highlight, shadow and shaping, and follows the
/// user's clear-to-tinted slider in System Settings without us doing
/// anything; the smoke is a gradient inside it, not a replacement for it.
///
/// Both styles are the same views with different amounts of smoke, so a
/// shape can change style — the provider button is smoked beside the bar
/// and a control on the card — as an animation rather than a rebuild.
struct Surface<S: InsettableShape>: ViewModifier {
    let shape: S
    var style: SurfaceStyle = .control
    /// Glass reacts to the pointer. Worth it on things you click, distracting
    /// on a card you're reading.
    var interactive = false
    /// Off draws nothing — for the card's input field while it's still the
    /// bar, which has the bar's own glass behind it. A parameter rather than
    /// a branch, so flipping it animates the glass in and out rather than
    /// rebuilding what's underneath.
    var isVisible = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(fallbackFill).opacity(isVisible ? 1 : 0)
                }
                .overlay {
                    shape.strokeBorder(fallbackRim, lineWidth: 1)
                        .opacity(isVisible ? 1 : 0)
                        .allowsHitTesting(false)
                }
        } else if #available(macOS 26.0, *) {
            smokeAndRim(content)
                .glassEffect(glass, in: shape)
        } else {
            smokeAndRim(content)
                .background {
                    // The smoke tint is glass's, keeping everything dark over
                    // a white window; controls read a shade lighter.
                    BehindWindowBlur()
                        .overlay { Palette.smokeTint }
                        .overlay { Color.white.opacity(style == .control ? 0.08 : 0) }
                        .clipShape(shape)
                        .opacity(isVisible ? 1 : 0)
                }
        }
    }

    private func smokeAndRim(_ content: Content) -> some View {
        content
            .background {
                shape.fill(Palette.smoke).opacity(smoke)
            }
            .overlay {
                shape.strokeBorder(Palette.rim, lineWidth: contrast == .increased ? 1.5 : 0.75)
                    .opacity(smoke)
                    .allowsHitTesting(false)
            }
    }

    private var smoke: Double { style == .smoke && isVisible ? 1 : 0 }

    @available(macOS 26.0, *)
    private var glass: Glass {
        guard isVisible else { return .identity }
        let glass: Glass = style == .smoke ? .regular.tint(Palette.smokeTint) : .regular
        return glass.interactive(interactive)
    }

    private var fallbackFill: Color {
        style == .smoke ? Color(white: 0.09) : Color(white: 0.2)
    }

    /// A white hairline reads as a lit edge on the dark fill; Increase
    /// Contrast wants a real boundary.
    private var fallbackRim: Color {
        Color.white.opacity(contrast == .increased ? 0.45 : 0.14)
    }
}

/// The overlay's colours. It's always dark, so these are too.
enum Palette {
    /// Laid inside the glass, not over what's behind it: dark at the top
    /// where the question and the corner buttons are, thinning toward the
    /// bottom edge.
    static let smoke = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.66), location: 0),
            .init(color: .black.opacity(0.46), location: 0.55),
            .init(color: .black.opacity(0.24), location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Keeps the glass dark over a white wallpaper, where glass on its own
    /// would lighten to match.
    static let smokeTint = Color.black.opacity(0.3)
    /// Brighter along the bottom, where Siri's bar catches the light.
    static let rim = LinearGradient(
        colors: [.white.opacity(0.1), .white.opacity(0.24)],
        startPoint: .top,
        endPoint: .bottom
    )
    /// The placeholder and the inline hint.
    static let hint = Color.white.opacity(0.42)
    /// Behind your question, in the conversation.
    static let bubble = Color.white.opacity(0.13)
}

extension View {
    func surface<S: InsettableShape>(
        _ shape: S,
        style: SurfaceStyle = .control,
        interactive: Bool = false,
        isVisible: Bool = true
    ) -> some View {
        modifier(Surface(shape: shape, style: style, interactive: interactive, isVisible: isVisible))
    }

    /// Glass buttons. Prominent is for the one action a view is asking for.
    /// Bordered ones before macOS 26.
    @ViewBuilder
    func flybyGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Keeps a glass shape's identity across a change of form. Nothing to
    /// keep before macOS 26, where the shape isn't glass.
    @ViewBuilder
    func flybyGlassEffectID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Card content scrolls the card's full height, under the corner buttons
    /// and the input, and dissolves as it goes. Clear bars the height of
    /// those controls tell the scroll view where it's covered, so the soft
    /// edge effect lands exactly there, and a fade makes sure nothing is still
    /// legible behind them.
    ///
    /// `reachesInput` false leaves the bottom edge alone: nothing is down
    /// there yet, and a question flying up out of the input has to be seen
    /// from its first frame, not emerge from a fade.
    ///
    /// Before macOS 26 there's no edge effect, only insets and the fade.
    @ViewBuilder
    func cardScrollEdges(reachesInput: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self
                .safeAreaBar(edge: .top, spacing: 0) {
                    Color.clear.frame(height: CardMetrics.headerInset)
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: CardMetrics.footerInset)
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
                .scrollEdgeEffectHidden(!reachesInput, for: .bottom)
                .mask { CardEdgeFade(fadesBottom: reachesInput) }
        } else {
            self
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: CardMetrics.headerInset)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: CardMetrics.footerInset)
                }
                .mask { CardEdgeFade(fadesBottom: reachesInput) }
        }
    }
}

/// The desktop behind Flyby's panel, blurred: what stands in for Liquid
/// Glass before macOS 26. AppKit's rather than a SwiftUI material, which in
/// a clear, non-activating panel doesn't reliably blur what's behind the
/// window or stay lit while another app is frontmost.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Opaque down the middle of the card, clear under the corner buttons and
/// — once there's content down there — the input.
private struct CardEdgeFade: View {
    let fadesBottom: Bool

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [.init(color: .clear, location: 0.4), .init(color: .black, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: CardMetrics.headerInset)
            Rectangle()
            ZStack {
                LinearGradient(
                    stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.6)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Rectangle().opacity(fadesBottom ? 0 : 1)
            }
            .frame(height: CardMetrics.footerInset)
        }
        .animation(.easeOut(duration: 0.25), value: fadesBottom)
    }
}

/// A round glass button the size of the card's other controls — the ✕ and
/// expand buttons in its corners. Drawn rather than `.buttonStyle(.glass)`,
/// whose size follows the label: these have to be exactly as big as the
/// provider button, and concentric with the card's corners.
struct GlassCircleButton: View {
    let systemImage: String
    let label: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: CardMetrics.controlSize, height: CardMetrics.controlSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .surface(Circle(), interactive: true)
        .help(help)
        .accessibilityLabel(label)
    }
}

/// A glass capsule the height of the card's other controls, with its icon
/// and its shortcut side by side — "⌘↩" written on the button, not hidden in
/// a tooltip, so the key is learned by looking.
struct GlassKeyButton: View {
    let systemImage: String
    let shortcut: String
    let label: String
    /// Showing what it opens: the icon takes the accent.
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
                Text(shortcut)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: CardMetrics.controlSize)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .surface(Capsule(), interactive: true)
        .help("\(label) (\(shortcut))")
        .accessibilityLabel(label)
        .accessibilityHint("Shortcut: \(shortcut)")
    }
}

/// Glass elements that sit near each other should be rendered together, so
/// they can share one sampling pass and blend or morph into each other as
/// they appear — which is what makes a row of buttons read as one control.
/// `spacing` is how close shapes have to be to merge, not layout. Before
/// macOS 26 there's no glass to group, and the content stands as it is.
struct GlassGroup<Content: View>: View {
    private let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

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
