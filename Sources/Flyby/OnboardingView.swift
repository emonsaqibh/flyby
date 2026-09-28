import SwiftUI
import AppKit
import Combine

/// The first-launch walkthrough: greet, pick a provider (and connect
/// Google, if that provider is AI Mode), record the trigger, clear the
/// Accessibility gate if the trigger needs it, then prove the whole thing
/// works by actually firing it once.
///
/// One step at a time on a glowing aura, with very little text: a headline
/// that writes itself in, a line under it, and one thing to do. The steps
/// themselves live in Onboarding/; this view owns where the user is, how
/// they move, and the chrome around it.
struct OnboardingView: View {
    /// In the order they're shown. Which ones are shown is `visibleSteps`.
    enum Step: Int, CaseIterable {
        case welcome, provider, google, hotkey, accessibility, practice, done
    }

    static let size = CGSize(width: 760, height: 540)

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var google = GoogleSession.shared
    /// Pauses the live hotkey while the recorder is armed, same as Settings.
    let onRecordingChanged: (Bool) -> Void
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step
    @State private var direction: OnboardingDirection = .forward
    @State private var axTrusted = HotKeyMonitor.isTrusted
    @State private var practiceSucceeded = false
    /// When the practice shortcut last fired, for the aura's burst of light.
    @State private var celebratedAt: Date?
    /// The footer and progress arrive after the welcome does, so the first
    /// thing on screen is the product, not the controls.
    @State private var chromeShown = false
    /// Permission landed, and the step is holding a beat to show it before
    /// moving on.
    @State private var leavingAccessibility = false
    /// Dev builds: stands in for a real grant (`OnboardingDebug`).
    @State private var debugTrusted = false

    private let axPoll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(onRecordingChanged: @escaping (Bool) -> Void, onFinished: @escaping () -> Void) {
        self.onRecordingChanged = onRecordingChanged
        self.onFinished = onFinished
        _step = State(initialValue: OnboardingDebug.initialStep ?? .welcome)
    }

    var body: some View {
        ZStack {
            OnboardingAura(phase: auraPhase, glow: auraGlow, burstDate: celebratedAt)
                .animation(reduceMotion ? .easeInOut(duration: 0.4) : .smooth(duration: 1.8), value: step)
                .animation(.smooth(duration: 1.4), value: practiceSucceeded)

            // Every step hangs from the same line, so headlines don't jump
            // between steps — or within one, when a choice grows the page.
            ZStack(alignment: .top) {
                stepContent
                    .id(step)
                    .transition(AsymmetricTransition(
                        insertion: IdentityTransition(),
                        removal: StepExitTransition(reduceMotion: reduceMotion)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 80)
            .padding(.bottom, 84)
            .environment(\.onboardingDirection, direction)

            chrome
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .ignoresSafeArea()
        .onReceive(axPoll) { _ in pollAccessibility() }
        .onReceive(NotificationCenter.default.publisher(for: .flybyDidTriggerShortcut)) { _ in
            if step == .practice, !practiceSucceeded { celebrate() }
        }
        // Firing the old shortcut proves nothing about a new one.
        .onChange(of: settings.shortcut) { _, _ in
            practiceSucceeded = false
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.6).delay(step == .welcome ? 1.0 : 0.3)) { chromeShown = true }
        }
        .task { await autoplayIfAsked() }
        .task(id: step) { await debugStepHooks() }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStep()
        case .provider:
            ProviderStep(settings: settings)
        case .google:
            GoogleStep()
        case .hotkey:
            ShortcutStep(settings: settings, onRecordingChanged: onRecordingChanged)
        case .accessibility:
            AccessibilityStep(isTrusted: axTrusted)
        case .practice:
            PracticeStep(shortcut: settings.shortcut, succeeded: practiceSucceeded)
        case .done:
            DoneStep(settings: settings)
        }
    }

    /// Where each step parks the aura's light. Uneven steps, so no two
    /// neighbours look alike.
    private var auraPhase: Double {
        switch step {
        case .welcome:       return 0
        case .provider:      return 1.4
        case .google:        return 2.1
        case .hotkey:        return 3.0
        case .accessibility: return 3.7
        case .practice:      return 4.5
        case .done:          return 5.6
        }
    }

    /// A little more light once it works, and at the end.
    private var auraGlow: Double {
        switch step {
        case .practice where practiceSucceeded: return 0.3
        case .done:                             return 0.3
        default:                                return 0
        }
    }

    // MARK: - Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            // Level with the traffic lights, in the titlebar's own band.
            ProgressCapsules(count: visibleSteps.count, current: visibleSteps.firstIndex(of: step) ?? 0)
                .padding(.top, 12)

