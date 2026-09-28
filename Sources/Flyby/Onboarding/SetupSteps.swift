import SwiftUI
import AppKit

// The first half of the walkthrough: hello, where answers come from, and
// (for AI Mode) the Google account behind them.

// MARK: - Welcome

/// The icon, one headline, one line, and Flyby answering a question — then
/// out of the way. The icon takes the first beat, so everything after it
/// arrives a little later than on the other steps.
struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 0) {
            AppIconHero()

            RevealText("Welcome to Flyby", delay: 0.3)
                .font(OnboardingType.hero)
                .tracking(OnboardingType.heroTracking)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 14)

            Text("Ask anything, from anywhere on your Mac.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .reveal(after: 0.62)
                .padding(.top, 8)

            FlybyDemo()
                .reveal(after: 0.8, blurs: false)
                .padding(.top, 20)
        }
    }
}

/// The app icon, springing up out of a blur into a soft pool of its own light.
private struct AppIconHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    var body: some View {
        let moving = !arrived && !reduceMotion
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: 96, height: 96)
            .background {
                Circle()
                    .fill(Color(AuraPalette.azure))
                    .frame(width: 150, height: 150)
                    .blur(radius: 38)
                    .opacity(arrived ? 0.55 : 0)
                    .scaleEffect(arrived ? 1 : 0.5)
            }
            .opacity(arrived ? 1 : 0)
            .blur(radius: moving ? 12 : 0)
            .scaleEffect(moving ? 0.55 : 1)
            .offset(y: moving ? 24 : 0)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.95, bounce: 0.38).delay(RevealOrder.hero.delay)) {
                    arrived = true
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Provider

struct ProviderStep: View {
    @ObservedObject var settings: AppSettings

    static let width: CGFloat = 640

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Where should answers come from?",
                subtitle: "Pick one to start. You can switch any time from Flyby's bar."
            )

            GlassEffectContainer(spacing: 12) {
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        tile(.browser)
                        tile(.aiMode)
                    }
                    GridRow {
                        tile(.gemini)
                        tile(.appleIntelligence)
                    }
                }
            }
            .reveal(.content, blurs: false)
            .padding(.top, 26)

            ProviderSetup(settings: settings)
                .reveal(.controls, blurs: false)
                .padding(.top, 12)
        }
        .frame(width: Self.width)
    }

    private func tile(_ kind: ProviderKind) -> some View {
        ProviderTile(kind: kind, isSelected: settings.provider == kind) {
            withAnimation(.spring(duration: 0.45, bounce: 0.18)) { settings.provider = kind }
        }
    }
}

/// A provider to pick: its badge, its name, what it's like. Chosen, it takes
/// an accent ring and a faint accent tint, and its check pops.
private struct ProviderTile: View {
    let kind: ProviderKind
    let isSelected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        Button(action: select) {
            HStack(spacing: 12) {
                kind.badge(size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .font(.system(size: 14, weight: .semibold))
                    Text(kind.tagline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isSelected)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            // Part of the label rather than an overlay on the tile: inside a
            // glass container, only what's *in* the glass draws above it.
            .overlay {
                shape.strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .paneGlass(shape, tint: isSelected ? Color.accentColor.opacity(0.14) : nil, interactive: true)
        .scaleEffect(hovering ? 1.015 : 1)
        .offset(y: hovering ? -1 : 0)
        .onHover { inside in
            withAnimation(.spring(duration: 0.3, bounce: 0.3)) { hovering = inside }
        }
        .accessibilityLabel(kind.label)
        .accessibilityValue(kind.detail)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private extension ProviderKind {
    /// Shorter than `detail`, which reads as a sentence in Settings; a tile
    /// has room for a phrase.
    var tagline: String {
        switch self {
        case .browser:           return "Opens results in your browser"
        case .aiMode:            return "Google's AI answers, in Flyby"
        case .gemini:            return "Fast answers, with a free key"
        case .appleIntelligence: return "Private, and on this Mac"
        }
    }
}

/// What the chosen provider needs, and the search engine every provider
/// shares. One glass panel whose height follows its contents, so choosing a
/// provider grows or shrinks it rather than jumping.
private struct ProviderSetup: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            providerRow
                // The old row goes at once and the new one focuses in, so
                // the panel's height travels straight from one to the other.
                .id(settings.provider)
                .transition(AsymmetricTransition(insertion: SoftSwapTransition(), removal: IdentityTransition()))

            if settings.provider != .browser {
                Divider().padding(.horizontal, 16)
            }

            engineRow
        }
        .frame(width: ProviderStep.width)
        .paneGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var providerRow: some View {
        switch settings.provider {
        case .browser:
            EmptyView()
        case .aiMode:
            row(badge: IconBadge("person.crop.circle.badge.checkmark", color: .indigo, size: 28)) {
                Text("Next, you can connect your Google account, so Google rarely asks if you're human.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .gemini:
            row(badge: IconBadge("key.fill", color: .teal, size: 28)) {
                SecureField("Paste your Gemini API key", text: $settings.geminiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Gemini API key")
                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    Label("Get a free key", systemImage: "arrow.up.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .font(.system(size: 12, weight: .medium))
                .fixedSize()
            }
        case .appleIntelligence:
            row(badge: ProviderKind.appleIntelligence.badge(size: 28)) {
                AppleIntelligenceStatus()
            }
        }
    }

    private var engineRow: some View {
        row(badge: IconBadge("magnifyingglass", color: .gray, size: 28)) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Search engine")
                    .font(.system(size: 13, weight: .medium))
                Text("For browser searches, and ⌘Return from any provider.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Picker("Search engine", selection: $settings.engine) {
                ForEach(SearchEngine.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private func row<Content: View>(badge: IconBadge, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            badge
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Get a free key ↗": the arrow after the words, where a link's arrow goes.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

// MARK: - Google

/// Only for AI Mode, and skippable: AI Mode works without an account, it
/// just gets quizzed more.
struct GoogleStep: View {
    var body: some View {
        VStack(spacing: 0) {
            StepHeader(
                title: "Connect your Google account",
                subtitle: "Signed in, Google rarely stops Flyby to ask if you're human."
            )

            // Hugs its rows, and scrolls only when it has to: a problem row
            // and its fix can make the card taller than the room left for it.
            ViewThatFits(in: .vertical) {
                connect
                ScrollView { connect }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: 290)
            }
            .frame(width: 560)
            .paneGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .reveal(.content, blurs: false)
            .padding(.top, 24)
        }
    }

    private var connect: some View {
        GoogleConnectView(layout: .card)
            .padding(18)
    }
}
