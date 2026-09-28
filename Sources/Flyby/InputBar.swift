import SwiftUI
import AppKit
import FlybyCore

/// The input: the one text field Flyby has, for its whole time on screen.
///
/// In the bar it's large type that wraps onto new lines — the bar grows
/// taller, never wider — the way Siri's does. Once the card is out it's the
/// follow-up field along the card's bottom edge. Keeping it one field means
/// the keyboard never has to be handed from one to another in the middle of
/// a morph. The stage sizes it, draws its glass and puts the provider chip
/// at its trailing end; this is the text.
///
/// Who the question goes to is said in words, right after the last
/// character: "…in nature? — Ask Gemini". Out of the keyboard, in the card,
/// the field says how to get back into it instead.
struct QueryField: View {
    @ObservedObject var controller: SearchController
    let style: InputStyle
    /// Along the bottom of the card rather than on its own.
    let isInCard: Bool
    /// Has the keyboard.
    let isFocused: Bool
    let questions: Namespace.ID
    /// How many lines the text takes, hint included — reported up, because
    /// that's what sizes the bar.
    @Binding var lines: Int
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            hint
            departingQuestion
            TextField("", text: $controller.query, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .lineLimit(1...style.maxLines)
                .onSubmit { controller.submit() }
                .accessibilityLabel(isFollowUp ? "Follow-up question" : prompt)
        }
        .frame(width: textWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            report(height: height)
        }
        .padding(.leading, style.horizontalPadding)
        .padding(.top, style.verticalPadding)
    }

    private var font: Font { .system(size: style.fontSize) }

    /// Leaves the chip its column, sized for the wider of the provider's name
    /// and Stop, so the text doesn't rewrap when an answer starts.
    private var textWidth: CGFloat {
        style.textWidth(chipColumn: ChipMetrics.column(for: settings.provider))
    }

    private var isFollowUp: Bool { isInCard && controller.isResultVisible }

    /// Who the question goes to: "Ask Gemini", or "Search DuckDuckGo".
    private var prompt: String { settings.provider.prompt(engine: settings.engine) }

    private var placeholder: String { isFollowUp ? "Ask a follow-up" : prompt }

    /// Reading the card, with the keyboard out of the field: Tab brings it
    /// back, and the field says so.
    private var showsTabHint: Bool { isInCard && !isFocused }

    /// " — Ask Gemini", held together with no-break spaces so it moves to the
    /// next line whole rather than leaving "— Ask" dangling.
    private var suffix: String {
        " —\u{00A0}" + prompt.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// Past the line limit the field scrolls inside itself, and the text
    /// behind it no longer lines up with what's showing. And while "/…" is
    /// picking a command, the text isn't a question for anyone.
    private var showsSuffix: Bool {
        lines <= style.maxLines && !showsTabHint && controller.commands.isEmpty
    }

    /// Behind the field: the placeholder while it's empty; once you type,
    /// your text again — clear, so it lays out exactly as the field's own
    /// does, same font, width and line breaks — with the hint after it.
    /// That's what puts the hint right after the last character, on whichever
    /// line that is. It fades in with the first character, and cross-fades
    /// when the provider changes or the keyboard leaves the field.
    private var hint: some View {
        ZStack(alignment: .topLeading) {
            if controller.query.isEmpty {
                placeholderView
                    .id(showsTabHint ? "tab \(placeholder)" : placeholder)
                    .transition(.opacity)
            } else {
                Text("\(Text(controller.query).foregroundStyle(.clear))\(Text(suffix).foregroundStyle(Palette.hint))")
                    // The text changes on every keystroke; only the hint's
                    // arrival and a change of provider should fade.
                    .contentTransition(.identity)
                    .opacity(showsSuffix ? 1 : 0)
                    .id(suffix)
                    .transition(.opacity)
            }
        }
        .font(font)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityHidden(true)
        .animation(Motion.swap, value: controller.query.isEmpty)
        .animation(Motion.swap, value: prompt)
        .animation(Motion.swap, value: showsTabHint)
        .animation(Motion.swap, value: controller.commands.isEmpty)
    }

    @ViewBuilder
    private var placeholderView: some View {
        if showsTabHint {
            HStack(spacing: 6) {
                Keycap("⇥ tab")
                Text(isFollowUp ? "to ask a follow-up" : "to \(prompt.lowercasingFirst)")
            }
            .foregroundStyle(Palette.hint)
        } else {
            Text(placeholder)
                .foregroundStyle(Palette.hint)
        }
    }

    /// Your text once more, invisible, carrying the identity the question
    /// will have once it's asked. Return empties the field and puts the
    /// question's bubble in the card in the same instant; sharing this
    /// identity is what starts the bubble here, where you typed it, and flies
    /// it to where it belongs. Not under Reduce Motion: the bubble just fades
    /// in where it lands.
    @ViewBuilder
    private var departingQuestion: some View {
        if !controller.query.isEmpty, !reduceMotion {
            Text(controller.query)
                .font(font)
                .foregroundStyle(.clear)
                .fixedSize(horizontal: false, vertical: true)
                .matchedGeometryEffect(id: controller.nextTurnID, in: questions, properties: .position)
                .accessibilityHidden(true)
        }
    }

    private func report(height: CGFloat) {
        let measured = max(1, Int((height / style.lineHeight).rounded()))
        guard measured != lines else { return }
        withAnimation(Motion.grow) { lines = measured }
    }
}

