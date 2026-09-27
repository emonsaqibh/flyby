import SwiftUI
import AppKit
import Combine

/// The first-launch walkthrough: greet, style, pick a provider (and connect
/// Google, if that provider is AI Mode), record the trigger, clear the
/// Accessibility gate if the trigger needs it, then prove the whole thing
/// works by actually firing it once.
struct OnboardingView: View {
    /// In the order they're shown. Which ones are shown is `visibleSteps`.
    enum Step: Int, CaseIterable {
        case welcome, appearance, provider, google, hotkey, accessibility, practice, done
    }

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var google = GoogleSession.shared
    /// Pauses the live hotkey while the recorder is armed, same as Settings.
    let onRecordingChanged: (Bool) -> Void
    let onFinished: () -> Void

    @State private var step: Step = .welcome
    @State private var goingForward = true
    @State private var axTrusted = HotKeyMonitor.isTrusted
    @State private var practiceSucceeded = false

    private let axPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                stepContent
                    .padding(.horizontal, 48)
                    .padding(.top, 36)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: goingForward ? .trailing : .leading)
                            .combined(with: .opacity),
                        removal: .move(edge: goingForward ? .leading : .trailing)
                            .combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
        .frame(width: 580, height: 560)
        .background(backdrop)
        .themed()
        .onReceive(axPoll) { _ in
            axTrusted = HotKeyMonitor.isTrusted
            // The moment permission lands, the gate step has done its job.
            if step == .accessibility, axTrusted {
                advance()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .flybyDidTriggerShortcut)) { _ in
            if step == .practice {
                withAnimation(.spring(duration: 0.4)) { practiceSucceeded = true }
            }
        }
        // Firing the old shortcut proves nothing about a new one.
        .onChange(of: settings.shortcut) { _, _ in
            practiceSucceeded = false
        }
    }

    /// A whisper of the icon's sky gradient behind everything, so the window
    /// reads as Flyby's rather than a generic form.
    private var backdrop: some View {
        ZStack {
            Rectangle().fill(.background)
            LinearGradient(
                colors: [settings.accent.color.opacity(0.14), .clear],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.55)
            )
        }
        .ignoresSafeArea()
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:       welcome
        case .appearance:    appearance
        case .provider:      provider
        case .google:        googleStep
        case .hotkey:        hotkey
        case .accessibility: accessibility
        case .practice:      practice
        case .done:          done
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 118, height: 118)
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .padding(.top, 26)
                .accessibilityHidden(true)

            Text("Welcome to Flyby")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)

            Text("Search from anywhere on your Mac with one gesture —\na quick pill that appears, answers, and gets out of the way.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("The next few steps take about a minute.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.top, 10)
        }
    }

    private var appearance: some View {
        VStack(spacing: 18) {
            header(
                symbol: "paintbrush.pointed.fill",
                title: "Make it yours",
                subtitle: "All of this can be changed later in Settings."
            )

            card {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                Divider()

                LabeledContent("Accent") {
                    AccentSwatches(selection: $settings.accent, diameter: 20)
                }

                if LiquidGlass.isSupported {
                    Divider()
                    Toggle("Liquid Glass material", isOn: $settings.liquidGlass)
                    Text("The macOS glass look for the pill and answer panel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var provider: some View {
        VStack(spacing: 18) {
            header(
                symbol: "sparkle.magnifyingglass",
                title: "Where should answers come from?",
                subtitle: "Flyby can hand off to your browser or answer inline."
            )

            card {
                ForEach(ProviderKind.allCases) { kind in
                    providerRow(kind)
                    if kind != ProviderKind.allCases.last { Divider() }
                }
            }

            card {
                Picker("Search engine", selection: $settings.engine) {
                    ForEach(SearchEngine.allCases) { Text($0.label).tag($0) }
                }
                Text("Used for browser searches, including ⌘Return from anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.provider == .gemini {
                    Divider()
                    SecureField("Gemini API key", text: $settings.geminiKey)
                        .textFieldStyle(.roundedBorder)
                    Link("Get a free key from Google AI Studio",
                         destination: URL(string: "https://aistudio.google.com/apikey")!)
                        .font(.caption)
                }
            }
        }
    }

    /// Only for AI Mode, and skippable: AI Mode works without an account, it
    /// just gets quizzed more. Scrolls, because a problem row and its fix can
    /// make the card taller than the window.
    private var googleStep: some View {
        VStack(spacing: 18) {
            header(
                symbol: "person.crop.circle.badge.checkmark",
                title: "Connect your Google account",
                subtitle: "AI Mode runs in your own Google session, so Google treats\nFlyby like your browser — and rarely asks if you're human."
            )

            ScrollView {
                card {
                    GoogleConnectView(layout: .card)
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var hotkey: some View {
        VStack(spacing: 18) {
            header(
                symbol: "keyboard.fill",
                title: "Your summon gesture",
                subtitle: "Double-tap Right ⌥ is the default — or record your own."
            )

            card {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(
                        shortcut: $settings.shortcut,
                        onRecordingChanged: onRecordingChanged
                    )
                    .frame(maxWidth: 260)
                }
                Text(settings.shortcut.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Key combos like ⌥Space work with no permissions at all.\nModifier-only gestures — double-taps and chords — need one Accessibility approval, coming up next.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var accessibility: some View {
        VStack(spacing: 18) {
            header(
                symbol: "lock.shield.fill",
                title: "One permission to grant",
                subtitle: "macOS only delivers modifier-only gestures to apps\nyou've approved under Accessibility."
            )

            card {
                if axTrusted {
                    Label("Permission granted — your shortcut is live.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for approval — this step moves on by itself the moment you flip the switch.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Button("Open Accessibility Settings") {
                        HotKeyMonitor.ensureAccessibilityPermission()
                        HotKeyMonitor.openAccessibilitySettings()
                    }
                    .controlSize(.large)
                    .flybyGlassButton(prominent: true)
                }
            }

            Text("Look for “Flyby” in the list and turn it on.\nFlyby only listens for your shortcut — nothing you type is recorded.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var practice: some View {
        VStack(spacing: 18) {
            header(
                symbol: practiceSucceeded ? "checkmark.seal.fill" : "hands.and.sparkles.fill",
                title: practiceSucceeded ? "You've got it!" : "Try it now",
                subtitle: practiceSucceeded
                    ? "That's the whole trick. Flyby is ready whenever you are."
                    : "Fire your shortcut and watch the pill appear."
            )

            Text(settings.shortcut.displayString)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(practiceSucceeded ? Color.green.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            practiceSucceeded ? Color.green.opacity(0.6) : Color.primary.opacity(0.1),
                            lineWidth: 1.5
                        )
                )
                .scaleEffect(practiceSucceeded ? 1.05 : 1)
                .accessibilityLabel("Your shortcut: \(settings.shortcut.displayString)")

            Text(practiceSucceeded
                 ? "Press Esc or click anywhere to put the pill away."
                 : settings.shortcut.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            header(
                symbol: "checkmark.circle.fill",
                title: "You're all set",
                subtitle: "Flyby lives in your menu bar — look for the magnifying glass.\nSettings… is always one click away there."
            )

            card {
                Toggle("Open Flyby at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let status = LoginItem.statusDescription {
                    Label(status, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Recommended, so your shortcut works from the moment you sign in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Pieces

    private func header(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(settings.accent.color)
                .frame(height: 52)
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func providerRow(_ kind: ProviderKind) -> some View {
        let isSelected = settings.provider == kind
        return Button {
            settings.provider = kind
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 17))
                    .foregroundStyle(isSelected ? settings.accent.color : .secondary)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label).font(.system(size: 13, weight: .semibold))
                    Text(kind.detail).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(settings.accent.color)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.label)
        .accessibilityValue(kind.detail)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        HStack {
            if step != .welcome, step != .done {
                Button("Back") { retreat() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            progressDots

            Spacer()

            Button(continueTitle) {
                if step == .done {
                    onFinished()
                } else {
                    advance()
                }
            }
            .controlSize(.large)
            .flybyGlassButton(prominent: true)
            .keyboardShortcut(.defaultAction)
        }
    }

    /// The gates advance themselves or are optional; on those the button is
    /// an escape hatch, and the label should say so.
    private var continueTitle: String {
        switch step {
        case .welcome:                            return "Get Started"
        case .google where !google.isConnected:   return "Skip for Now"
        case .accessibility where !axTrusted:     return "Skip for Now"
        case .practice where !practiceSucceeded:  return "Skip"
        case .done:                               return "Start Using Flyby"
        default:                                  return "Continue"
        }
    }

    /// The steps this user will actually walk through, in order. Drives both
    /// navigation and the progress dots, so the dots never promise a step
    /// that won't come.
    ///
    /// The Accessibility gate stays in the list while it's on screen even
    /// once permission lands, so its dot doesn't vanish under the user in the
    /// moment before the step moves itself on.
    private var visibleSteps: [Step] {
        var steps: [Step] = [.welcome, .appearance, .provider]
        if settings.provider == .aiMode { steps.append(.google) }
        steps.append(.hotkey)
        if shapeNeedsAccessibility, !axTrusted || step == .accessibility {
            steps.append(.accessibility)
        }
        steps.append(contentsOf: [.practice, .done])
        return steps
    }

    private var progressDots: some View {
        let steps = visibleSteps
        let current = steps.firstIndex(of: step) ?? 0
        return HStack(spacing: 7) {
            ForEach(steps, id: \.self) { s in
                Circle()
                    .fill(s == step ? settings.accent.color : Color.primary.opacity(0.15))
                    .frame(width: 7, height: 7)
            }
        }
        .animation(.easeOut(duration: 0.2), value: steps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue("Step \(current + 1) of \(steps.count)")
    }

    private var shapeNeedsAccessibility: Bool {
        if case .keyCombo = settings.shortcut { return false }
        return true
    }

    // MARK: - Navigation

    private func advance() {
        // Read fresh rather than trusting the last poll: permission granted in
        // the last second shouldn't route through the gate.
        axTrusted = HotKeyMonitor.isTrusted
        guard let next = visibleSteps.first(where: { $0.rawValue > step.rawValue }) else { return }
        go(to: next, forward: true)
    }

    private func retreat() {
        guard let previous = visibleSteps.last(where: { $0.rawValue < step.rawValue }) else { return }
        go(to: previous, forward: false)
    }

    /// A removed view leaves with the transition it was last drawn with. So
    /// when the direction flips — the first Back after a Forward — the page on
    /// screen still holds the old exit edge, and changing direction and page
    /// together sends it off the wrong side. On a flip, re-draw it with the new
    /// direction first, then change page a beat later.
    private func go(to target: Step, forward: Bool) {
        let animation = Animation.spring(duration: 0.45)
        guard goingForward != forward else {
            withAnimation(animation) { step = target }
            return
        }
        withAnimation(animation) { goingForward = forward }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            withAnimation(animation) { step = target }
        }
    }
}

extension Notification.Name {
    /// Posted every time the recorded shortcut actually fires — the practice
    /// step listens for it as proof the whole pipeline works.
    static let flybyDidTriggerShortcut = Notification.Name("flybyDidTriggerShortcut")

    /// Settings asking for the walkthrough back, since the window it would need
    /// to open belongs to the app delegate.
    static let flybyShouldShowOnboarding = Notification.Name("flybyShouldShowOnboarding")
}
