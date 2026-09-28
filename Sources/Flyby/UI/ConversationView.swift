import SwiftUI
import AppKit
import FlybyCore

/// The conversation: each question in a bubble on the right, its answer as
/// plain text under it, oldest at the top. The live turn — the one still
/// answering, or the last one — carries the sources, the suggested next
/// questions and the error card; earlier turns keep their answer and sources.
///
/// It scrolls the card's full height and follows the answer down as it
/// streams, until you scroll up to read; scrolling back to the end picks
/// it up again.
struct ConversationView: View {
    @ObservedObject var controller: SearchController
    /// Where questions fly in from, shared with the input.
    let questions: Namespace.ID

    @State private var scroll = ScrollPosition(idType: UUID.self)
    @State private var followsAnswer = true
    /// The conversation is long enough to run under the input — until it is,
    /// the bottom edge doesn't fade (see `cardScrollEdges`).
    @State private var reachesInput = false
    /// Where the scroll is, for the keyboard to scroll from. Kept out of
    /// SwiftUI's sight: it changes every frame of a scroll, and nothing on
    /// screen depends on it.
    @State private var lastGeometry = GeometryBox()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(controller.earlierTurns) { turn in
                    // Appears exactly where the live turn it was a moment
                    // ago stood — a fade would flash it.
                    EarlierTurnView(turn: turn, questions: questions)
                        .transition(.identity)
                }