extension ProviderKind {
    /// What the input says it'll do with the question.
    func prompt(engine: SearchEngine) -> String {
        switch self {
        case .browser:           return "Search \(engine.label)"
        case .aiMode:            return "Ask Google"
        case .gemini:            return "Ask Gemini"
        case .appleIntelligence: return "Ask Apple Intelligence"
        }
    }

    /// The name on the chip — what you'd call it, not the full product name.
    var shortLabel: String {
        switch self {
        case .browser:           return "Browser"
        case .aiMode:            return "Google"
        case .gemini:            return "Gemini"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    /// ⌘1–⌘4, in the order the menu and Settings list them.
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

private extension String {
    var lowercasingFirst: String { prefix(1).lowercased() + dropFirst() }
}

// MARK: - Provider chip

/// Who answers, drawn as the setting it is: the provider's name and a
/// chevron in a small capsule at the input's trailing end, anchored to the
/// bottom so it stays with the last line as the bar grows upward. It opens
/// the provider menu (so does ⌘K), which also holds everything else a chat
/// offers. While an answer is on its way it's Stop instead (so is ⌘.).
struct ProviderChip: View {
    @ObservedObject var controller: SearchController
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            if controller.isBusy {
                stop
                    .transition(.blurReplace)
            } else {
                provider
                    .transition(.blurReplace)
            }
        }
        .frame(height: ChipMetrics.height)
        // The menu opens over the chip whichever it is — ⌘K works mid-answer.
        .background(alignment: .trailing) {
            ProviderMenuAnchor()
                .frame(width: ChipMetrics.providerWidth(settings.provider), height: ChipMetrics.height)
        }
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: controller.isBusy)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: settings.provider)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var provider: some View {
        Button {
            ProviderMenu.shared.show(for: controller)
        } label: {
            HStack(spacing: ChipMetrics.spacing) {
                Text(settings.provider.shortLabel)
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: ChipMetrics.chevronWidth)
                    .opacity(0.6)
            }
            .font(.system(size: ChipMetrics.fontSize, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, ChipMetrics.horizontalPadding)
            .frame(height: ChipMetrics.height)
            .background(chipFill(Color.white.opacity(hovering ? 0.17 : 0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Answering with \(settings.provider.label). Click or ⌘K to change; ⌘1–⌘4 switch directly.")
        .accessibilityLabel("Provider: \(settings.provider.label)")
        .accessibilityHint("Opens the provider menu")
    }

    private var stop: some View {
        Button {
            controller.stop()
        } label: {
            HStack(spacing: ChipMetrics.spacing) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .frame(width: ChipMetrics.stopGlyphWidth)
                Text("Stop")
                Text("⌘.")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: ChipMetrics.fontSize, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, ChipMetrics.horizontalPadding)
            .frame(height: ChipMetrics.height)
            .background(chipFill(Color.accentColor.opacity(hovering ? 0.45 : 0.32)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Stop answering (⌘.)")
        .accessibilityLabel("Stop answering")
    }

    private func chipFill(_ color: Color) -> some View {
        Capsule()
            .fill(color)
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - Pills

/// Recent Chats and Shortcuts, as two small smoked pills under the bar:
/// secondary, but where the eye already is, each with its key written on it.
/// The one whose panel is open reads as selected.
struct StagePills: View {
    @ObservedObject var controller: SearchController

    var body: some View {
        // Spacing under the gap between them: two pills, never one blob.
        GlassEffectContainer(spacing: 2) {
            HStack(spacing: 8) {
                StagePill(
                    symbol: "clock.arrow.circlepath",
                    title: "Recent Chats",
                    shortcut: "⌘Y",
                    isActive: controller.showsHistory
                ) {
                    controller.toggleHistory()
                }
                StagePill(
                    symbol: "keyboard",
                    title: "Shortcuts",
                    shortcut: "⌘/",
                    isActive: controller.showsShortcuts
                ) {
                    controller.showsShortcuts.toggle()
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: controller.showsHistory)
        .animation(.easeOut(duration: 0.18), value: controller.showsShortcuts)
    }
}

private struct StagePill: View {
    let symbol: String
    let title: String
    let shortcut: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 11)
            .frame(height: StageMetrics.pillHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .surface(Capsule(), style: .smoke, interactive: true)
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(false)
        }
        .help("\(title) (\(shortcut))")
        .accessibilityLabel(title)
        .accessibilityHint("Shortcut: \(shortcut)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
