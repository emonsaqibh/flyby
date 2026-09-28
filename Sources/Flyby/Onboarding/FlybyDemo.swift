import SwiftUI

/// A few seconds of Flyby on a loop, under the welcome headline: a question
/// types itself into the bar, and an answer card blooms up out of it. Shows
/// what the product *is* faster than a sentence could.
///
/// Drawn in the overlay's own smoked glass, so it looks like the real thing.
/// Under Reduce Motion it's one still frame of a finished answer.
struct FlybyDemo: View {
    private struct Exchange {
        let question: String
        let answer: String
    }

    private static let exchanges = [
        Exchange(
            question: "How far away is the Moon?",
            answer: "About 384,400 km on average — close enough that its light reaches you in 1.3 seconds."
        ),
        Exchange(
            question: "Convert 72 °F to Celsius",
            answer: "72 °F is about 22.2 °C — a comfortable room temperature."
        ),
        Exchange(
            question: "Who painted The Starry Night?",
            answer: "Vincent van Gogh, in June 1889, from his window at the asylum in Saint-Rémy."
        ),
    ]

    static let width: CGFloat = 460
    private static let cardHeight: CGFloat = 92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var typed = 0
    @State private var answered = false
    @State private var sent = false

    private var exchange: Exchange { Self.exchanges[index] }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                if answered {
                    card
                        .transition(CardBloomTransition())
                }
            }
            .frame(width: Self.width, height: Self.cardHeight, alignment: .bottom)

            bar
        }
        .task { await loop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: a question typed into Flyby, and its answer appearing above it")
    }

    // MARK: Pieces

    private var bar: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if typed == 0 {
                    Text("Ask anything")
                        .foregroundStyle(Palette.hint)
                        .transition(.opacity)
                }
                HStack(spacing: 1) {
                    Text(exchange.question.prefix(typed))
                        .foregroundStyle(.white)
                    Caret(isTyping: typed > 0 && typed < exchange.question.count)
                }
            }
            .font(.system(size: 17))
            .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "sparkle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(sent ? 0.3 : 0.12)))
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(width: Self.width, height: 52)
        .surface(shape, style: .smoke)
        .scaleEffect(sent ? 0.98 : 1)
    }

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            Label("Answer", systemImage: "sparkle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            RevealText(exchange.answer, delay: 0.15, timing: .stream)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: Self.width, height: Self.cardHeight, alignment: .topLeading)
        .surface(shape, style: .smoke)
    }

    // MARK: Loop

    private func loop() async {
        guard !reduceMotion else {
            typed = exchange.question.count
            answered = true
            return
        }
        // Waits for the welcome headline to finish writing itself in.
        try? await Task.sleep(for: .seconds(1.2))
        while !Task.isCancelled {
            let question = exchange.question
            for count in 1...question.count {
                typed = count
                // A little unevenness reads as a person typing.
                let jitter = Double((count * 37) % 5) * 0.012
                try? await Task.sleep(for: .seconds(0.045 + jitter))
                if Task.isCancelled { return }
            }
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.spring(duration: 0.18)) { sent = true }
            try? await Task.sleep(for: .seconds(0.14))
            withAnimation(.spring(duration: 0.35, bounce: 0.4)) { sent = false }
            withAnimation(.spring(duration: 0.6, bounce: 0.22)) { answered = true }
            try? await Task.sleep(for: .seconds(3.4))
            withAnimation(.smooth(duration: 0.35)) { answered = false }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.smooth(duration: 0.25)) { typed = 0 }
            try? await Task.sleep(for: .seconds(0.5))
            index = (index + 1) % Self.exchanges.count
        }
    }
}

/// The text cursor: solid while typing, blinking at rest.
private struct Caret: View {
    let isTyping: Bool
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(width: 2, height: 20)
            .opacity(isTyping || visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { visible = false }
            }
    }
}

/// The answer card growing up out of the bar and folding back into it.
private struct CardBloomTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 8)
            .scaleEffect(phase.isIdentity ? 1 : 0.9, anchor: .bottom)
            .offset(y: phase.isIdentity ? 0 : 14)
    }
}
