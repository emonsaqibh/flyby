import SwiftUI

/// Settings › Answers: which provider answers, and that provider's setup
/// right under the choice — so picking Gemini puts the key field in front of
/// you instead of three sections down.
struct AnswersPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var google = GoogleSession.shared
    @ObservedObject private var navigation = SettingsNavigation.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Form {
            PaneHero(section: .answers)

            Section("Answer With") {
                ForEach(ProviderKind.allCases) { kind in
                    ProviderChoiceRow(kind: kind, isSelected: settings.provider == kind) {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.35)) {
                            settings.provider = kind
                        }
                    }
                }
            }

            setup

            Section {
                Picker("Search engine", selection: $settings.engine) {
                    ForEach(SearchEngine.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Browser")
            } footer: {
                Text("Used when opening in your browser, including ⌘Return from any provider.")
            }
        }
        .formStyle(.grouped)
    }

    /// The chosen provider's own settings. The browser has none beyond the
    /// search engine, which every provider uses for ⌘Return.
    @ViewBuilder
    private var setup: some View {
        switch settings.provider {
        case .browser:
            EmptyView()
        case .aiMode:
            aiMode
        case .gemini:
            gemini
        case .appleIntelligence:
            Section {
                AppleIntelligenceStatus()
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text("Answers come from Apple’s on-device model: private and offline, but without the live web.")
            }
        }
    }

    private var aiMode: some View {
        Section {
            // AI Mode without an account is the path Google quizzes most;
            // say so where the choice is made.
            LabeledContent {
                if google.isConnected {
                    Button("Manage…") { navigation.section = .google }
                } else {
                    Button("Connect…") { navigation.section = .google }
                }
            } label: {
                Text("Google Account")
                Text(google.isConnected
                     ? "Connected — Google treats Flyby like your browser."
                     : "Connect for fewer “are you human?” checks.")
            }

            Toggle("Reader mode", isOn: $settings.readerMode)
        } header: {
            Text("Google AI Mode")
        } footer: {
            Text("Reader mode hides Google’s navigation, sign-in and composer when Flyby shows Google’s page itself, so only the answer shows. Turn it off if it ever hides too much.")
        }
    }

    private var gemini: some View {
        Section {
            SecureField("API key", text: $settings.geminiKey, prompt: Text("Paste your key"))
            TextField("Model", text: $settings.geminiModel, prompt: Text(AppSettings.defaultGeminiModel))
        } header: {
            Text("Gemini")
        } footer: {
            Text("Stored in your Keychain, never written to disk in plain text. The free tier covers everyday use. [Get a free key from Google AI Studio](https://aistudio.google.com/apikey)")
        }
    }
}

/// One provider as a choice: its badge, what it is, what it does, and a
/// check when it's the one answering. The check changes shape as well as
/// colour, so the choice never rests on colour alone.
private struct ProviderChoiceRow: View {
    let kind: ProviderKind
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                kind.badge(size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .font(.system(size: 13))
                    Text(kind.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!kind.isAvailable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Answers questions with \(kind.label).")
    }
}