            Spacer(minLength: 0)

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 26)
        }
        .opacity(chromeShown ? 1 : 0)
        .background { closeShortcut }
    }

    private var footer: some View {
        ZStack {
            HStack {
                if showsBack {
                    Button(action: retreat) {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .transition(SoftSwapTransition())
                }
                Spacer()
            }

            Button(action: primaryAction) {
                Text(continueTitle)
                    .contentTransition(.interpolate)
                    .frame(minWidth: 170)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
        }
        .animation(.smooth(duration: 0.3), value: showsBack)
        .animation(.smooth(duration: 0.3), value: continueTitle)
    }

    /// ⌘W, as in any other window. The app's minimal main menu has no Close
    /// item to carry it, so a button nobody sees does.
    private var closeShortcut: some View {
        Button("Close Window") {
            NSApp.keyWindow?.performClose(nil)
        }
        .keyboardShortcut("w", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var showsBack: Bool {
        step != .welcome && step != .done
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
    /// navigation and the progress capsules, so progress never promises a
    /// step that won't come.
    ///
    /// The Accessibility gate stays in the list while it's on screen even
    /// once permission lands, so its capsule doesn't vanish under the user in
    /// the moment before the step moves itself on.
    private var visibleSteps: [Step] {
        var steps: [Step] = [.welcome, .provider]
        if settings.provider == .aiMode { steps.append(.google) }
        steps.append(.hotkey)
        if shapeNeedsAccessibility, !axTrusted || step == .accessibility {
            steps.append(.accessibility)
        }
        steps.append(contentsOf: [.practice, .done])
        return steps
    }

    private var shapeNeedsAccessibility: Bool {
        if case .keyCombo = settings.shortcut { return false }
        return true
    }

    // MARK: - Navigation

    private func primaryAction() {
        if step == .done {
            onFinished()
        } else {
            advance()
        }
    }

    private func advance() {
        // Read fresh rather than trusting the last poll: permission granted in
        // the last second shouldn't route through the gate.
        axTrusted = isTrusted
        guard let next = visibleSteps.first(where: { $0.rawValue > step.rawValue }) else { return }
        go(to: next, direction: .forward)
    }

    private func retreat() {
        guard let previous = visibleSteps.last(where: { $0.rawValue < step.rawValue }) else { return }
        go(to: previous, direction: .backward)
    }

    /// The outgoing page leaves the same way whichever way the user is going,
    /// so direction only matters to what arrives — and that reads it as it's
    /// created. Nothing waits on anything, so clicks can come as fast as
    /// they like: every page just starts arriving or leaving.
    private func go(to target: Step, direction: OnboardingDirection) {
        self.direction = direction
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.26)) {
            step = target
        }
    }

    // MARK: - Accessibility gate

    private var isTrusted: Bool {
        HotKeyMonitor.isTrusted || debugTrusted
    }

    private func pollAccessibility() {
        let trusted = isTrusted
        if trusted != axTrusted {
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) { axTrusted = trusted }
        }
        // The moment permission lands, the gate step has done its job — after
        // a beat, so the check is seen landing.
        guard step == .accessibility, trusted, !leavingAccessibility else { return }
        leavingAccessibility = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            leavingAccessibility = false
            if step == .accessibility { advance() }
        }
    }

    // MARK: - Practice

    private func celebrate() {
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { practiceSucceeded = true }
        celebratedAt = .now
    }

    // MARK: - Debug

    private func autoplayIfAsked() async {
        guard let interval = OnboardingDebug.autoplayInterval else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(interval))
            if step == .done {
                go(to: .welcome, direction: .forward)
            } else {
                advance()
            }
        }
    }

    private func debugStepHooks() async {
        if step == .practice, OnboardingDebug.practiceSucceeds, !practiceSucceeded {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .flybyDidTriggerShortcut, object: nil)
        }
        if step == .accessibility, let delay = OnboardingDebug.grantsAccessibilityAfter {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            debugTrusted = true
            pollAccessibility()
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

extension OnboardingView {
    /// The walkthrough's window: a fixed landscape canvas, always dark, the
    /// aura running right up under a transparent titlebar, movable by its
    /// background. The
    /// app delegate owns its lifetime: it positions it, keeps it, and hears
    /// it close.
    static func makeWindow(
        onRecordingChanged: @escaping (Bool) -> Void,
        onFinished: @escaping () -> Void
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Never drawn, but it's what VoiceOver, Mission Control and the
        // Window menu call it.
        window.title = "Welcome to Flyby"
        // Flyby is a dark product — the overlay has no light mode — so its
        // introduction is dark too, whatever the Mac is set to.
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        let host = NSHostingView(
            rootView: OnboardingView(onRecordingChanged: onRecordingChanged, onFinished: onFinished)
                .modifier(OnboardingDebug.AccessibilityOverrides())
        )
        // The canvas runs under the titlebar, so it's the window's whole
        // frame. Left to size itself, the hosting view would fit the canvas
        // *below* the titlebar and leave a band of nothing at the bottom.
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        return window
    }
}
