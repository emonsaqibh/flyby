import SwiftUI

/// Everything Flyby draws: the bar, and the answer card it becomes.
///
/// Opening, the bar springs out of a small blob. Asking something turns the
/// bar into the card — the same piece of glass growing up and out, the way the
/// Dynamic Island expands — while the question travels up into its bubble and
/// the input settles into a field along the card's bottom edge. With nothing
/// left to show, the card folds back down into the bar. Closing Flyby is
/// simpler: everything shrinks and fades down together, as it stands.
struct FlybyRootView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var stage: PanelStage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        OverlayStage(controller: controller, stage: stage)
            .padding(.bottom, StageMetrics.shadowMargin)
            .modifier(ClosingEffect(progress: stage.isClosing ? 1 : 0, reduceMotion: reduceMotion))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // The window is darkAqua already; this makes sure everything
            // SwiftUI resolves on its own agrees.
            .environment(\.colorScheme, .dark)
    }
}

/// Closing: the whole stage shrinks toward the bar and drops, and fades a
/// little behind the shrink rather than with it, so the motion is seen before
/// it's gone. One animated value drives all three, so there's one animation
/// to finish, not three to keep in step. Reduce Motion keeps only the fade.
private struct ClosingEffect: ViewModifier, Animatable {
    var progress: CGFloat
    let reduceMotion: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let motion = reduceMotion ? 0 : progress
        content
            .scaleEffect(1 - (1 - PanelStage.closedScale) * motion, anchor: .bottom)
            .offset(y: PanelStage.closedDrop * motion)
            .opacity(reduceMotion ? 1 - progress : 1 - progress * progress)
    }
}

/// The surface's shape at one moment: the blob Flyby opens out of, the bar,
/// or the card. Measured from the card's bottom-leading corner, which is
/// where the bar's bottom edge is too.
private struct SurfaceGeometry {
    enum Form { case blob, bar, card }

    let form: Form
    let barHeight: CGFloat
    let cardSize: CGSize

    var size: CGSize {
        switch form {
        case .blob: return CGSize(width: InputStyle.bar.minHeight, height: InputStyle.bar.minHeight)
        case .bar:  return CGSize(width: InputMetrics.width, height: barHeight)
        case .card: return cardSize
        }
    }

    /// The bar lines up with the card's inset controls; the blob sits on the
    /// bar's centre, so opening grows it evenly both ways.
    var leading: CGFloat {
        switch form {
        case .blob: return CardMetrics.edgeInset + (InputMetrics.width - InputStyle.bar.minHeight) / 2
        case .bar:  return CardMetrics.edgeInset
        case .card: return 0
        }
    }

