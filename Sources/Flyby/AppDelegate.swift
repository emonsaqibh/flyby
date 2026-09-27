import AppKit
import SwiftUI
import Combine
import os
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// NSApplication holds its delegate weakly; this is the strong reference,
    /// for the life of the process.
    static let shared = AppDelegate()

    private static let log = Logger(subsystem: "com.fringecore.flyby", category: "ui")

    private let controller = SearchController()
    private let hotKeys = HotKeyMonitor()
    // Lazy, so a launch that hands straight over to the installed copy never
    // builds windows it won't use.
    private lazy var panel = PillPanel(controller: controller)
    private lazy var results = ResultPanel(controller: controller)
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var shortcutProblemMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var outsideClickMonitor: Any?
    private var keyMonitor: Any?
    private var permissionPoll: Task<Void, Never>?
    private var hasShownAccessibilityAlert = false
    /// The last "that combo is taken" message shown, so reinstalling the same
    /// broken shortcut twice in a row (recorder commit, then the settings
    /// change) doesn't alert twice.
    private var lastReportedProblem: String?
    /// Whoever was frontmost when the pill opened, to hand focus back to.
    private var previousApp: NSRunningApplication?
    private var isRunning = false
    private var cancellables = Set<AnyCancellable>()

    /// What the menu bar icon says about the shortcut.
    private enum ShortcutHealth {
        case ok
        case needsAccessibility
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

        // Built up front, so the first summon doesn't pay for them.
        _ = panel
        _ = results
        installStatusItem()
        installMenu()
        observeDismissRequests()
        observeOnboardingRequests()
        observeInstaller()
        observeOtherInstances()
        observeModeChanges()
        installKeyboardShortcuts()
        observeAppearance()
        startHotKeys()
        if !AppSettings.shared.hasCompletedOnboarding {
            showOnboarding()
        }
        // Never prompts, so it's fine alongside onboarding. A session the
        // browser has since rotated is what sends AI Mode's first search
        // into a CAPTCHA.
        Task { await GoogleSession.shared.refreshIfStale() }
        Updater.shared.applyAutomaticChecks()
        observeUpdates()
        observeGoogleSettingsRequests()
        Self.log.info("launch-at-login status=\(String(describing: SMAppService.mainApp.status), privacy: .public)")
    }

    /// Appearance is set once on `NSApp`, which every window — pill, result
    /// panel, settings — inherits.
    private func observeAppearance() {
        AppSettings.shared.$appearance
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { NSApp.appearance = $0.nsAppearance }
            .store(in: &cancellables)
    }

    private var ownsKeyWindow: Bool {
        panel.isKeyWindow || results.isKeyWindow
    }

    /// The pill's keys. ⌘Return escapes to the real browser whatever the
    /// provider is, and Esc closes — both need intercepting, since the text
    /// field swallows Return and the web view swallows Esc. The rest act on
    /// the answer: ⌘. stops it, ⌘R asks again, ⌘⇧C copies it. Plain ⌘C is
    /// left alone so it keeps copying the selection.
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

        // Return (36) or keypad Enter (76).
        if event.keyCode == 36 || event.keyCode == 76, modifiers.contains(.command) {
            controller.submitToBrowser()
            return true
        }
        if event.keyCode == 53 {  // Esc
            hidePill()
            return true
        }
        if modifiers == .command, Self.matches(event, character: ".", keyCode: 47), controller.isBusy {
            controller.stop()
            return true
        }
        if modifiers == .command, Self.matches(event, character: "r", keyCode: 15), controller.isResultVisible {
            controller.retry()
            return true
        }
        if modifiers == [.command, .shift], Self.matches(event, character: "c", keyCode: 8), controller.isResultVisible {
            controller.copyAnswer()
            return true
        }
        return false
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
        AppSettings.shared.flushPendingWrites()
    }

    /// Re-opening the app from Finder or `open -a` has nowhere to go for a
    /// menu-bar-only app, so treat it as a request for the pill — unless the
    /// user is mid-onboarding, in which case bring that back instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        handleOpenRequest()
        return true
    }

    private func handleOpenRequest() {
        guard isRunning else { return }
        if let onboardingWindow {
            NSApp.activate()
            onboardingWindow.makeKeyAndOrderFront(nil)
        } else {
            showPill()
        }
    }

    /// A second copy launched while this one runs asks for the pill and quits
    /// (see `SingleInstance`); from the user's side, launching Flyby again
    /// opens Flyby.
    private func observeOtherInstances() {
        DistributedNotificationCenter.default()
            .publisher(for: SingleInstance.showPillRequest)
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
                self?.stopPermissionPoll()
                self?.hotKeys.stop()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: Installer.relaunchDidFail)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.installShortcut(promptIfNeeded: false, reportProblems: false) }
            .store(in: &cancellables)
    }

    // MARK: - Hotkey

    private func startHotKeys() {
        hotKeys.onTrigger = { [weak self] in
            // The onboarding practice step listens for this as proof the
            // pipeline works end to end.
            NotificationCenter.default.post(name: .flybyDidTriggerShortcut, object: nil)
            self?.togglePill()
        }
        hotKeys.onAccessibilityLost = { [weak self] in
            // Revoked while running. Same state as a launch without the grant:
            // the menu bar says so and the poll waits for it to come back.
            self?.installShortcut(promptIfNeeded: false, reportProblems: false)
        }
        // During onboarding the flow owns the permission conversation — no
        // alert on top of it.
        let onboarded = AppSettings.shared.hasCompletedOnboarding
        installShortcut(promptIfNeeded: onboarded, reportProblems: onboarded)

        // Re-install when the user records a different shortcut: the Carbon and
        // event-tap paths aren't interchangeable, so this is a real rebuild.
        // A combo that turns out to be taken is reported even mid-onboarding —
        // the user just chose it and needs to know.
        AppSettings.shared.$shortcut
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.installShortcut(
                    promptIfNeeded: AppSettings.shared.hasCompletedOnboarding,
                    reportProblems: true
                )
            }
            .store(in: &cancellables)
    }

    /// The recorder has the keyboard: pause the live shortcut (which also
    /// unregisters a Carbon combo, so it can be re-recorded), and bring it
    /// back once recording ends however it ends.
    private func setRecording(_ recording: Bool) {
        if recording {
            stopPermissionPoll()
            // A fresh attempt: re-recording the same taken combo should say so again.
            lastReportedProblem = nil
            hotKeys.isPaused = true
        } else {
            guard hotKeys.isPaused else { return }
            hotKeys.isPaused = false
            installShortcut(promptIfNeeded: false, reportProblems: true)
        }
    }

    private func installShortcut(promptIfNeeded: Bool, reportProblems: Bool) {
        stopPermissionPoll()

        switch hotKeys.reload() {
        case .active, .paused:
            lastReportedProblem = nil
            updateStatusItem(.ok)

        case .needsAccessibility:
            // Only a modifier-only gesture can fail this way, and only for want
            // of Accessibility permission.
            updateStatusItem(.needsAccessibility)
            if promptIfNeeded {
                HotKeyMonitor.ensureAccessibilityPermission()
                presentAccessibilityAlert()
            }
            startPermissionPoll()

        case .unavailable(let reason):
            // No poll: waiting won't free a combo another app owns.
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

    /// Checks every second, so the shortcut starts working the moment
    /// permission is granted, without needing a relaunch.
    private func startPermissionPoll() {
        permissionPoll?.cancel()
        permissionPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                // The recorder owns the keyboard; it reinstalls when it's done.
                if self.hotKeys.isPaused { continue }

                switch self.hotKeys.reload() {
                case .needsAccessibility, .paused:
                    continue
                case .active:
                    self.permissionPoll = nil
                    self.updateStatusItem(.ok)
                    return
                case .unavailable(let reason):
                    self.permissionPoll = nil
                    self.updateStatusItem(.unavailable(reason))
                    return
                }
            }
        }
    }

    private func stopPermissionPoll() {
        permissionPoll?.cancel()
        permissionPoll = nil
    }

    /// Silent failure here is the worst outcome — the shortcut just does
    /// nothing and there's no way to tell why — so say it out loud, once.
    private func presentAccessibilityAlert() {
        guard !hasShownAccessibilityAlert else { return }
        hasShownAccessibilityAlert = true

        // By the bundle's own name: the dev build is listed as "Flyby Dev".
        let name = BuildFlavor.appName
        let alert = NSAlert()
        alert.messageText = "\(name) needs Accessibility permission"
        alert.informativeText = """
        Your shortcut is a modifier-only gesture, which macOS will only deliver \
        through an Accessibility-gated event tap.

        Approve “\(name)” in System Settings › Privacy & Security › \
        Accessibility. It starts working within a second — no relaunch needed.

        If it's already listed, remove it with the − button and add it again: \
        rebuilding changes the app's signature and invalidates the old entry.

        You can also avoid this entirely by recording a shortcut that includes \
        a regular key, like ⌥Space — those need no permission at all.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.alertStyle = .warning

        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            HotKeyMonitor.openAccessibilitySettings()
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

    // MARK: - Showing and hiding

    private func togglePill() {
        if panel.isVisible { hidePill() } else { showPill() }
    }

    private func showPill() {
        guard isRunning else { return }
        controller.reset()
        guard let screen = PillPanel.activeScreen else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        panel.position(on: screen)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .quickSearchDidShow, object: nil)
        startWatchingForOutsideClicks()

        // A cold Google page costs the first AI Mode search a second or two;
        // warming it while the user types hides that.
        if AppSettings.shared.provider == .aiMode {
            controller.aiMode.prewarm()
        }
        Self.log.info("pill shown visible=\(self.panel.isVisible, privacy: .public) frame=\(NSStringFromRect(self.panel.frame), privacy: .public)")
    }

    /// `returnFocus` is false when the dismissal came from a click elsewhere:
    /// that click already picked where focus goes.
    private func hidePill(returnFocus: Bool = true) {
        stopWatchingForOutsideClicks()
        results.dismiss()
        panel.orderOut(nil)
        controller.reset()

        let previous = previousApp
        previousApp = nil

        // Hiding the app hands focus back to whatever the user was working
        // in — but it would also hide Settings or onboarding, and the practice
        // step literally asks for Esc. With one of those open, give focus back
        // without hiding anything.
        guard let window = visibleAuxiliaryWindow else {
            NSApp.hide(nil)
            return
        }
        guard returnFocus else { return }
        if let previous, !previous.isTerminated {
            _ = previous.activate(options: [])
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Settings, onboarding, the Google sign-in window, an alert: any titled
    /// window of ours still on screen once the pill and panel are gone.
    private var visibleAuxiliaryWindow: NSWindow? {
        NSApp.windows.first { window in
            window !== panel && window !== results
                && window.isVisible
                && window.styleMask.contains(.titled)
        }
    }

    private func observeDismissRequests() {
        NotificationCenter.default.publisher(for: .quickSearchShouldDismiss)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.hidePill() }
            .store(in: &cancellables)
    }

    /// Unfolds the result panel upward out of the pill as soon as there's
    /// something to show.
    private func observeModeChanges() {
        controller.$phase
            .map { $0 != .idle }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] showing in
                guard let self, self.panel.isVisible else { return }

                if showing {
                    // The pill's own screen, not wherever the mouse has
                    // wandered since it opened: the two read as one object.
                    guard let screen = self.panel.screen ?? PillPanel.activeScreen else { return }
                    self.results.present(on: screen)
                } else {
                    self.results.dismiss()
                }

                // The result panel is ordered in front; keep typing in the pill.
                self.panel.makeKeyAndOrderFront(nil)
            }
            .store(in: &cancellables)
    }

    private func startWatchingForOutsideClicks() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hidePill(returnFocus: false) }
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
        case .needsAccessibility:
            return NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Flyby — needs Accessibility permission"
            )
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
        let permissionItem = NSMenuItem(
            title: "Grant Accessibility Permission…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.isHidden = true
        menu.addItem(permissionItem)
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
        menu.addItem(withTitle: "Open \(BuildFlavor.appName)", action: #selector(openFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
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
        accessibilityMenuItem = permissionItem
        shortcutProblemMenuItem = problemItem
    }

    /// The menu bar is the only surface the user can see when the shortcut is
    /// dead, so it carries the warning.
    private func updateStatusItem(_ health: ShortcutHealth) {
        switch health {
        case .ok:
            accessibilityMenuItem?.isHidden = true
            shortcutProblemMenuItem?.isHidden = true
        case .needsAccessibility:
            accessibilityMenuItem?.isHidden = false
            shortcutProblemMenuItem?.isHidden = true
        case .unavailable(let reason):
            accessibilityMenuItem?.isHidden = true
            shortcutProblemMenuItem?.isHidden = false
            shortcutProblemMenuItem?.toolTip = reason
        }
        statusItem?.button?.image = Self.statusImage(for: health)
    }

    @objc private func openAccessibilitySettings() {
        HotKeyMonitor.ensureAccessibilityPermission()
        HotKeyMonitor.openAccessibilitySettings()
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

    /// "Connect Google Account…" from the pill's menu or the result panel's
    /// banner. The pill closes first: Settings is where the connecting
    /// happens, and a floating pill over it would only be in the way.
    private func observeGoogleSettingsRequests() {
        NotificationCenter.default.publisher(for: .flybyShouldShowGoogleSettings)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.panel.isVisible { self.hidePill(returnFocus: false) }
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
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
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
        showPill()
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

    private func showOnboarding() {
        if let onboardingWindow {
            NSApp.activate()
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: OnboardingView(
                onRecordingChanged: { [weak self] recording in self?.setRecording(recording) },
                onFinished: { [weak self] in self?.finishOnboarding() }
            )
        )
        window.center()
        window.delegate = self
        onboardingWindow = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        AppSettings.shared.hasCompletedOnboarding = true
        onboardingWindow?.orderOut(nil)
        onboardingWindow = nil
        // If the Accessibility gate was skipped, the poll keeps trying and the
        // menu bar carries the warning — same as any other launch.
        if hotKeys.isPaused {
            setRecording(false)
        } else {
            installShortcut(promptIfNeeded: false, reportProblems: false)
        }
    }

    @objc private func openSettings() {
        if let settingsWindow {
            NSApp.activate()
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsView.size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(BuildFlavor.appName) Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView(onRecordingChanged: { [weak self] recording in
                self?.setRecording(recording)
            })
        )
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
            onboardingWindow = nil
            setRecording(false)
        }
        if window === settingsWindow {
            settingsWindow = nil
            setRecording(false)
        }
    }
}