                liveTurn
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AnswerMetrics.sideInset)
            .padding(.top, 4)
            .padding(.bottom, 12)
            // A new question is a spring even when the card is already out,
            // so it can be seen travelling from the input to its bubble.
            .animation(Motion.morph, value: controller.liveTurnID)
        }
        .scrollPosition($scroll)
        .cardScrollEdges(reachesInput: reachesInput)
        .onScrollGeometryChange(for: Bool.self, of: Self.overflows) { _, overflows in
            reachesInput = overflows
        }
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in
            lastGeometry.value = geometry
        }
        .onReceive(NotificationCenter.default.publisher(for: .flybyShouldScrollAnswer)) { note in
            if let command = note.object as? AnswerScroll { keyboardScroll(command) }
        }
        .onScrollPhaseChange { oldPhase, newPhase, context in
            // Only the reader turns following off and on. Settling after a
            // scroll of our own doesn't count, or an answer that grew during
            // it would be left behind.
            if newPhase == .interacting {
                followsAnswer = false
            } else if newPhase == .idle, oldPhase == .interacting || oldPhase == .decelerating {
                followsAnswer = Self.isAtEnd(context.geometry)
            }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }) { oldHeight, newHeight in
            guard followsAnswer, newHeight > oldHeight else { return }
            withAnimation(Motion.follow) { scroll.scrollTo(edge: .bottom) }
        }
        .onChange(of: controller.liveTurnID) {
            showLiveTurn(animated: true)
        }
        .onAppear {
            showLiveTurn(animated: false)
        }
    }

    /// A new question lands at the end, just above the input, and the answer
    /// pushes it up as it arrives. A chat reopened from history opens on its
    /// last question instead, to be read from there.
    private func showLiveTurn(animated: Bool) {
        guard !controller.earlierTurns.isEmpty else {
            followsAnswer = true
            return
        }
        withAnimation(animated ? Motion.follow : nil) {
            if controller.isRestored {
                followsAnswer = false
                scroll.scrollTo(id: controller.liveTurnID, anchor: .top)
            } else {
                followsAnswer = true
                scroll.scrollTo(edge: .bottom)
            }
        }
    }

    /// The reading keys: a line is a couple of lines of text, a page is the
    /// visible part less a little overlap, so the eye has somewhere to land.
    /// Scrolling to the end turns following back on; anywhere else, off.
    private func keyboardScroll(_ command: AnswerScroll) {
        switch command {
        case .top:
            followsAnswer = false
            withAnimation(Motion.follow) { scroll.scrollTo(edge: .top) }
            return
        case .bottom:
            followsAnswer = true
            withAnimation(Motion.follow) { scroll.scrollTo(edge: .bottom) }
            return
        default:
            break
        }
        guard let geometry = lastGeometry.value else { return }
        let insets = geometry.contentInsets
        let visible = geometry.containerSize.height - insets.top - insets.bottom
        let page = max(visible - 48, 80)
        let step: CGFloat
        switch command {
        case .lineUp:   step = -48
        case .lineDown: step = 48
        case .pageUp:   step = -page
        default:        step = page
        }
        let top = -insets.top
        let bottom = max(top, geometry.contentSize.height + insets.bottom - geometry.containerSize.height)
        let target = min(max(geometry.contentOffset.y + step, top), bottom)
        followsAnswer = target >= bottom - 1
        withAnimation(Motion.follow) { scroll.scrollTo(y: target) }
    }

    private static func isAtEnd(_ geometry: ScrollGeometry) -> Bool {
        geometry.visibleRect.maxY >= geometry.contentSize.height - 40
    }

    private static func overflows(_ geometry: ScrollGeometry) -> Bool {
        let insets = geometry.contentInsets.top + geometry.contentInsets.bottom
        return geometry.contentSize.height + insets > geometry.containerSize.height + 1
    }

    private var liveTurn: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuestionRow {
                if !controller.submittedQuery.isEmpty {
                    QuestionBubble(text: controller.submittedQuery)
                        .matchedGeometryEffect(id: controller.liveTurnID, in: questions, properties: .position)
                        // A new question is a new bubble. The one it replaces
                        // is now an earlier turn's, standing in the same place.
                        .id(controller.liveTurnID)
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .opacity : .questionArrival(from: arrivalScale),
                            removal: .identity
                        ))
                }
            }

            if let message = failureMessage {
                AnswerErrorCard(
                    message: message,
                    onRetry: { controller.retry() },
                    onOpenInBrowser: { controller.submitToBrowser() }
                )
                .transition(.arrive)
            }

            if !controller.answer.isEmpty {
                AnswerBlocksView(
                    blocks: controller.answer.blocks,
                    isStreaming: controller.phase == .streaming
                )
                .transition(.arrive)
            } else if controller.isBusy {
                AnswerSkeleton()
                    .transition(.opacity)
            } else if controller.phase == .complete {
                Text("Nothing came back for this one. Try rewording it, or open it in your browser.")
                    .font(.system(size: AnswerMetrics.bodySize))
                    .foregroundStyle(.secondary)
            }

            if !controller.answer.sources.isEmpty {
                SourcesSection(sources: controller.answer.sources)
                    .transition(.arrive)
            }

            // Only once the answer has settled: a suggestion that changes
            // under the pointer mid-stream is a misclick waiting to happen.
            if !controller.answer.followUps.isEmpty, !controller.isBusy {
                FollowUpsSection(followUps: controller.answer.followUps) { controller.ask($0) }
                    .transition(.arrive)
            }
        }
        .animation(.easeOut(duration: 0.25), value: controller.answer.isEmpty)
        .animation(.easeOut(duration: 0.25), value: controller.answer.sources.count)
        .animation(.easeOut(duration: 0.25), value: controller.isBusy)
    }

    /// The first question comes from the bar, in the bar's large type; later
    /// ones from the card's field, in the bubble's own size.
    private var arrivalScale: CGFloat {
        let typed = controller.earlierTurns.isEmpty ? InputStyle.bar.fontSize : InputStyle.field.fontSize
        return typed / AnswerMetrics.questionSize
    }

    private var failureMessage: String? {
        if case .failed(let message) = controller.phase { return message }
        return nil
    }
}

/// Holds the latest scroll geometry without SwiftUI watching it.
private final class GeometryBox {
    var value: ScrollGeometry?
}

/// A keyboard scroll of the conversation, from the app delegate's key
/// monitor.
enum AnswerScroll {
    case lineUp, lineDown, pageUp, pageDown, top, bottom
}