    var outline: RoundedRectangle {
        let radius: CGFloat
        switch form {
        case .blob: radius = InputStyle.bar.minHeight / 2
        case .bar:  radius = InputStyle.bar.cornerRadius
        case .card: radius = CardMetrics.cornerRadius
        }
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

extension View {
    /// Changes the card makes on its own — an answer arriving, the history
    /// opening, New Chat — morph the bar into the card or back; opening Flyby
    /// brings its own animation, which is left alone, and resetting it out of
    /// sight asks for none.
    fileprivate func morphSpring(isOpen: Bool) -> some View {
        transaction(value: isOpen) { transaction in
            if transaction.animation == nil, !transaction.disablesAnimations {
                transaction.animation = Motion.morph
            }
        }
    }
}

/// The stage in layers, back to front:
///
/// 1. The surface: one smoked-glass shape that's the bar, or the card. The
///    card's content is always laid out at the card's size and only revealed
///    by the shape growing around it, so an animation frame costs a clip,
///    not a relayout of the answer (or of Google's page).
/// 2. The input — the one text field, with the provider chip at its end — in
///    the bar or along the bottom of the card. One field for both, so focus
///    is never handed over mid-morph. Glass in a container of its own: in the
///    surface's container it would merge into the card it sits on, and
///    vanish.
/// 3. The slash-command list and the keyboard shortcuts, when asked for,
///    just above the input.
///
/// And under all of it, a row of its own: the Recent Chats and Shortcuts
/// pills, which stay put while the bar becomes the card above them.
private struct OverlayStage: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var stage: PanelStage
    @Namespace private var glass
    /// The typed question and the bubble it becomes share an identity here.
    @Namespace private var questions
    /// How many lines the input's text takes, which is how tall the bar is.
    @State private var inputLines = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum GlassElement: Hashable, Sendable {
        case surface
    }

    var body: some View {
        VStack(spacing: StageMetrics.pillGap) {
            ZStack(alignment: .bottom) {
                GlassEffectContainer {
                    ZStack(alignment: .bottomLeading) {
                        if reduceMotion { barForCrossfade }
                        surface
                    }
                    .frame(width: CardMetrics.width, height: stage.cardSize.height, alignment: .bottomLeading)
                }

                GlassEffectContainer {
                    input
                        .frame(width: CardMetrics.width, height: stage.cardSize.height, alignment: .bottomLeading)
                }

                if !controller.commands.isEmpty {
                    CommandList(controller: controller)
                        .padding(.leading, CardMetrics.edgeInset)
                        .padding(.bottom, inputGeometry.bottom + inputGeometry.size.height + 8)
                        .frame(width: CardMetrics.width, alignment: .leading)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .bottomLeading)))
                }

                if controller.showsShortcuts {
                    ShortcutsOverlay { controller.showsShortcuts = false }
                        .padding(.bottom, inputGeometry.bottom + inputGeometry.size.height + 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }
            }

            pills
        }
        .morphSpring(isOpen: isOpen)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: controller.showsShortcuts)
        .animation(.spring(response: 0.26, dampingFraction: 0.9), value: controller.commands.isEmpty)
        // Put away folded, so the next opening starts from one line.
        .onChange(of: stage.isExpanded) { _, expanded in
            if !expanded { inputLines = 1 }
        }
    }

    /// The card is out: there's a conversation, or the history list.
    private var isOpen: Bool { stage.isExpanded && controller.showsPanel }

    private var inputStyle: InputStyle { isOpen ? .field : .bar }

    private var geometry: SurfaceGeometry {
        let form: SurfaceGeometry.Form
        if reduceMotion {
            // Doesn't morph: the card is always the card, and cross-fades
            // with a bar of its own.
            form = .card
        } else if !stage.isExpanded {
            form = .blob
        } else {
            form = isOpen ? .card : .bar
        }
        return SurfaceGeometry(
            form: form,
            barHeight: InputStyle.bar.height(lines: inputLines),
            cardSize: stage.cardSize
        )
    }

    private var surfaceOpacity: Double {
        if reduceMotion { return isOpen ? 1 : 0 }
        return stage.isExpanded ? 1 : 0
    }

    // MARK: Surface

    private var surface: some View {
        let geometry = self.geometry
        let showsContent = isOpen && stage.isPresented
        return AnswerCard(controller: controller, questions: questions)
            .frame(width: CardMetrics.width, height: stage.cardSize.height)
            // Opaque the moment the card starts to open — the question is
            // already on its way up, and has to be seen leaving the input —
            // and faded quickly as it folds or closes, before the glass
            // around it is gone.
            .animation(showsContent ? nil : Motion.reveal) { $0.opacity(showsContent ? 1 : 0) }
            .allowsHitTesting(isOpen)
            // Pinned to the card's own corner, whatever the shape around it
            // is doing: only the clip moves.
            .offset(x: -geometry.leading)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
            .clipShape(geometry.outline)
            // Interactive glass reacts to the pointer — right for the bar you
            // type in, a distraction on a card you're reading.
            .surface(geometry.outline, style: .smoke, interactive: !isOpen)
            .glassEffectID(GlassElement.surface, in: glass)
            .scaleEffect(stage.isExpanded || reduceMotion ? 1 : 0.55)
            .opacity(surfaceOpacity)
            .padding(.leading, geometry.leading)
    }

    /// Under Reduce Motion the bar doesn't turn into the card: this bar fades
    /// out as the card fades in over it.
    private var barForCrossfade: some View {
        let outline = RoundedRectangle(cornerRadius: InputStyle.bar.cornerRadius, style: .continuous)
        return Color.clear
            .frame(width: InputMetrics.width, height: InputStyle.bar.height(lines: inputLines))
            .surface(outline, style: .smoke, interactive: true)
            .opacity(stage.isExpanded && !isOpen ? 1 : 0)
            .padding(.leading, CardMetrics.edgeInset)
    }

    // MARK: Pills

    /// Recent Chats and Shortcuts, under the bar. Their own row, not part of
    /// the bar's glass, so the bar can become the card above them without
    /// moving them. They follow the text's rule: out a beat after the glass,
    /// gone before it.
    private var pills: some View {
        let shows = stage.isPresented
        return StagePills(controller: controller)
            .frame(height: StageMetrics.pillHeight)
            .animation(shows ? Motion.contentIn : Motion.contentOut) { content in
                content
                    .opacity(shows ? 1 : 0)
                    .scaleEffect(shows || reduceMotion ? 1 : 0.92, anchor: .top)
            }
            .allowsHitTesting(shows)
    }

    // MARK: Input

    /// Where the input's glass is. Folded up and in the bar it's exactly the
    /// surface's shape — the blob, then the bar — so the text and the chip
    /// are clipped to precisely what the glass has grown to, and can't show
    /// ahead of it. In the card it's a capsule of its own along the bottom,
    /// lifted to the card's inset.
    private var inputGeometry: InputGeometry {
        if isOpen {
            let style = InputStyle.field
            return InputGeometry(
                size: CGSize(width: InputMetrics.width, height: style.height(lines: inputLines)),
                leading: CardMetrics.edgeInset,
                bottom: CardMetrics.edgeInset,
                outline: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            )
        }
        let bar = SurfaceGeometry(
            form: stage.isExpanded || reduceMotion ? .bar : .blob,
            barHeight: InputStyle.bar.height(lines: inputLines),
            cardSize: stage.cardSize
        )
        return InputGeometry(size: bar.size, leading: bar.leading, bottom: 0, outline: bar.outline)
    }

    /// In the bar the input *is* the bar's content, flush with its bottom
    /// edge and with no glass of its own; in the card it's a glass field,
    /// with an accent rim while it has the keyboard.
    private var input: some View {
        let style = inputStyle
        let geometry = inputGeometry
        let showsText = stage.isPresented
        return QueryField(
            controller: controller,
            style: style,
            isInCard: isOpen,
            isFocused: stage.isInputFocused,
            questions: questions,
            lines: $inputLines
        )
        .frame(width: InputMetrics.width, height: style.height(lines: inputLines), alignment: .topLeading)
        .overlay(alignment: .bottomTrailing) {
            ProviderChip(controller: controller)
                .padding(.trailing, style.chipTrailing)
                .padding(.bottom, style.chipBottom)
        }
        // Comes out once the glass is there to hold it, and goes before the
        // glass does.
        .animation(showsText ? Motion.contentIn : Motion.contentOut) { $0.opacity(showsText ? 1 : 0) }
        // Pinned in place while the blob grows around it: only the clip moves.
        .offset(x: CardMetrics.edgeInset - geometry.leading)
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottomLeading)
        .clipShape(geometry.outline)
        .surface(geometry.outline, interactive: true, isVisible: isOpen)
        .overlay {
            geometry.outline
                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                .opacity(isOpen && stage.isInputFocused ? 1 : 0)
                .animation(.easeOut(duration: 0.18), value: stage.isInputFocused)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            // The dev and release builds run side by side; this says which
            // one is answering. Half off the input's top edge, on a dark
            // backing of its own so it reads over anything.
            if BuildFlavor.isDev {
                DevBadge()
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .offset(x: -24, y: -7)
                    .animation(showsText ? Motion.contentIn : Motion.contentOut) { $0.opacity(showsText ? 1 : 0) }
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(stage.isExpanded || reduceMotion ? 1 : 0.55)
        .padding(.leading, geometry.leading)
        .padding(.bottom, geometry.bottom)
    }
}

/// The input's glass at one moment. See `OverlayStage.inputGeometry`.
private struct InputGeometry {
    let size: CGSize
    let leading: CGFloat
    let bottom: CGFloat
    let outline: RoundedRectangle
}
