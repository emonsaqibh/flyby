import SwiftUI

/// Everything Flyby draws: the pill, and the panel that grows up out of it.
///
/// Opening, the pill springs out of a small blob to its full width. When
/// there's something to show, the panel grows out of the pill's capsule to
/// full size; closing, it folds back down into the capsule and the pill
/// shrinks away — the way the Dynamic Island expands and contracts. With
/// glass, pill and panel are drawn in one glass container, so the panel
/// leaves and rejoins the capsule as liquid rather than as a second slab.
///
/// The panel's content is always laid out at its open size and only
/// revealed by the growing shape, so an animation frame costs a clip, not a
/// relayout of the answer (or of Google's page).
struct FlybyRootView: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var stage: PanelStage
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        stageView
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .themed()
            .onAppear { inputFocused = true }
            .onReceive(NotificationCenter.default.publisher(for: .quickSearchDidShow)) { _ in
                inputFocused = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .flybyShouldFocusInput)) { _ in
                inputFocused = true
            }
    }

    @ViewBuilder
    private var stageView: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassStage(controller: controller, stage: stage, focus: $inputFocused)
        } else {
            ClassicStage(controller: controller, stage: stage, focus: $inputFocused)
        }
    }
}

/// The panel's frame at one moment: open above the pill, or folded into its
/// capsule.
private struct PanelGeometry {
    let isOpen: Bool
    let openSize: CGSize
    let foldedWidth: CGFloat
    let foldedOffset: CGFloat

    var width: CGFloat { isOpen ? openSize.width : foldedWidth }
    var height: CGFloat { isOpen ? openSize.height : PillMetrics.height }
    /// Distance from the pill's bottom edge to the panel's.
    var bottom: CGFloat { isOpen ? PillMetrics.height + StageMetrics.gap : 0 }
    var xOffset: CGFloat { isOpen ? 0 : foldedOffset }
    var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: isOpen ? PanelMetrics.cornerRadius : PillMetrics.height / 2,
            style: .continuous
        )
    }
}

/// The panel's content at its open size, faded and eased in as the shape
/// around it opens.
private struct PanelBody: View {
    @ObservedObject var controller: SearchController
    let size: CGSize
    let isOpen: Bool

    var body: some View {
        ResultPanelView(controller: controller)
            .frame(width: size.width, height: size.height)
            .opacity(isOpen ? 1 : 0)
            .scaleEffect(isOpen ? 1 : 0.96, anchor: .bottom)
    }
}

extension View {
    /// Changes the panel makes on its own — an answer arriving, the history
    /// opening — spring it open; opening and closing Flyby bring their own
    /// animation, which is left alone.
    fileprivate func panelSpring(_ stage: PanelStage, isOpen: Bool) -> some View {
        transaction(value: isOpen) { transaction in
            if transaction.animation == nil { transaction.animation = stage.panelAnimation }
        }
    }
}

@available(macOS 26.0, *)
private struct GlassStage: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var stage: PanelStage
    var focus: FocusState<Bool>.Binding
    @Namespace private var glass

    var body: some View {
        // Spacing equal to the pill's: at rest the panel sits clear of the
        // pill, and only runs into it — merging like liquid — as it folds
        // down into the capsule or grows out of it.
        GlassEffectContainer(spacing: PillMetrics.bubbleSpacing) {
            ZStack(alignment: .bottom) {
                PanelBody(controller: controller, size: stage.panelSize, isOpen: isOpen)
                    .frame(width: geometry.width, height: geometry.height, alignment: .bottom)
                    .clipShape(geometry.shape)
                    .glassEffect(panelGlass, in: geometry.shape)
                    .glassEffectID(GlassPill.Element.panel, in: glass)
                    .offset(x: geometry.xOffset)
                    .padding(.bottom, geometry.bottom)
                    .allowsHitTesting(isOpen)

                GlassPill(controller: controller, focus: focus, glass: glass, isPresented: stage.isPresented)
                    .scaleEffect(stage.isPresented ? 1 : 0.55)
                    .opacity(stage.isPresented ? 1 : 0)
            }
            .padding(.bottom, PillMetrics.verticalMargin)
        }
        .panelSpring(stage, isOpen: isOpen)
    }

    private var isOpen: Bool { stage.isPresented && controller.showsPanel }

    private var geometry: PanelGeometry {
        PanelGeometry(
            isOpen: isOpen,
            openSize: stage.panelSize,
            foldedWidth: PillMetrics.glassCapsuleWidth(for: controller.query, inConversation: controller.isResultVisible),
            foldedOffset: GlassPill.capsuleOffset(hasQuery: !controller.query.isEmpty, isPresented: stage.isPresented)
        )
    }

    /// Folded, the panel is no glass at all — it's inside the capsule. Over
    /// Google's page (opaque anyway) it's none either; `.regular`, not
    /// interactive, because this is something you read.
    private var panelGlass: Glass {
        isOpen && !controller.showsWebPage ? .regular : .identity
    }
}

/// The same choreography in the classic material. Without glass there's
/// nothing to merge, so the panel fades as it folds.
private struct ClassicStage: View {
    @ObservedObject var controller: SearchController
    @ObservedObject var stage: PanelStage
    var focus: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .bottom) {
            PanelBody(controller: controller, size: stage.panelSize, isOpen: isOpen)
                .frame(width: geometry.width, height: geometry.height, alignment: .bottom)
                .surface(geometry.shape, isVisible: !controller.showsWebPage)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)
                .opacity(isOpen ? 1 : 0)
                .padding(.bottom, geometry.bottom)
                .allowsHitTesting(isOpen)

            ClassicPill(controller: controller, focus: focus, isPresented: stage.isPresented)
                .scaleEffect(stage.isPresented ? 1 : 0.55)
                .opacity(stage.isPresented ? 1 : 0)
        }
        .padding(.bottom, PillMetrics.verticalMargin)
        .panelSpring(stage, isOpen: isOpen)
    }

    private var isOpen: Bool { stage.isPresented && controller.showsPanel }

    private var geometry: PanelGeometry {
        PanelGeometry(
            isOpen: isOpen,
            openSize: stage.panelSize,
            foldedWidth: PillMetrics.classicWidth(for: controller.query, inConversation: controller.isResultVisible),
            foldedOffset: 0
        )
    }
}