extension Notification.Name {
    /// Carries an `AnswerScroll`.
    static let flybyShouldScrollAnswer = Notification.Name("flybyShouldScrollAnswer")
}

/// A finished turn: the question, and the answer as it stood.
private struct EarlierTurnView: View {
    let turn: ConversationTurn
    let questions: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuestionRow {
                QuestionBubble(text: turn.query)
                    .matchedGeometryEffect(id: turn.id, in: questions, properties: .position)
            }

            if !turn.answer.isEmpty {
                AnswerBlocksView(blocks: turn.answer.blocks)
            } else if let failure = turn.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if !turn.answer.sources.isEmpty {
                SourcesSection(sources: turn.answer.sources)
            }
        }
    }
}

/// Right-aligns a question, leaving room on its left so it reads as a reply
/// bubble rather than a banner. Always there, even empty, so a bubble
/// arriving in it is the view being inserted — and its own transition is
/// the one that plays.
private struct QuestionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: AnswerMetrics.bubbleLeadingRoom)
            content
        }
    }
}

/// What you asked, in a dark bubble with a tail — the shape every chat uses
/// for "you".
struct QuestionBubble: View {
    let text: String
    /// How far the bubble has filled in around the text; see
    /// `QuestionArrival`.
    @Environment(\.questionChrome) private var chrome

    var body: some View {
        Text(text)
            .font(.system(size: AnswerMetrics.questionSize))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(QuestionBubbleShape().fill(Palette.bubble).opacity(chrome))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You asked: \(text)")
    }
}

/// A rounded rectangle with a tail curling out of its bottom-trailing
/// corner.
struct QuestionBubbleShape: Shape {
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let bubble = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        var tail = Path()
        // From the bottom edge, out to a point just past the corner, and back
        // up into the trailing edge — well inside the rounded corner, so the
        // union has no seam.
        tail.move(to: CGPoint(x: rect.maxX - 16, y: rect.maxY))
        tail.addCurve(
            to: CGPoint(x: rect.maxX + 5, y: rect.maxY + 1),
            control1: CGPoint(x: rect.maxX - 6, y: rect.maxY),
            control2: CGPoint(x: rect.maxX + 1, y: rect.maxY + 1)
        )
        tail.addCurve(
            to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 14),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - 2),
            control2: CGPoint(x: rect.maxX - 1, y: rect.maxY - 8)
        )
        tail.closeSubpath()
        return bubble.union(tail)
    }
}

extension EnvironmentValues {
    /// 0 while a question is still in flight to its bubble, 1 once it's
    /// landed: the bubble behind the text fills in as it arrives.
    @Entry var questionChrome: Double = 1
}

/// A question arriving in the conversation. It starts where the input had
/// it (the shared identity puts it there) at the size it was typed in, and
/// settles to the bubble's size while the bubble fills in around it — so
/// what you see is your own text lifting out of the input.
private struct QuestionArrival: ViewModifier, Animatable {
    var progress: Double
    let typedScale: CGFloat

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .environment(\.questionChrome, progress)
            .scaleEffect(typedScale + (1 - typedScale) * progress)
    }
}

extension AnyTransition {
    fileprivate static func questionArrival(from typedScale: CGFloat) -> AnyTransition {
        .modifier(
            active: QuestionArrival(progress: 0, typedScale: typedScale),
            identity: QuestionArrival(progress: 1, typedScale: typedScale)
        )
    }

    /// Fades in; leaves at once. What leaves the live turn is either replaced
    /// by the same thing in an earlier turn or gone with the whole card, and
    /// fading it would show it twice, or late.
    fileprivate static var arrive: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }
}

enum AnswerMetrics {
    /// Siri's answer size. On a card this narrow a line holds about 60
    /// characters, which is what reads comfortably.
    static let bodySize: CGFloat = 16
    static let lineSpacing: CGFloat = 3
    /// The question in its bubble — a step below the answer, which is what
    /// you're here to read.
    static let questionSize: CGFloat = 15
    /// Between the card's edges and the text.
    static let sideInset: CGFloat = 24
    /// Room a question bubble always leaves on its left.
    static let bubbleLeadingRoom: CGFloat = 120
}

