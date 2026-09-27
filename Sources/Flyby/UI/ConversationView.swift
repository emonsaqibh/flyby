import SwiftUI
import AppKit
import FlybyCore

/// The conversation: each question and its answer, oldest at the top, in
/// one comfortably narrow reading column. The live turn — the one still
/// answering, or the last one — carries the sources, the suggested next
/// questions and the error card; earlier turns keep their answer and sources.
struct ConversationView: View {
    @ObservedObject var controller: SearchController
    /// Height of the header floating over the top of the panel. Content starts
    /// below it and scrolls up underneath it.
    var topInset: CGFloat = 0
    /// Dissolve content as it scrolls under the header. For the glass look,
    /// where the header has no bar of its own to hide it behind.
    var fadesUnderHeader = false

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    ForEach(controller.earlierTurns) { turn in
                        EarlierTurnView(turn: turn)
                    }

                    liveTurn
                        .id(controller.liveTurnID)
                }
                // A line of 14pt text wider than this is hard to track back
                // across; on a wide panel the column centres instead of sprawling.
                .frame(maxWidth: AnswerMetrics.readingWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, topInset + 6)
                .padding(.bottom, 26)
            }
            .softTopScrollEdge()
            // Each new question scrolls to the top of the view, so its answer
            // has the whole panel to arrive in.
            .onChange(of: controller.liveTurnID) {
                guard !controller.earlierTurns.isEmpty else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    reader.scrollTo(controller.liveTurnID, anchor: .top)
                }
            }
            .onAppear {
                if !controller.earlierTurns.isEmpty {
                    reader.scrollTo(controller.liveTurnID, anchor: .top)
                }
            }
        }
        .mask {
            if fadesUnderHeader {
                headerFade
            } else {
                Rectangle()
            }
        }
    }

    private var liveTurn: some View {
        VStack(alignment: .leading, spacing: 24) {
            // The first question is already the panel's title.
            if !controller.earlierTurns.isEmpty {
                QuestionBubble(text: controller.submittedQuery)
            }

            if let message = failureMessage {
                AnswerErrorCard(
                    message: message,
                    onRetry: { controller.retry() },
                    onOpenInBrowser: { controller.submitToBrowser() }
                )
            }

            if !controller.answer.isEmpty {
                AnswerBlocksView(
                    blocks: controller.answer.blocks,
                    isStreaming: controller.phase == .streaming
                )
            } else if controller.isBusy {
                AnswerSkeleton()
                    .transition(.opacity)
            } else if controller.phase == .complete {
                Text("Nothing came back for this one. Try rewording it, or open it in your browser.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if !controller.answer.sources.isEmpty {
                SourcesSection(sources: controller.answer.sources)
                    .transition(.opacity)
            }

            // Only once the answer has settled: a suggestion that changes
            // under the pointer mid-stream is a misclick waiting to happen.
            if !controller.answer.followUps.isEmpty, !controller.isBusy {
                FollowUpsSection(followUps: controller.answer.followUps) { controller.ask($0) }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: controller.answer.isEmpty)
        .animation(.easeOut(duration: 0.25), value: controller.answer.sources.count)
        .animation(.easeOut(duration: 0.25), value: controller.isBusy)
    }

    private var failureMessage: String? {
        if case .failed(let message) = controller.phase { return message }
        return nil
    }

    /// Transparent under the header's title and buttons, opaque just below
    /// it — so text scrolling up dissolves instead of colliding with them.
    private var headerFade: some View {
        VStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.55),
                    .init(color: .black, location: 1),
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: topInset + 4)
            Rectangle()
        }
    }
}

/// A finished turn: the question, and the answer as it stood.
private struct EarlierTurnView: View {
    let turn: ConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            QuestionBubble(text: turn.query)

            if !turn.answer.isEmpty {
                AnswerBlocksView(blocks: turn.answer.blocks)
            } else if let failure = turn.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if !turn.answer.sources.isEmpty {
                SourcesSection(sources: turn.answer.sources)
            }
        }
    }
}

/// What you asked, on the right in a tinted bubble — the shape every chat
/// uses for "you".
struct QuestionBubble: View {
    let text: String
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(settings.accent.color.opacity(0.16))
                )
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You asked: \(text)")
    }
}

enum AnswerMetrics {
    static let readingWidth: CGFloat = 700
}

// MARK: - Waiting

/// Placeholder lines while nothing has arrived, with a slow sheen passing
/// over them — so the panel reads as "answer loading" rather than "empty".
/// The sheen stops under Reduce Motion; the lines stay.
struct AnswerSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    /// Line lengths as fractions of the column; 0 is a paragraph break.
    private static let lines: [CGFloat] = [0.94, 0.99, 0.87, 0.58, 0, 0.97, 0.91, 0.72]
    private static let lineHeight: CGFloat = 11
    private static let lineSpacing: CGFloat = 10
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
                .foregroundStyle(Color.primary.opacity(0.07))
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
                    .font(.system(size: 14, weight: .semibold))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            Text(message)
                .font(.system(size: 13))
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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(source.title.isEmpty ? source.displaySite : source.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(10)
            .frame(width: 200, height: 78, alignment: .topLeading)
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

/// The provider's suggested next questions. Clicking one asks it, with the
/// same provider, and puts it in the pill so it can be edited and re-asked.
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
            .font(.system(size: 12.5))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
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
