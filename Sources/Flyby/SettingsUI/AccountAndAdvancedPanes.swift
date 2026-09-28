import SwiftUI

/// Settings › Google Account: the shared connect flow, as form sections.
struct GoogleAccountPane: View {
    var body: some View {
        Form {
            PaneHero(section: .google)
            GoogleConnectView(layout: .form)
        }
        .formStyle(.grouped)
    }
}

/// Settings › Advanced: the walkthrough again, and the way back to a fresh
/// install.
struct AdvancedPane: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @State private var confirmingReset = false

    var body: some View {
        Form {
            PaneHero(section: .advanced)

            Section {
                LabeledContent("Walkthrough") {
                    Button("Show Onboarding Again") { showOnboarding() }
                }
            } footer: {
                Text("Runs the first-launch walkthrough again. Nothing is erased.")
            }

            Section {
                LabeledContent("Everything") {
                    Button("Reset All Data…", role: .destructive) { confirmingReset = true }
                }
            } header: {
                Text("Reset")
            } footer: {
                Text("Clears every preference and your chat history, disconnects your Google account, forgets the Gemini key in your Keychain and turns off open-at-login — the state a fresh install would have. Reinstalling doesn’t do this on its own, because settings live in your user account rather than in the app.")
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reset Flyby to a fresh install?",
            isPresented: $confirmingReset,
            titleVisibility: .visible
        ) {
            Button("Reset All Data", role: .destructive) { resetAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your shortcut, provider settings, chat history, Gemini API key and Google connection are all removed, and onboarding starts over. This can't be undone.")
        }
    }

    private func resetAll() {
        settings.resetAll()
        ConversationHistory.shared.clear()
        Task { await GoogleSession.shared.disconnect() }
        navigation.section = .general
        showOnboarding()
    }

    /// The walkthrough lives in a window the app delegate owns, so Settings can
    /// only ask for it.
    private func showOnboarding() {
        settings.hasCompletedOnboarding = false
        NotificationCenter.default.post(name: .flybyShouldShowOnboarding, object: nil)
    }
}