// MARK: - Waiting

/// Placeholder lines while nothing has arrived, with a slow sheen passing
/// over them — so the card reads as "answer loading" rather than "empty".
/// The sheen stops under Reduce Motion; the lines stay.
struct AnswerSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    /// Line lengths as fractions of the column; 0 is a paragraph break.
    private static let lines: [CGFloat] = [0.94, 0.99, 0.87, 0.58, 0, 0.97, 0.91, 0.72]
    private static let lineHeight: CGFloat = 12
    private static let lineSpacing: CGFloat = 11
    private static let breakHeight: CGFloat = 4

    private static var height: CGFloat {
        let bars = lines.filter { $0 > 0 }.count
        let breaks = lines.count - bars
        return CGFloat(bars) * lineHeight
            + CGFloat(breaks) * breakHeight
            + CGFloat(lines.count - 1) * lineSpacing
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            bars(width: width)
                .foregroundStyle(Color.primary.opacity(0.08))
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [.clear, Color.primary.opacity(0.10), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: width * 0.5)
                        .offset(x: -width * 0.5 + sweep * width * 1.5)
                        .frame(width: width, alignment: .leading)
                        .mask { bars(width: width) }
                    }
                }
        }
        .frame(height: Self.height)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                sweep = 1
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading answer")
    }

    private func bars(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.lineSpacing) {
            ForEach(Array(Self.lines.enumerated()), id: \.offset) { _, fraction in
                if fraction > 0 {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .frame(width: width * fraction, height: Self.lineHeight)
                } else {
                    Color.clear.frame(height: Self.breakHeight)
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Failure

/// What went wrong, in the provider's own words, and the two ways forward.
struct AnswerErrorCard: View {
    let message: String
    let onRetry: () -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("No answer this time")
                    .font(.system(size: 15, weight: .semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Try Again", action: onRetry)
                    .flybyGlassButton(prominent: true)
                Button("Open in Browser", action: onOpenInBrowser)
                    .flybyGlassButton()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Sources

/// Cards in a row that scrolls sideways — they're supporting material, so
/// they take one line of the column however many there are.
struct SourcesSection: View {
    let sources: [WebSource]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Sources", count: sources.count)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(sources) { SourceCard(source: $0) }
                }
                .padding(.bottom, 6)
            }
        }
    }
}

private struct SourceCard: View {
    let source: WebSource
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(source.url)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Favicon(host: source.url.host(percentEncoded: false))
                        .frame(width: 16, height: 16)
                    Text(source.displaySite)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(source.title.isEmpty ? source.displaySite : source.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .frame(width: 200, height: 80, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.10 : 0.05))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(source.url.absoluteString)
        .accessibilityLabel("\(source.title), \(source.displaySite)")
        .accessibilityHint("Opens in your browser")
    }
}

/// The site's icon via Google's favicon service — the answer came from Google
/// anyway, so this tells it nothing new — with a globe until it loads, or if
/// it doesn't.
private struct Favicon: View {
    let host: String?

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var url: URL? {
        guard let host, !host.isEmpty,
              let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=64")
    }

    private var placeholder: some View {
        Image(systemName: "globe")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Follow-ups

/// The provider's suggested next questions. Clicking one asks it, of the
/// provider that suggested it.
struct FollowUpsSection: View {
    let followUps: [String]
    let onAsk: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Ask next", count: nil)

            FlowLayout(spacing: 8) {
                ForEach(followUps, id: \.self) { question in
                    FollowUpChip(question: question) { onAsk(question) }
                }
            }
        }
    }
}

private struct FollowUpChip: View {
    let question: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text(question)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 13.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(Color.primary.opacity(hovering ? 0.11 : 0.06))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Ask this")
    }
}

private struct SectionLabel: View {
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
            if let count {
                Text("\(count)")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
