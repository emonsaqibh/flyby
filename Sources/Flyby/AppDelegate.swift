import AppKit
import SwiftUI
import Combine
import os
import ServiceManagement
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// NSApplication holds its delegate weakly; this is the strong reference,
    /// for the life of the process.
    static let shared = AppDelegate()

    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "ui")

    private let controller = SearchController()
    private let stage = PanelStage()
    private let hotKeys = HotKeyMonitor()
    /// ⌥⇧Space by default: a screenshot of the window you're in, into Flyby.
    private let screenshotHotKeys = HotKeyMonitor(number: 2) { AppSettings.shared.screenshotShortcut }
    /// The main shortcut's state, as `installShortcut` last found it.
    private var mainShortcutHealth: ShortcutHealth = .ok
    private var isCapturing = false
    private var waveGeneration = 0
    // Lazy, so a launch that hands straight over to the installed copy never
    // builds a window it won't use.
    private lazy var panel = FlybyPanel(controller: controller, stage: stage)
    /// Bumped on every open and close, so a close animation that finishes
    /// after Flyby was opened again doesn't hide it.
    private var presentationGeneration = 0
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    /// The walkthrough window is showing What's new rather than the
    /// walkthrough.
    private var isShowingWhatsNew = false
    private var statusItem: NSStatusItem?
    private var shortcutProblemMenuItem: NSMenuItem?
    private var openMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var appSettingsMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    /// The last "that combo is taken" message shown, so reinstalling the same
    /// broken shortcut twice in a row (recorder commit, then the settings
    /// change) doesn't alert twice.
    private var lastReportedProblem: String?
    /// Whoever was frontmost when Flyby opened, to hand focus back to.
    private var previousApp: NSRunningApplication?
    private var isRunning = false
    private var cancellables = Set<AnyCancellable>()

    /// What the menu bar icon says about the shortcut.
    private enum ShortcutHealth {
        case ok
        case unavailable(String)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything else: if this launch is off the disk image, moving
        // now relaunches from /Applications, and onboarding runs there instead
        // of granting permissions to a path that's about to disappear.
        if Installer.offerInstallIfNeeded() {
            // The installed copy is starting, and this one quits once it has.
            // Only if that launch fails does this copy carry on.
            NotificationCenter.default.publisher(for: Installer.relaunchDidFail)
                .first()
                .sink { [weak self] _ in self?.finishLaunching() }
                .store(in: &cancellables)
            return
        }
        finishLaunching()
    }

    private func finishLaunching() {
        guard !isRunning else { return }
        isRunning = true

        // Built up front, so the first summon doesn't pay for it.
        _ = panel
        installStatusItem()
        installMenu()
        observeSetupState()
        observeDismissRequests()
        observeOnboardingRequests()
        observeInstaller()
        observeOtherInstances()
        observeFocusRequests()
        observeSettingsRequests()
        installKeyboardShortcuts()
        startHotKeys()
        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboarding()
        } else if AppSettings.shared.needsWhatsNew {
            showWhatsNew()
        }
        observeCaptureRequests()
        // Nothing of an earlier run's screenshots is kept, and the wave's
        // shader compiles now rather than on the first capture.
        Screenshot.removeFiles()
        CaptureWave.prewarm()
        openDebugWindowIfAsked()
        AIModeDebug.runIfAsked(controller) { [weak self] in self?.showFlyby() }
        AIModeDebug.runConsoleIfAsked(controller)
        // Never prompts, so it's fine alongside onboarding. A session the
        // browser has since rotated is what sends AI Mode's first search
        // into a CAPTCHA.
        Task { await GoogleSession.shared.refreshIfStale() }
        Updater.shared.applyAutomaticChecks()
        observeUpdates()
        observeGoogleSettingsRequests()
        Self.log.info("launch-at-login status=\(String(describing: SMAppService.mainApp.status), privacy: .public)")
        announceReplacedShortcutIfNeeded()
    }

    private var ownsKeyWindow: Bool {
        panel.isKeyWindow
    }

    /// The input has the keyboard — not the web page, and not a selection in
    /// an answer.
    private var isTypingInInput: Bool { panel.inputEditor != nil }

    /// The keyboard is in Google's page — a CAPTCHA's field, a consent
    /// button — which gets its own keys, Tab included.
    private var isInWebPage: Bool {
        var view = panel.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }

    /// Flyby's keys, all of them handled here: typing stays in the input, so
    /// shortcuts attached to buttons would never fire. `KeyboardMap` lists
    /// them for the shortcuts overlay (⌘/); keep the two in step.
    ///
    /// The keyboard is in one of three places. **Typing** in the input, where
    /// text editing keeps every key it uses. **Reading** the card, after Esc
    /// or a click in an answer: the arrows, Space and the page keys scroll,
    /// Tab goes back to the input, and anything typed lands in it. Or **in
    /// Google's page**, which keeps its keys. Esc steps back one level at a
    /// time — the shortcuts, recent chats, the input, then Flyby itself; ⌘W
    /// closes at once.
    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            let handled = MainActor.assumeIsolated { self?.handleKeyDown(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard ownsKeyWindow else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.contains(.command) {
            return handleCommand(event, modifiers: modifiers)
        }

        // An input method mid-composition owns the keyboard: its arrows pick
        // candidates, Return commits, Esc cancels. And the text it's
        // composing isn't in the query yet, so "empty" would be a lie.
        if panel.inputEditor?.hasMarkedText() == true { return false }

        let typing = isTypingInInput
        let inPage = isInWebPage
        let emptyInput = controller.query.isEmpty
        let reading = stage.isPresented && controller.showsPanel && !typing && !inPage
        let key = event.keyCode

        // The slash-command list, while it's open, has the keys that move
        // through it and run it; Return is the input's own, and runs it too.
        if typing, !controller.commands.isEmpty, modifiers.isEmpty {
            switch key {
            case Key.escape:
                controller.dismissCommands()
                return true
            case Key.upArrow, Key.downArrow:
                controller.moveCommandSelection(by: key == Key.upArrow ? -1 : 1)
                return true
            case Key.tab:
                controller.runSelectedCommand()
                return true
            default:
                break
            }
        }

        switch key {
        case Key.escape:
            if controller.showsShortcuts {
                controller.showsShortcuts = false
            } else if controller.showsHistory {
                controller.closeHistory()
            } else if typing, controller.showsPanel {
                panel.leaveInput()
            } else {
                hideFlyby()
            }
            return true

        case Key.returnKey, Key.enter:
            // Typing, Return is the field's own (it asks). Reading the list,
            // it opens the highlighted chat.
            guard modifiers.isEmpty, !typing, !inPage, controller.showsHistory,
                  let id = controller.historySelection else { return false }
            controller.openConversation(id)
            return true

        case Key.tab:
            guard !inPage, modifiers.subtracting(.shift).isEmpty else { return false }
            // From anywhere in the card, into the input; in the input, Tab
            // goes nowhere — the input is where it leads.
            panel.focusInput()
            return true

        case Key.upArrow, Key.downArrow:
            guard modifiers.isEmpty, !inPage else { return false }
            let up = key == Key.upArrow
            if controller.showsHistory, !typing || emptyInput {
                controller.moveHistorySelection(by: up ? -1 : 1)
                return true
            }
            if typing, emptyInput, up {
                controller.openHistory()
                return true
            }
            if reading, canScrollAnswer {
                scrollAnswer(up ? .lineUp : .lineDown)
                return true
            }
            return false

        case Key.space:
            guard reading, canScrollAnswer, modifiers.subtracting(.shift).isEmpty else { break }
            scrollAnswer(modifiers.contains(.shift) ? .pageUp : .pageDown)
            return true

        case Key.pageUp, Key.pageDown:
            // The input is a few lines at most; paging only ever means the
            // answer, typing or not.
            guard canScrollAnswer, !inPage else { return false }
            scrollAnswer(key == Key.pageUp ? .pageUp : .pageDown)
            return true

        case Key.home, Key.end:
            guard canScrollAnswer, !inPage, !typing || emptyInput else { return false }
            scrollAnswer(key == Key.home ? .top : .bottom)
            return true

        default:
            break
        }

        // Reading, anything typed is the start of a follow-up: into the input
        // it goes, and the keystroke with it.
        if reading, modifiers.subtracting([.shift, .option]).isEmpty, Self.isPrintable(event) {
            panel.focusInput()
        }
        return false
    }

    private func handleCommand(_ event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        let typing = isTypingInInput
        let reading = stage.isPresented && controller.showsPanel && !typing && !isInWebPage

        if modifiers == .command {
            switch event.keyCode {
            case Key.returnKey, Key.enter:
                controller.submitToBrowser()
                return true
            case Key.upArrow, Key.downArrow:
                // In the input these move the caret to the start or end.
                guard reading, canScrollAnswer else { return false }
                scrollAnswer(event.keyCode == Key.upArrow ? .top : .bottom)
                return true
            case Key.delete:
                // In an empty input there's nothing for ⌘⌫ to delete.
                guard controller.showsHistory, !typing || controller.query.isEmpty else { return false }
                controller.deleteSelectedConversation()
                return true
            default:
                break
            }
            for provider in ProviderKind.allCases {
                let digit = "\(provider.number)"
                if Self.matches(event, character: digit, keyCode: Key.digits[provider.number - 1])
                    || event.keyCode == Key.digits[provider.number - 1] {
                    AppSettings.shared.provider = provider
                    return true
                }
            }
            if Self.matches(event, character: "w", keyCode: 13) {
                hideFlyby()
                return true
            }
            if Self.matches(event, character: "k", keyCode: 40) {
                // After this key event is done with: the menu runs a tracking
                // loop of its own.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    ProviderMenu.shared.show(for: self.controller)
                }
                return true
            }
            if Self.matches(event, character: "/", keyCode: 44) {
                controller.showsShortcuts.toggle()
                return true
            }
            if Self.matches(event, character: "n", keyCode: 45), controller.showsPanel {
                controller.newChat()
                return true
            }
            if Self.matches(event, character: "y", keyCode: 16) {
                controller.toggleHistory()
                return true
            }
            if Self.matches(event, character: ".", keyCode: 47) {
                // Stop, or nothing. Left alone, ⌘. is Cocoa's "cancel" and
                // would close Flyby outright, skipping Esc's steps back.
                controller.stop()
                return true
            }
            if Self.matches(event, character: "r", keyCode: 15), controller.isResultVisible {
                controller.retry()
                return true
            }
        }
        if modifiers == [.command, .shift], Self.matches(event, character: "c", keyCode: 8), controller.isResultVisible {
            controller.copyAnswer()
            return true
        }
        return false
    }

    /// There's a conversation on the card to scroll — not the history list,
    /// not Google's page.
    private var canScrollAnswer: Bool {
        stage.isPresented && controller.isResultVisible && !controller.showsHistory && !controller.showsWebPage
    }

    private func scrollAnswer(_ scroll: AnswerScroll) {
        NotificationCenter.default.post(name: .flybyShouldScrollAnswer, object: scroll)
    }

    /// Text rather than a key that moves or edits: the function and arrow
    /// keys type characters in the private-use range, Return and friends
    /// control characters.
    private static func isPrintable(_ event: NSEvent) -> Bool {
        guard let scalar = event.characters?.unicodeScalars.first else { return false }
        if scalar.value < 0x20 || scalar.value == 0x7F { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }
        return true
    }

    /// Virtual key codes, which name positions rather than characters — right
    /// for keys that aren't letters.
    private enum Key {
        static let returnKey: UInt16 = 36
        static let enter: UInt16 = 76
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let home: UInt16 = 115
        static let pageUp: UInt16 = 116
        static let end: UInt16 = 119
        static let pageDown: UInt16 = 121
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        /// 1 to 4 along the top row.
        static let digits: [UInt16] = [18, 19, 20, 21]
    }

    /// Matches by the character the layout types, as menus do, falling back
    /// to the ANSI key position on layouts that don't type Latin letters.
    private static func matches(_ event: NSEvent, character: String, keyCode: UInt16) -> Bool {
        if let typed = event.charactersIgnoringModifiers?.lowercased(),
           let scalar = typed.unicodeScalars.first, scalar.isASCII {
            return typed == character
        }
        return event.keyCode == keyCode
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.stop()
        screenshotHotKeys.stop()
        AppSettings.shared.flushPendingWrites()
    }

    /// Re-opening the app from Finder or `open -a` has nowhere to go for a
    /// menu-bar-only app, so treat it as a request for Flyby — unless the
    /// user is mid-onboarding, in which case bring that back instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        handleOpenRequest()
        return true
    }

    private func handleOpenRequest() {
        guard isRunning else { return }
        if let onboardingWindow {
            bringToFront(onboardingWindow)
        } else {
            showFlyby()
        }
    }

    /// A second copy launched while this one runs asks for Flyby and quits
    /// (see `SingleInstance`); from the user's side, launching Flyby again
    /// opens Flyby.
    private func observeOtherInstances() {
        DistributedNotificationCenter.default()
            .publisher(for: SingleInstance.showRequest)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleOpenRequest() }
            .store(in: &cancellables)
    }

    /// Settings' "Move to Applications": let go of the hot key before the
    /// installed copy starts and registers its own, and take it back if that
    /// copy never starts.
    private func observeInstaller() {
        NotificationCenter.default.publisher(for: Installer.willRelaunch)
            .sink { [weak self] _ in
                self?.hotKeys.stop()
                self?.screenshotHotKeys.stop()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: Installer.relaunchDidFail)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.installShortcut(reportProblems: false)
                self?.installScreenshotShortcut(reportProblems: false)
            }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey

    private func startHotKeys() {
        // A scripted run owns the chat; a shortcut would reset it mid-question.
        if AIModeDebug.isScripted {
            Self.log.notice("scripted debug run: not listening for shortcuts")
            return
        }
        hotKeys.onTrigger = { [weak self] in
            // The practice step listens for this as proof the shortcut works
            // end to end. While the walkthrough (or What's new) is up, that's
            // all a press is: Flyby doesn't open over it.
            NotificationCenter.default.post(name: .flybyDidTriggerShortcut, object: nil)
            guard let self else { return }
            if let onboardingWindow = self.onboardingWindow {
                self.bringToFront(onboardingWindow)
                return
            }
            self.toggleFlyby()
        }
        // A combo another app owns is said out loud when the user has just
        // chosen it — mid-onboarding too — and at launch only by the menu bar.
        installShortcut(reportProblems: AppSettings.shared.hasCompletedOnboarding)
        AppSettings.shared.$shortcut
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.installShortcut(reportProblems: true) }
            .store(in: &cancellables)

        screenshotHotKeys.onTrigger = { [weak self] in self?.captureScreen() }
        installScreenshotShortcut(reportProblems: false)
        AppSettings.shared.$screenshotShortcut
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.installScreenshotShortcut(reportProblems: true) }
            .store(in: &cancellables)
    }

    /// Like the main shortcut: a combo another app owns is said under the
    /// recorder, in the menu bar, and — when the user has just chosen it —
    /// out loud.
    private func installScreenshotShortcut(reportProblems: Bool) {
        switch screenshotHotKeys.reload() {
        case .active, .off:
            setScreenshotProblem(nil)
        case .paused:
            break
        case .unavailable(let reason):
            setScreenshotProblem(reason)
            if reportProblems, reason != lastReportedProblem {
                lastReportedProblem = reason
                Task { @MainActor [weak self] in self?.presentUnavailableAlert(reason) }
            }
        }
    }

    private func setScreenshotProblem(_ problem: String?) {
        ShortcutHealthModel.shared.screenshot = problem
        refreshStatusItem()
    }

    /// The recorder has the keyboard: pause the live shortcuts (which also
    /// unregisters them, so the same combo can be recorded again), and bring
    /// them back once recording ends however it ends.
    private func setRecording(_ recording: Bool) {
        if recording {
            // A fresh attempt: re-recording the same taken combo should say so again.
            lastReportedProblem = nil
            hotKeys.isPaused = true
            // Either recorder: neither shortcut should fire while the other
            // is being recorded.
            screenshotHotKeys.isPaused = true
        } else {
            guard hotKeys.isPaused else { return }
            hotKeys.isPaused = false
            screenshotHotKeys.isPaused = false
            installShortcut(reportProblems: true)
            installScreenshotShortcut(reportProblems: true)
        }
    }

    private func installShortcut(reportProblems: Bool) {
        switch hotKeys.reload() {
        case .active, .paused, .off:
            lastReportedProblem = nil
            updateStatusItem(.ok)
        case .unavailable(let reason):
            updateStatusItem(.unavailable(reason))
            if reportProblems, reason != lastReportedProblem {
                lastReportedProblem = reason
                // Deferred: this can run inside the recorder's key handling,
                // and a modal session in the middle of that is asking for
                // trouble.
                Task { @MainActor [weak self] in self?.presentUnavailableAlert(reason) }
            }
        }
    }

    /// Shortcuts became key combos only in 0.6. Someone whose double-tap or
    /// chord was replaced by the default hears it once, rather than finding
    /// their shortcut quietly doing nothing.
    private func announceReplacedShortcutIfNeeded() {
        guard AppSettings.shared.replacedRetiredShortcut, AppSettings.shared.hasCompletedOnboarding else { return }
        let name = BuildFlavor.appName
        let alert = NSAlert()
        alert.messageText = "\(name) now opens with \(AppSettings.shared.shortcut.displayString)"
        alert.informativeText = """
        Double-tap and held-modifier shortcuts are gone: on this version of macOS \
        they needed two privacy permissions that updates kept taking away. \
        Shortcuts are key combos now, which need none.

        Keep \(AppSettings.shared.shortcut.displayString), or record your own in Settings › Shortcut.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Change It…")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            SettingsNavigation.shared.section = .shortcut
            openSettings()
        }
    }

    /// A taken combo isn't a permission problem, and polling for a grant
    /// would never fix it — the only fix is a different shortcut.
    private func presentUnavailableAlert(_ reason: String) {
        let alert = NSAlert()
        alert.messageText = "Your shortcut isn't available"
        alert.informativeText = reason
        alert.addButton(withTitle: onboardingWindow == nil ? "Open Settings" : "OK")
        if onboardingWindow == nil { alert.addButton(withTitle: "Later") }
        alert.alertStyle = .warning

        NSApp.activate()
        let choice = alert.runModal()
        // Onboarding is already showing the recorder; Settings would only
        // fight it for the hot key.
        if onboardingWindow == nil, choice == .alertFirstButtonReturn {
            openSettings()
        }
    }

    // MARK: - Screenshots

    /// The Screenshot pill and /screenshot ask through the controller.
    private func observeCaptureRequests() {
        NotificationCenter.default.publisher(for: .flybyShouldCaptureScreen)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.captureScreen() }
            .store(in: &cancellables)
    }

    /// A screenshot of the window the user was in, waiting over the input
    /// for their question. From anywhere with the shortcut — Flyby opens with
    /// it — or from the bar, which takes a new one. The wave plays across
    /// the display as it's taken.
    private func captureScreen() {
        guard isRunning, !isCapturing else { return }
        // The walkthrough or What's new is up: a practice run, nothing more.
        if onboardingWindow != nil {
            practiceScreenshot()
            return
        }
        // Not set up yet: back to where setup left off.
        guard AppSettings.shared.hasCompletedOnboarding else {
            showOnboarding()
            return
        }
        // The app the user was in: whatever's in front, or, with Flyby open
        // (and so in front), the one Flyby came from.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let target = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApp : frontmost

        // The wave plays where the bar is, or where it's about to open.
        let barScreen = stage.isPresented && !stage.isClosing ? (panel.screen ?? FlybyPanel.activeScreen) : FlybyPanel.activeScreen

        guard ScreenCapture.hasPermission else {
            reportCaptureProblem(.notAllowed)
            return
        }
        isCapturing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }
            do {
                let capture = try await ScreenCapture.capture(windowOf: target, waveScreen: barScreen)
                AppSettings.shared.hasCapturedScreen = true
                self.playWave(for: capture)
                self.openFlybyIfClosed()
                self.controller.attach(capture.screenshot)
            } catch let failure as ScreenCapture.Failure {
                self.reportCaptureProblem(failure)
            } catch {
                self.reportCaptureProblem(.failed(error.localizedDescription))
            }
        }
    }

    /// The screenshot shortcut during setup: the wave crosses the screen if
    /// Flyby can see it, and the screenshot step hears that it worked.
    /// Nothing is attached and Flyby doesn't open. The walkthrough window is
    /// lifted over the wave, which would otherwise hide it for a second.
    private func practiceScreenshot() {
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            return
        }
        isCapturing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }
            guard let capture = try? await ScreenCapture.capture(windowOf: nil) else { return }
            let window = self.onboardingWindow
            let resting = window?.level ?? .normal
            window?.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            CaptureWave.play(
                over: capture.screen, showing: capture.display,
                from: FlybyPanel.barCenter(on: capture.screen), focus: capture.windowFrame,
                level: .screenSaver
            ) { window?.level = resting }
            NotificationCenter.default.post(name: .flybyDidTriggerScreenshotShortcut, object: nil)
        }
    }

    /// Said over the input, in Flyby — opened for it if need be — with
    /// macOS asked as well: it prompts whenever Flyby isn't in its list at
    /// all, and says nothing when an entry's there, on or off, or stale from
    /// an earlier build that no longer matches.
    private func reportCaptureProblem(_ failure: ScreenCapture.Failure) {
        openFlybyIfClosed()
        switch failure {
        case .notAllowed:
            ScreenCapture.requestPermission()
            controller.captureNotice = AppSettings.shared.hasCapturedScreen ? .permissionLost : .needsPermission
        case .failed(let message):
            controller.captureNotice = .failed(message)
        }
    }

    private func openFlybyIfClosed() {
        if !stage.isPresented || stage.isClosing { showFlyby() }
    }

    /// From the middle of the bar, over everything on its display, the menu
    /// bar and Dock included — except the bar itself, lifted above it until
    /// it's done, so it can open while the wave crosses the screen behind it.
    private func playWave(for capture: ScreenCapture.Capture) {
        waveGeneration += 1
        let generation = waveGeneration
        let resting = NSWindow.Level.floating
        // Lifted first: a wave that can't play finishes before `play` returns.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        CaptureWave.play(
            over: capture.screen, showing: capture.display,
            from: FlybyPanel.barCenter(on: capture.screen), focus: capture.windowFrame,
            level: .screenSaver
        ) { [weak self] in
            guard let self, generation == self.waveGeneration else { return }
            self.panel.level = resting
        }
    }

    // MARK: - Showing and hiding

    private func toggleFlyby() {
        if stage.isPresented { hideFlyby() } else { showFlyby() }
    }

    private func showFlyby() {
        guard isRunning else { return }
        // Flyby is for after setup: until then, every way in leads back to
        // the walkthrough, on the step it was left on.
        guard AppSettings.shared.hasCompletedOnboarding else {
            showOnboarding()
            return
        }
        presentationGeneration += 1
        let generation = presentationGeneration
        // Folded up first, so emptying the panel of a close still in progress
        // doesn't play the card folding back into the bar on its way out.
        stage.prepare()
        controller.reset()
        guard let screen = FlybyPanel.activeScreen else { return }

        // Reopened mid-close: this app is still frontmost, and the app to go
        // back to is the one remembered before.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }

        // In place before the window shows, so the first frame is the blob
        // the bar opens out of.
        panel.position(on: screen)
        panel.ignoresMouseEvents = false
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        // Now, not on SwiftUI's next pass: typing works from the first key.
        panel.focusInput()
        startWatchingForOutsideClicks()
        // Next pass, once the folded state has been drawn: animating from a
        // state that never reached the screen would skip the opening. Not if
        // it was closed again in the meantime.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, generation == self.presentationGeneration else { return }
            self.stage.present()
            Self.log.info("presented inputFocused=\(self.panel.inputEditor != nil, privacy: .public)")
        }

        // A cold Google page, or a cold on-device model, costs the first
        // answer a second or two; warming it while the user types hides that.
        switch AppSettings.shared.provider {
        case .aiMode:            controller.aiMode.prewarm()
        case .appleIntelligence: AppleIntelligenceProvider.prewarm()
        case .browser, .gemini:  break
        }
        Self.log.info("shown visible=\(self.panel.isVisible, privacy: .public) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    /// `returnFocus` is false when the dismissal came from a click elsewhere:
    /// that click already picked where focus goes.
    ///
    /// Focus goes back at once — whatever is typed during the closing
    /// animation belongs to the app the user is returning to — while the
    /// window stays up for the animation and goes once it has played.
    private func hideFlyby(returnFocus: Bool = true) {
        // Already on its way out: a second Esc shouldn't cut the close short.
        guard !stage.isClosing, stage.isPresented || panel.isVisible else { return }
        stopWatchingForOutsideClicks()
        // What's left on screen is on its way out; clicks on it belong to
        // whatever is underneath.
        panel.ignoresMouseEvents = true
        presentationGeneration += 1
        let generation = presentationGeneration

        let previous = previousApp
        previousApp = nil

        // With Settings or onboarding open, hand focus back without hiding
        // anything — the practice step literally asks for Esc. Otherwise
        // the app hides once the animation is done, which also returns focus
        // if there was no app to hand it to.
        let auxiliary = visibleAuxiliaryWindow
        if returnFocus {
            if let previous, !previous.isTerminated {
                _ = previous.activate(options: [])
            } else if let auxiliary {
                auxiliary.makeKeyAndOrderFront(nil)
            }
        }

        stage.dismiss { [weak self] in
            guard let self, generation == self.presentationGeneration else { return }
            self.panel.orderOut(nil)
            self.controller.reset()
            if self.visibleAuxiliaryWindow == nil, NSApp.isActive {
                NSApp.hide(nil)
            }
        }
    }

    /// Settings, onboarding, the Google sign-in window, an alert: any titled
    /// window of ours still on screen besides Flyby's own.
    private var visibleAuxiliaryWindow: NSWindow? {
        NSApp.windows.first { window in
            window !== panel
                && window.isVisible
                && window.styleMask.contains(.titled)
        }
    }

    /// /settings. Flyby steps aside first, as it does for "Connect Google
    /// Account…": Settings is a window of its own, and a floating bar over it
    /// would only be in the way.
    private func observeSettingsRequests() {
        NotificationCenter.default.publisher(for: .flybyShouldOpenSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.stage.isPresented { self.hideFlyby(returnFocus: false) }
                self.openSettings()
            }
            .store(in: &cancellables)
    }

    /// The controller hands the keyboard back to the input after a question
    /// is sent, a chat is opened, or the history list closes.
    private func observeFocusRequests() {
        NotificationCenter.default.publisher(for: .flybyShouldFocusInput)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panel.focusInput() }
            .store(in: &cancellables)
    }

    private func observeDismissRequests() {
        NotificationCenter.default.publisher(for: .quickSearchShouldDismiss)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.hideFlyby() }
            .store(in: &cancellables)
    }

    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideFlyby(returnFocus: false) }
        }
    }

    private func stopWatchingForOutsideClicks() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    // MARK: - Menu bar

    /// A lens with a spark: search that answers, which is the product. The
    /// warning triangle replaces it whenever the shortcut is dead.
    private static func statusImage(for health: ShortcutHealth) -> NSImage? {
        switch health {
        case .ok:
            return NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "Flyby")
                ?? NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Flyby")
        case .unavailable:
            return NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Flyby — shortcut unavailable"
            )
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.statusImage(for: .ok)

        let menu = NSMenu()
        let problemItem = NSMenuItem(
            title: "Shortcut Unavailable — Change It…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        problemItem.isHidden = true
        menu.addItem(problemItem)
        let updateItem = NSMenuItem(title: "", action: #selector(showAvailableUpdate), keyEquivalent: "")
        updateItem.isHidden = true
        menu.addItem(updateItem)
        openMenuItem = menu.addItem(withTitle: "Open \(BuildFlavor.appName)", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        settingsMenuItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(BuildFlavor.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = $0.action == #selector(NSApplication.terminate(_:)) ? nil : self }
        item.menu = menu
        // Hovering says which build this is — with a dev and a release build
        // both in the menu bar, the icons alone can't.
        item.button?.toolTip = "\(BuildFlavor.appName) \(BuildFlavor.versionLabel)"
        statusItem = item
        updateMenuItem = updateItem
        shortcutProblemMenuItem = problemItem
    }

    /// The menu bar is the only surface the user can see when a shortcut is
    /// dead, so it carries the warning — the main shortcut's first, then the
    /// screenshot one's. The recorders say it too.
    private func updateStatusItem(_ health: ShortcutHealth) {
        mainShortcutHealth = health
        switch health {
        case .ok:                       ShortcutHealthModel.shared.main = nil
        case .unavailable(let reason):  ShortcutHealthModel.shared.main = reason
        }
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        var health = mainShortcutHealth
        if case .ok = health, let reason = ShortcutHealthModel.shared.screenshot {
            health = .unavailable(reason)
        }
        switch health {
        case .ok:
            shortcutProblemMenuItem?.isHidden = true
        case .unavailable(let reason):
            shortcutProblemMenuItem?.isHidden = false
            shortcutProblemMenuItem?.toolTip = reason
        }
        statusItem?.button?.image = Self.statusImage(for: health)
    }

    // MARK: - Updates

    /// A waiting update shows up at the top of the menu-bar menu — the one
    /// place a menu-bar app can say something without interrupting.
    private func observeUpdates() {
        Updater.shared.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] release in
                guard let item = self?.updateMenuItem else { return }
                item.isHidden = release == nil
                if let release {
                    item.title = "Update Available — \(BuildFlavor.appName) \(release.version.description)…"
                }
            }
            .store(in: &cancellables)
    }

    /// "Connect Google Account…" from the provider menu or the card's banner.
    /// Flyby closes first: Settings is where the connecting happens, and a
    /// floating card over it would only be in the way.
    private func observeGoogleSettingsRequests() {
        NotificationCenter.default.publisher(for: .flybyShouldShowGoogleSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.stage.isPresented { self.hideFlyby(returnFocus: false) }
                self.openSettings()
            }
            .store(in: &cancellables)
    }

    @objc private func checkForUpdates() {
        UpdateCommand.checkNow()
    }

    @objc private func showAvailableUpdate() {
        UpdateCommand.checkNow()
    }

    /// A minimal main menu so ⌘, ⌘Q and text editing shortcuts work.
    private func installMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appSettingsMenuItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appSettingsMenuItem?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Flyby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func openFromMenu() {
        showFlyby()
    }

    /// Before setup is done the menu says what's left to do, and Settings
    /// isn't offered: Flyby is for after the walkthrough.
    private func observeSetupState() {
        AppSettings.shared.$hasCompletedOnboarding
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshSetupMenus() }
            .store(in: &cancellables)
    }

    private func refreshSetupMenus() {
        let done = AppSettings.shared.hasCompletedOnboarding
        let name = BuildFlavor.appName
        openMenuItem?.title = done ? "Open \(name)" : "Finish Setting Up \(name)…"
        settingsMenuItem?.isHidden = !done
        appSettingsMenuItem?.isHidden = !done
    }

    // MARK: - Onboarding

    private func observeOnboardingRequests() {
        NotificationCenter.default.publisher(for: .flybyShouldShowOnboarding)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // Settings and the walkthrough both drive the same recorder;
                // two of them open at once is a fight over the hot key.
                self?.settingsWindow?.orderOut(nil)
                self?.setRecording(false)
                self?.showOnboarding()
            }
            .store(in: &cancellables)
    }

    /// Dev builds only: opens a window at launch, so it can be looked at (and
    /// screenshotted) without clicking through the menu bar. Arguments land in
    /// the volatile defaults domain, so nothing is remembered:
    ///
    ///     open "build/Flyby Dev.app" --args -FlybyDebugOpen onboarding
    ///     open "build/Flyby Dev.app" --args -FlybyDebugOpen settings.answers
    ///
    /// `-FlybyDebugAppearance light|dark` sets the app's appearance. Every
    /// Flyby window pins itself dark, so `light` only proves that still holds.
    private func openDebugWindowIfAsked() {
        guard BuildFlavor.isDev else { return }
        switch UserDefaults.standard.string(forKey: "FlybyDebugAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
        default:      break
        }
        guard let target = UserDefaults.standard.string(forKey: "FlybyDebugOpen") else { return }
        if target == "onboarding" {
            showOnboarding()
        } else if target == "whatsnew" {
            showWhatsNew()
        } else if target.hasPrefix("settings") {
            if let section = SettingsSection(rawValue: String(target.dropFirst("settings.".count))) {
                SettingsNavigation.shared.section = section
            }
            openSettings()
        }
    }

    private func showOnboarding() {
        if let onboardingWindow {
            bringToFront(onboardingWindow)
            return
        }

        let window = OnboardingView.makeWindow(
            onRecordingChanged: { [weak self] recording in self?.setRecording(recording) },
            onFinished: { [weak self] in self?.finishOnboarding() }
        )
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        onboardingWindow = window
        bringToFront(window)
    }

    /// In front of everything, whichever app was — a menu-bar app's windows
    /// otherwise open behind the one the user is in.
    private func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// What's new, once, for an install that finished the walkthrough before
    /// it: the same window and steps, just the new ones.
    private func showWhatsNew() {
        if let onboardingWindow {
            bringToFront(onboardingWindow)
            return
        }
        let window = OnboardingView.makeWindow(
            mode: .whatsNew,
            onRecordingChanged: { [weak self] recording in self?.setRecording(recording) },
            onFinished: { [weak self] in self?.finishOnboarding() }
        )
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        onboardingWindow = window
        isShowingWhatsNew = true
        bringToFront(window)
    }

    /// The walkthrough or What's new, done: either way, what's new has been
    /// seen.
    private func finishOnboarding() {
        AppSettings.shared.hasCompletedOnboarding = true
        AppSettings.shared.onboardingStep = nil
        AppSettings.shared.whatsNewSeen = AppSettings.currentWhatsNew
        isShowingWhatsNew = false
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        if hotKeys.isPaused {
            setRecording(false)
        } else {
            installShortcut(reportProblems: false)
        }
    }

    @objc private func openSettings() {
        // Settings is for after setup too.
        guard AppSettings.shared.hasCompletedOnboarding else {
            showOnboarding()
            return
        }
        if let settingsWindow {
            NSApp.activate()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = SettingsView.makeWindow(onRecordingChanged: { [weak self] recording in
            self?.setRecording(recording)
        })
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        settingsWindow = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Both auxiliary windows are cached so they can be re-shown; forgetting them
/// when they close is what keeps "reopen" from resurrecting a walkthrough
/// somebody deliberately dismissed.
///
/// Either can close mid-recording, and the recorder can't be relied on to
/// report that itself, so closing always un-pauses the hot key.
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === onboardingWindow {
            // Closing What's new counts as seeing it; it doesn't come back.
            if isShowingWhatsNew {
                AppSettings.shared.whatsNewSeen = AppSettings.currentWhatsNew
                isShowingWhatsNew = false
            }
            onboardingWindow = nil
            setRecording(false)
        }
        if window === settingsWindow {
            settingsWindow = nil
            setRecording(false)
        }
    }
}
