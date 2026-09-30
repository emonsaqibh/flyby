import AppKit
import SwiftUI

/// The provider chip's menu: who answers, which engine the browser hop uses,
/// and what a chat offers — search again, copy, Google's page, a new chat —
/// each with its shortcut. Recent Chats and the shortcuts have pills of their
/// own under the bar.
///
/// AppKit rather than a SwiftUI `Menu`, because it has to open from the
/// keyboard (⌘K) as well as from a click, which a SwiftUI menu can't — and
/// this way it opens the way a pop-up button's does, the current provider
/// lined up over the chip. Built afresh each time it opens, so it only ever
/// offers what applies now.
///
/// The key equivalents it lists are the app delegate's while it's closed —
/// typing stays in the input, and the shortcuts work from there — and the
/// menu's own while it's open.
@MainActor
final class ProviderMenu: NSObject {
    static let shared = ProviderMenu()

    /// The chip, which the menu opens over. The chip registers it.
    weak var anchor: NSView?
    private weak var controller: SearchController?

    private var settings: AppSettings { .shared }

    func show(for controller: SearchController) {
        guard let anchor, anchor.window != nil else { return }
        self.controller = controller
        let menu = makeMenu(for: controller)
        let current = menu.items.first { ($0.representedObject as? ProviderKind) == settings.provider }
        // The current provider's row over the chip, its title roughly on
        // the chip's label.
        let top = anchor.isFlipped ? 0 : anchor.bounds.height
        menu.popUp(positioning: current, at: NSPoint(x: -14, y: top + (anchor.isFlipped ? 3 : -3)), in: anchor)
    }

    // MARK: - Building

    private func makeMenu(for controller: SearchController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(.sectionHeader(title: "Answer with"))
        for provider in ProviderKind.allCases {
            let item = self.item(provider.label, symbol: provider.icon, key: "\(provider.number)", action: #selector(chooseProvider))
            item.representedObject = provider
            item.state = provider == settings.provider ? .on : .off
            if !provider.isAvailable {
                item.isEnabled = false
                item.subtitle = provider.detail
            }
            menu.addItem(item)
        }

        // Only the browser hop uses this — including ⌘↩ from any provider —
        // so it stays reachable but visibly separate.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Open in browser with"))
        for engine in SearchEngine.allCases {
            let item = self.item(engine.label, action: #selector(chooseEngine))
            item.representedObject = engine
            item.state = engine == settings.engine ? .on : .off
            menu.addItem(item)
        }

        if controller.isResultVisible {
            menu.addItem(.separator())
            let again = item("Search Again", symbol: "arrow.clockwise", key: "r", action: #selector(searchAgain))
            again.isEnabled = controller.offersRetry
            menu.addItem(again)
            let copy = item("Copy Answer", symbol: "doc.on.doc", key: "c", modifiers: [.command, .shift], action: #selector(copyAnswer))
            copy.isEnabled = !controller.answer.isEmpty
            menu.addItem(copy)
            if controller.offersPageToggle {
                menu.addItem(item(
                    controller.prefersWebPage ? "Show Answer" : "Show Google's Page",
                    symbol: controller.prefersWebPage ? "text.alignleft" : "globe",
                    action: #selector(togglePage)
                ))
            }
        }
        if controller.showsPanel {
            if !controller.isResultVisible { menu.addItem(.separator()) }
            menu.addItem(item("New Chat", symbol: "square.and.pencil", key: "n", action: #selector(newChat)))
        }

        // AI Mode without an account is the CAPTCHA-prone path; the fix is
        // one click away, so offer it where the choice is made.
        if settings.provider == .aiMode, !GoogleSession.shared.isConnected {
            menu.addItem(.separator())
            menu.addItem(item("Connect Google Account…", symbol: "person.crop.circle.badge.plus", action: #selector(connectGoogle)))
        }
        return menu
    }

    private func item(
        _ title: String,
        symbol: String? = nil,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        action: Selector
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    // MARK: - Actions

    @objc private func chooseProvider(_ item: NSMenuItem) {
        if let provider = item.representedObject as? ProviderKind { settings.provider = provider }
    }

    @objc private func chooseEngine(_ item: NSMenuItem) {
        if let engine = item.representedObject as? SearchEngine { settings.engine = engine }
    }

    @objc private func searchAgain() { controller?.retry() }
    @objc private func copyAnswer() { controller?.copyAnswer() }
    @objc private func togglePage() { controller?.prefersWebPage.toggle() }
    @objc private func newChat() { controller?.newChat() }

    @objc private func connectGoogle() {
        SettingsNavigation.showGoogleAccount()
    }
}

/// Where the provider menu opens: a plain view behind the chip, the chip's
/// size, that clicks pass straight through.
struct ProviderMenuAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        ProviderMenu.shared.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        ProviderMenu.shared.anchor = view
    }

    private final class AnchorView: NSView {
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
